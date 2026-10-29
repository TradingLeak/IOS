#!/usr/bin/env python3
"""Render a basic, self-hosted Vietnam raster map from a licensed OSM extract.
No requests to public tile servers. Output: PNG/TMS MBTiles, zoom 5..13 by default.
This is a deliberately simple road/water/place style, not OpenStreetMap Carto.
"""
import argparse
import gc
import io
import json
import math
import multiprocessing
import sqlite3
import time
from pathlib import Path

import osmium
from PIL import Image, ImageDraw, ImageFont, ImageChops
from shapely import wkb, clip_by_rect
from shapely.geometry import Polygon, LineString, Point, box, MultiPolygon
from shapely.ops import unary_union
from shapely.prepared import prep

ATTRIBUTION = "© OpenStreetMap contributors (ODbL) · Extract: Geofabrik · Style: VietMap Basic"
ROAD = {
    "motorway": (5, 7), "trunk": (5, 6), "primary": (7, 5), "secondary": (8, 4),
    "tertiary": (9, 3), "unclassified": (11, 2), "residential": (11, 2),
    "living_street": (12, 1), "service": (13, 1), "track": (13, 0),
    "path": (13, 0), "footway": (13, 0), "cycleway": (13, 0), "pedestrian": (12, 1),
}


def project(lon, lat):
    lat = max(-85, min(85, lat))
    return ((lon + 180) / 360, (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2)


def unproject(x, y):
    return (x * 360 - 180, math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y)))))


def country_polygon(path):
    """Read a Geofabrik .poly including islands and holes, in Web Mercator units."""
    lines = path.read_text().splitlines()[1:]
    outers, holes = [], []
    index = 0
    while index < len(lines):
        name = lines[index].strip()
        index += 1
        if not name:
            continue
        if name == "END":
            break
        points = []
        while index < len(lines) and lines[index].strip() != "END":
            values = lines[index].split()
            index += 1
            if len(values) == 2:
                points.append(project(float(values[0]), float(values[1])))
        index += 1
        if len(points) >= 3:
            polygon = Polygon(points).buffer(0)
            (holes if name.startswith("!") else outers).append(polygon)
    if not outers:
        raise ValueError("No outer rings in Vietnam extract polygon")
    result = unary_union(outers)
    if holes:
        result = result.difference(unary_union(holes))
    # Technical envelope, not an administrative boundary or sovereignty statement.
    west, north = project(102, 24)
    east, south = project(118, 6)
    result = result.intersection(box(west, north, east, south)).buffer(0)
    if result.is_empty:
        raise ValueError("Extract polygon does not intersect Vietnam envelope")
    return result


class Indexer(osmium.SimpleHandler):
    def __init__(self, database, country):
        super().__init__()
        self.db = database
        self.country = prep(country)
        self.count = 0

    def add(self, geometry, kind, rank, zoom, name=""):
        if geometry.is_empty or not self.country.intersects(geometry):
            return
        bounds = geometry.bounds
        self.count += 1
        self.db.execute("INSERT INTO features VALUES (?,?,?,?,?,?)",
                        (self.count, kind, rank, zoom, name[:120], sqlite3.Binary(geometry.wkb)))
        self.db.execute("INSERT INTO spatial VALUES (?,?,?,?,?)",
                        (self.count, bounds[0], bounds[2], bounds[1], bounds[3]))
        if self.count % 10000 == 0:
            self.db.commit()
            print(f"Indexed {self.count:,} map features", flush=True)

    def node(self, node):
        place = node.tags.get("place")
        if place not in ("city", "town", "village", "suburb") or not node.location.valid():
            return
        name = node.tags.get("name:vi", node.tags.get("name", ""))
        if name:
            self.add(Point(project(node.location.lon, node.location.lat)), "place", 0,
                     {"city": 5, "town": 8, "suburb": 11, "village": 12}[place], name)

    def way(self, way):
        highway = way.tags.get("highway", "").removesuffix("_link")
        natural, landuse = way.tags.get("natural"), way.tags.get("landuse")
        kind = "road" if highway in ROAD else None
        if not kind and (natural == "water" or landuse == "reservoir"):
            kind = "water"
        if not kind and way.tags.get("waterway") in ("river", "canal", "stream"):
            kind = "river"
        if not kind and (natural == "wood" or landuse in ("forest", "grass", "recreation_ground") or way.tags.get("leisure") == "park"):
            kind = "park"
        if not kind:
            return
        try:
            if any(not node.location.valid() for node in way.nodes):
                return
            points = [project(node.lon, node.lat) for node in way.nodes]
            if len(points) < 2:
                return
            geometry = LineString(points)
            if kind in ("water", "park"):
                if len(points) < 4 or points[0] != points[-1]:
                    return
                geometry = Polygon(points).buffer(0)
            zoom, rank = ROAD[highway] if kind == "road" else (8 if kind == "river" else 7, 0)
            name = way.tags.get("name:vi", way.tags.get("name", way.tags.get("ref", "")))
            self.add(geometry, kind, rank, zoom, name)
        except (ValueError, osmium.InvalidLocationError):
            return


def build_index(source, index, country):
    with sqlite3.connect(index) as db:
        db.executescript("""
          PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;
          CREATE TABLE features(id INTEGER PRIMARY KEY, kind TEXT, rank INTEGER, minzoom INTEGER, name TEXT, geom BLOB);
          CREATE VIRTUAL TABLE spatial USING rtree(id,minx,maxx,miny,maxy);
        """)
        handler = Indexer(db, country)
        handler.apply_file(str(source), locations=True, idx="flex_mem")
        db.commit()
        count = handler.count
    if count == 0:
        raise ValueError("Source extract contains no supported Vietnam map features")
    print(f"Index complete: {count:,} features", flush=True)
    gc.collect()
    return count


def parts(geometry, kind):
    if geometry.geom_type == kind:
        yield geometry
    elif hasattr(geometry, "geoms"):
        for child in geometry.geoms:
            yield from parts(child, kind)


_db = _country = _font = _font_small = None


def worker_init(index, polygon, font):
    global _db, _country, _font, _font_small
    _db = sqlite3.connect(Path(index).resolve().as_uri() + "?mode=ro", uri=True)
    _country = wkb.loads(Path(polygon).read_bytes())
    _font = ImageFont.truetype(font, 24)
    _font_small = ImageFont.truetype(font, 19)


def render_tile(job):
    z, x, y = job
    n = 1 << z
    tile = box(x / n, y / n, (x + 1) / n, (y + 1) / n)
    region = _country.intersection(tile)
    scale, size = 2, 512
    factor = n * size

    def pixels(coords):
        return [((px - x / n) * factor, (py - y / n) * factor) for px, py in coords]

    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    for polygon in parts(region, "Polygon"):
        md.polygon(pixels(polygon.exterior.coords), fill=255)
        for ring in polygon.interiors:
            md.polygon(pixels(ring.coords), fill=0)
    image = Image.new("RGBA", (size, size), "#f4f2eb")
    draw = ImageDraw.Draw(image)
    margin = 24 / factor
    bounds = (x / n - margin, y / n - margin, (x + 1) / n + margin, (y + 1) / n + margin)
    rows = _db.execute("""SELECT f.kind,f.rank,f.name,f.geom FROM spatial s JOIN features f ON f.id=s.id
      WHERE s.minx<=? AND s.maxx>=? AND s.miny<=? AND s.maxy>=? AND f.minzoom<=?
      ORDER BY CASE f.kind WHEN 'park' THEN 0 WHEN 'water' THEN 1 WHEN 'river' THEN 2 WHEN 'road' THEN 3 ELSE 4 END,f.rank""",
      (bounds[2], bounds[0], bounds[3], bounds[1], z))
    labels = []
    for kind, rank, name, blob in rows:
        geometry = wkb.loads(blob)
        if kind == "place":
            if tile.covers(geometry):
                labels.append((name, geometry.x, geometry.y, True))
            continue
        geometry = clip_by_rect(geometry.simplify(0.45 / factor), *bounds)
        if geometry.is_empty:
            continue
        if kind in ("park", "water"):
            color = "#e0e9d5" if kind == "park" else "#bbdbe5"
            for polygon in parts(geometry, "Polygon"):
                draw.polygon(pixels(polygon.exterior.coords), fill=color)
                for ring in polygon.interiors:
                    draw.polygon(pixels(ring.coords), fill="#f4f2eb")
        else:
            for line in parts(geometry, "LineString"):
                points = pixels(line.coords)
                if kind == "river":
                    draw.line(points, fill="#b6d6e2", width=2 * scale)
                else:
                    width = max(1, round((0.65 + rank * 0.36) * scale * (0.7 if z < 10 else 1)))
                    draw.line(points, fill="#d6d2c8", width=width + 2, joint="curve")
                    draw.line(points, fill="#f4d8a2" if rank >= 4 else "#ffffff", width=width, joint="curve")
                    if name and z >= 12 and rank >= 2 and line.length * factor > 150:
                        point = line.interpolate(0.5, normalized=True)
                        if tile.covers(point):
                            labels.append((name, point.x, point.y, False))
    occupied = []
    # Place names first. Road labels are intentionally simple and sparse.
    for name, px, py, place in sorted(labels, key=lambda row: not row[3]):
        position = pixels([(px, py)])[0]
        font = _font if place else _font_small
        text = name[:48]
        rectangle = draw.textbbox(position, text, font=font, anchor="mm", stroke_width=3)
        if any(rectangle[0] < old[2] + 6 and rectangle[2] > old[0] - 6 and rectangle[1] < old[3] + 6 and rectangle[3] > old[1] - 6 for old in occupied):
            continue
        draw.text(position, text, font=font, anchor="mm", fill="#53625c" if place else "#8d897f",
                  stroke_width=3, stroke_fill="#f4f2eb")
        occupied.append(rectangle)
        if len(occupied) >= 16:
            break
    image.putalpha(mask)
    image = image.resize((256, 256), Image.Resampling.LANCZOS)
    out = io.BytesIO()
    image.save(out, format="PNG", compress_level=6)
    return z, x, (1 << z) - 1 - y, out.getvalue()


def build(source, poly, output, work, font, low=5, high=13, workers=2, version="1"):
    if not 0 <= low <= high <= 14:
        raise ValueError("Supported build zoom range is 0..14")
    work.mkdir(parents=True, exist_ok=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise ValueError("Output already exists; use a new filename")
    country = country_polygon(poly)
    west, north, east, south = country.bounds
    lon_west, lat_north = unproject(west, north)
    lon_east, lat_south = unproject(east, south)
    bounds = [max(102, lon_west), max(6, lat_south), min(118, lon_east), min(24, lat_north)]
    index = work / "features.sqlite"
    if index.exists():
        index.unlink()
    feature_count = build_index(source, index, country)
    polygon_file = work / "country.wkb"
    polygon_file.write_bytes(country.wkb)
    prepared = prep(country)
    jobs = []
    for z in range(low, high + 1):
        n = 1 << z
        for x in range(max(0, int(west * n)), min(n - 1, int(east * n)) + 1):
            for y in range(max(0, int(north * n)), min(n - 1, int(south * n)) + 1):
                if prepared.intersects(box(x / n, y / n, (x + 1) / n, (y + 1) / n)):
                    jobs.append((z, x, y))
    print(f"Rendering {len(jobs):,} Vietnam tiles, zoom {low}–{high}, {workers} workers", flush=True)
    metadata = dict(name="VietMap Basic — Việt Nam", country_code="VN", format="png", scheme="tms",
                    bounds=",".join(map(str, bounds)), minzoom=str(low), maxzoom=str(high),
                    attribution=ATTRIBUTION, version=version,
                    description="Basic road/water/place style; no routing graph or satellite imagery.",
                    source="https://download.geofabrik.de/asia/vietnam.html", type="baselayer")
    started = time.monotonic()
    with sqlite3.connect(output) as db:
        db.executescript("""PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;
          CREATE TABLE metadata(name TEXT PRIMARY KEY,value TEXT);
          CREATE TABLE tiles(zoom_level INTEGER,tile_column INTEGER,tile_row INTEGER,tile_data BLOB,
          PRIMARY KEY(zoom_level,tile_column,tile_row));""")
        db.executemany("INSERT INTO metadata VALUES (?,?)", metadata.items())
        with multiprocessing.get_context("spawn").Pool(workers, initializer=worker_init,
                initargs=(str(index), str(polygon_file), font)) as pool:
            for count, row in enumerate(pool.imap_unordered(render_tile, jobs, chunksize=16), 1):
                db.execute("INSERT INTO tiles VALUES (?,?,?,?)", row)
                if count % 500 == 0:
                    db.commit()
                if count % 1000 == 0:
                    print(f"Rendered {count:,}/{len(jobs):,} tiles in {time.monotonic()-started:.0f}s", flush=True)
        db.commit()
        assert db.execute("PRAGMA quick_check").fetchone()[0] == "ok"
    size = output.stat().st_size
    if size >= 1_900_000_000:
        raise ValueError("Package exceeds release budget (1.9 GB); use a lower max zoom")
    result = dict(features=feature_count, tiles=len(jobs), bytes=size, bounds=bounds, minZoom=low, maxZoom=high)
    (work / "build-report.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--polygon", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--font", default="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
    parser.add_argument("--min-zoom", type=int, default=5)
    parser.add_argument("--max-zoom", type=int, default=13)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    build(args.source, args.polygon, args.output, args.work, args.font,
          args.min_zoom, args.max_zoom, max(1, args.workers), args.version)


if __name__ == "__main__":
    main()

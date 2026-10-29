#!/usr/bin/env python3
"""Validate a pre-rendered Vietnam PNG MBTiles and publish its download manifest.

Does NOT download public OSM tiles or render .osm.pbf. Use licensed/self-hosted data.
The producer must clip the rendered content to the Vietnam polygon, including at low zoom.
"""
import argparse
import hashlib
import json
import math
import sqlite3
from pathlib import Path
from urllib.parse import urlsplit

PNG = bytes.fromhex("89504e470d0a1a0a")


def validate_source(url):
    parsed = urlsplit(url)
    host = (parsed.hostname or "").lower()
    if (parsed.scheme != "https" or not host or parsed.username or parsed.password
            or host == "openstreetmap.org" or host.endswith(".openstreetmap.org")):
        raise ValueError("Use an HTTPS offline-package host, not the public OSM tile service")


def make_manifest(path, url, version):
    validate_source(url)
    if not version or len(version) > 100:
        raise ValueError("Invalid version")
    with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as db:
        if db.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise ValueError("SQLite quick_check failed")
        meta = dict(db.execute("SELECT name,value FROM metadata"))
        if any(meta.get(k) != v for k, v in {"country_code": "VN", "format": "png", "scheme": "tms"}.items()):
            raise ValueError("Required metadata: country_code=VN, format=png, scheme=tms")
        bounds = [float(x) for x in meta["bounds"].split(",")]
        if not (len(bounds) == 4 and all(math.isfinite(x) for x in bounds)
                and 102 <= bounds[0] < bounds[2] <= 118 and 6 <= bounds[1] < bounds[3] <= 24):
            raise ValueError("Bounds must describe a Vietnam regional package, not the whole world")
        low, high = int(meta["minzoom"]), int(meta["maxzoom"])
        if not 0 <= low <= high <= 19:
            raise ValueError("Zoom must be 0..19")
        if not meta.get("attribution", "").strip():
            raise ValueError("Missing attribution")
        count = 0
        actual_low, actual_high = 20, -1
        for z, x, tms_y, signature, size in db.execute(
                "SELECT zoom_level,tile_column,tile_row,substr(tile_data,1,8),length(tile_data) FROM tiles"):
            if (not all(isinstance(v, int) for v in (z, x, tms_y)) or not low <= z <= high
                    or not 0 <= x < (1 << z) or not 0 <= tms_y < (1 << z)
                    or signature != PNG or size > 16 * 1024 * 1024):
                raise ValueError("Invalid tile coordinates, zoom, size or PNG signature")
            # Coarse envelope test only. A rectangle cannot prove polygon clipping.
            n = 1 << z
            xyz_y = n - 1 - tms_y
            west, east = x / n * 360 - 180, (x + 1) / n * 360 - 180
            north = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * xyz_y / n))))
            south = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (xyz_y + 1) / n))))
            if east <= bounds[0] or west >= bounds[2] or north <= bounds[1] or south >= bounds[3]:
                raise ValueError("Tile lies entirely outside declared Vietnam bounds")
            count += 1
            actual_low, actual_high = min(actual_low, z), max(actual_high, z)
        if count == 0 or (actual_low, actual_high) != (low, high):
            raise ValueError("Empty tiles or actual zoom range differs from metadata")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    size = path.stat().st_size
    if not 0 < size <= 50_000_000_000:
        raise ValueError("Package size must be 1 byte..50 GB")
    return dict(schemaVersion=1, countryCode="VN", version=version, downloadURL=url,
                byteCount=size, sha256=digest.hexdigest(), format="png", bounds=bounds,
                minZoom=low, maxZoom=high, attribution=meta["attribution"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mbtiles", type=Path)
    parser.add_argument("--url", required=True, help="HTTPS package URL, not a tile URL")
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        manifest = make_manifest(args.mbtiles, args.url, args.version)
    except (ValueError, KeyError, OSError, sqlite3.Error) as exc:
        parser.exit(1, f"Invalid Vietnam package: {exc}\n")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Validated package; manifest written to {args.output}")
    print("Producer must verify Vietnam polygon clipping and data/style redistribution rights before publishing.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
fetch-osm-alerts.py — tải biển báo / camera / khu dân cư / trường học từ OpenStreetMap
(Overpass API) và ghi thành tệp nguồn cho `build-alert-data.py`.

    ./scripts/fetch-osm-alerts.py                 # tải toàn quốc (chia ô 3°×3°)
    ./scripts/fetch-osm-alerts.py --self-test     # kiểm tra bộ phân tích, KHÔNG cần mạng
    ./scripts/fetch-osm-alerts.py --from-file raw.json   # phân tích một phản hồi Overpass đã lưu
    ./scripts/fetch-osm-alerts.py --dry-run       # chỉ in danh sách ô sẽ tải

Kết quả: data/curated/osm-vn.json (dữ liệu © OpenStreetMap contributors, ODbL).
Sau đó chạy:

    ./scripts/build-alert-data.py     # gộp camera TP.HCM + dữ liệu OSM → App/Resources/Data/vn_alerts.json

Ghi chú thiết kế
----------------
* Chỉ lấy các trục đường chính có tag `maxspeed` — đó mới là **biển báo thật** trên OSM.
  Chỗ OSM thiếu biển thì app tự suy ra theo TT 38/2024 lúc chạy (xem `SpeedLimitRules`),
  và hiển thị nguồn là "Ước tính TT 38/2024" để người dùng biết.
* Một way dài được lấy mẫu mỗi `--spacing` mét (mặc định 800) để không nhồi hàng chục
  nghìn điểm trùng lặp vào app.
* Mọi cảnh báo đều ghi `source`, `confidence` và `detail` nêu rõ nguồn gốc.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DEFAULT = os.path.join(ROOT, "data", "curated", "osm-vn.json")

OVERPASS = os.environ.get("OVERPASS_URL", "https://overpass-api.de/api/interpreter")
USER_AGENT = "VietMap-iOS-build/3.0 (https://github.com/TradingLeak/IOS)"

# Việt Nam — khớp LAT_RANGE/LNG_RANGE trong build-alert-data.py
BOUNDS = (7.5, 102.0, 23.6, 110.5)  # south, west, north, east

ALLOWED_SPEEDS = {20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 80, 90, 100, 110, 120}

MAJOR_ROADS = "^(motorway|trunk|primary|secondary)$"

SOURCES = [
    {
        "id": "osm",
        "name": "OpenStreetMap (Overpass API)",
        "url": "https://www.openstreetmap.org/copyright",
        "license": "ODbL 1.0 — © OpenStreetMap contributors",
        "note": "Biển giới hạn tốc độ, camera tốc độ, trường học, khu dân cư, đường ngang tàu hoả",
    }
]


# --------------------------------------------------------------------------- tiện ích


def log(message: str) -> None:
    print(message, flush=True)


def haversine(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Khoảng cách (mét) giữa hai (lat, lng)."""
    lat1, lng1 = math.radians(a[0]), math.radians(a[1])
    lat2, lng2 = math.radians(b[0]), math.radians(b[1])
    dlat, dlng = lat2 - lat1, lng2 - lng1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlng / 2) ** 2
    return 2 * 6_371_000 * math.asin(min(1.0, math.sqrt(h)))


def parse_limit(raw) -> int | None:
    """"50", "50 km/h", "50;60", "urban" → 50 (không đọc được → None)."""
    if raw is None:
        return None
    text = str(raw).strip().lower()
    if not text or text[0] not in "0123456789":
        return None
    digits = ""
    for char in text:
        if char.isdigit():
            digits += char
        else:
            break
    if not digits:
        return None
    value = int(digits)
    return value if value in ALLOWED_SPEEDS else None


def valid_coordinate(lat: float, lng: float) -> bool:
    south, west, north, east = BOUNDS
    return south <= lat <= north and west <= lng <= east


def tiles(step: float) -> list[tuple[float, float, float, float]]:
    south, west, north, east = BOUNDS
    result = []
    lat = south
    while lat < north:
        lng = west
        while lng < east:
            result.append((lat, lng, min(lat + step, north), min(lng + step, east)))
            lng += step
        lat += step
    return result


# --------------------------------------------------------------------------- Overpass


def build_query(box: tuple[float, float, float, float]) -> str:
    south, west, north, east = box
    bbox = f"{south:.4f},{west:.4f},{north:.4f},{east:.4f}"
    return (
        "[out:json][timeout:180];\n"
        "(\n"
        f'  way["highway"~"{MAJOR_ROADS}"]["maxspeed"]({bbox});\n'
        f'  node["highway"="speed_camera"]({bbox});\n'
        f'  node["enforcement"="speed"]({bbox});\n'
        f'  node["amenity"="school"]({bbox});\n'
        f'  node["railway"="level_crossing"]({bbox});\n'
        ");\n"
        "out body geom;\n"
    )


def build_residential_query(box: tuple[float, float, float, float]) -> str:
    south, west, north, east = box
    bbox = f"{south:.4f},{west:.4f},{north:.4f},{east:.4f}"
    return (
        "[out:json][timeout:180];\n"
        f'way["landuse"="residential"]({bbox});\n'
        "out center;\n"
    )


def fetch(query: str, attempt: int = 0) -> dict:
    data = urllib.parse.urlencode({"data": query}).encode("utf-8")
    request = urllib.request.Request(OVERPASS, data=data, headers={
        "User-Agent": USER_AGENT,
        "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
    })
    try:
        with urllib.request.urlopen(request, timeout=240) as response:
            return json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        if attempt >= 3:
            raise RuntimeError(f"Overpass lỗi sau 4 lần thử: {error}") from error
        wait = 5 * (attempt + 1) + random.random() * 3
        log(f"    ! lỗi ({error}) — thử lại sau {wait:.0f}s")
        time.sleep(wait)
        return fetch(query, attempt + 1)


# --------------------------------------------------------------------------- phân tích


def way_length_and_points(geometry: list[dict], spacing: float) -> list[tuple[float, float]]:
    """Lấy mẫu một way mỗi `spacing` mét, trả về toạ độ các điểm."""
    points = [
        (float(node["lat"]), float(node["lon"]))
        for node in geometry
        if "lat" in node and "lon" in node
    ]
    if len(points) < 2:
        return []

    samples = [points[0]]
    distance = 0.0
    for index in range(1, len(points)):
        segment = haversine(points[index - 1], points[index])
        if segment <= 0:
            continue
        travelled = 0.0
        while distance + (segment - travelled) >= spacing:
            need = spacing - distance
            travelled += need
            ratio = travelled / segment
            lat = points[index - 1][0] + (points[index][0] - points[index - 1][0]) * ratio
            lng = points[index - 1][1] + (points[index][1] - points[index - 1][1]) * ratio
            samples.append((lat, lng))
            distance = 0.0
        distance += segment - travelled
    return samples


def bearing_of(geometry: list[dict]) -> float | None:
    if len(geometry) < 2:
        return None
    first, second = geometry[0], geometry[1]
    try:
        lat1, lng1 = math.radians(float(first["lat"])), math.radians(float(first["lon"]))
        lat2, lng2 = math.radians(float(second["lat"])), math.radians(float(second["lon"]))
    except (KeyError, TypeError, ValueError):
        return None
    d_lng = lng2 - lng1
    y = math.sin(d_lng) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(d_lng)
    return round((math.degrees(math.atan2(y, x)) + 360) % 360, 1)


def road_name(tags: dict) -> str:
    name = tags.get("name") or tags.get("ref") or ""
    return str(name).strip()[:80]


def parse_elements(elements: list[dict], spacing: float, residential: bool) -> list[dict]:
    """Chuyển phản hồi Overpass thành danh sách cảnh báo theo schema vn_alerts.json."""
    alerts: list[dict] = []
    for element in elements:
        tags = element.get("tags") or {}
        element_type = element.get("type")

        # --- camera tốc độ ---
        if element_type == "node" and (tags.get("highway") == "speed_camera"
                                       or tags.get("enforcement") == "speed"):
            lat, lng = element.get("lat"), element.get("lon")
            if lat is None or lng is None:
                continue
            alerts.append({
                "id": f"osm-cam-{element.get('id')}",
                "kind": "speed_camera",
                "lat": round(float(lat), 6),
                "lng": round(float(lng), 6),
                "name": tags.get("name") or "Camera tốc độ (OSM)",
                "road": road_name(tags),
                "detail": "Camera bắn tốc độ — nguồn OpenStreetMap",
                "confidence": 0.7,
                "source": "osm",
            })
            continue

        # --- trường học ---
        if element_type == "node" and tags.get("amenity") == "school":
            lat, lng = element.get("lat"), element.get("lon")
            if lat is None or lng is None:
                continue
            alerts.append({
                "id": f"osm-school-{element.get('id')}",
                "kind": "school_zone",
                "lat": round(float(lat), 6),
                "lng": round(float(lng), 6),
                "name": tags.get("name") or "Trường học",
                "detail": "Khu vực trường học — nguồn OpenStreetMap",
                "confidence": 0.6,
                "source": "osm",
            })
            continue

        # --- đường ngang tàu hoả ---
        if element_type == "node" and tags.get("railway") == "level_crossing":
            lat, lng = element.get("lat"), element.get("lon")
            if lat is None or lng is None:
                continue
            alerts.append({
                "id": f"osm-rail-{element.get('id')}",
                "kind": "hazard",
                "lat": round(float(lat), 6),
                "lng": round(float(lng), 6),
                "name": "Đường ngang tàu hoả",
                "detail": "Giao cắt đường sắt — đi chậm, quan sát hai phía",
                "confidence": 0.6,
                "source": "osm",
            })
            continue

        if element_type != "way":
            continue

        # --- khu dân cư (chỉ lấy tâm way, không cần hình học) ---
        if residential and tags.get("landuse") == "residential":
            center = element.get("center") or {}
            lat, lng = center.get("lat"), center.get("lon")
            if lat is None or lng is None:
                continue
            alerts.append({
                "id": f"osm-res-{element.get('id')}",
                "kind": "residential_zone",
                "lat": round(float(lat), 6),
                "lng": round(float(lng), 6),
                "speedLimit": 60,
                "name": tags.get("name") or "Khu vực đông dân cư",
                "detail": "Khu dân cư — giới hạn 60 km/h trong đô thị (TT 38/2024)",
                "confidence": 0.5,
                "source": "osm",
            })
            continue

        # --- biển giới hạn tốc độ trên trục đường chính ---
        limit = parse_limit(tags.get("maxspeed"))
        if limit is None:
            continue
        geometry = element.get("geometry") or []
        samples = way_length_and_points(geometry, spacing)
        if not samples:
            continue
        bearing = bearing_of(geometry)
        name = road_name(tags)
        for index, (lat, lng) in enumerate(samples):
            alerts.append({
                "id": f"osm-sign-{element.get('id')}-{index}",
                "kind": "speed_sign",
                "lat": round(lat, 6),
                "lng": round(lng, 6),
                "speedLimit": limit,
                "bearing": bearing,
                "road": name,
                "name": name or f"Giới hạn {limit} km/h",
                "detail": f"Biển {limit} km/h — nguồn OpenStreetMap",
                "confidence": 0.65,
                "source": "osm",
            })

    return alerts


def dedupe(alerts: list[dict], cell: float = 400.0) -> list[dict]:
    """Bỏ cảnh báo trùng: cùng loại + cùng giới hạn trong bán kính `cell` mét."""
    kept: list[dict] = []
    buckets: set[tuple[str, int, int, int | None]] = set()
    for alert in alerts:
        key = (
            alert["kind"],
            int(alert["lat"] * 111_320 / cell),
            int(alert["lng"] * 111_320 * math.cos(math.radians(alert["lat"])) / cell),
            alert.get("speedLimit"),
        )
        if key in buckets:
            continue
        buckets.add(key)
        kept.append(alert)
    return kept


# --------------------------------------------------------------------------- nguồn


def collect(spacing: float, step: float, residential: bool, max_alerts: int) -> list[dict]:
    alerts: list[dict] = []
    boxes = tiles(step)
    log(f"  {len(boxes)} ô × {step}° — bắt đầu tải Overpass ({OVERPASS})")

    for index, box in enumerate(boxes, start=1):
        label = f"{box[0]:.1f},{box[1]:.1f} → {box[2]:.1f},{box[3]:.1f}"
        try:
            payload = fetch(build_query(box))
            elements = payload.get("elements") or []
            alerts.extend(parse_elements(elements, spacing, residential=False))
            if residential:
                payload = fetch(build_residential_query(box))
                alerts.extend(parse_elements(payload.get("elements") or [], spacing, residential=True))
        except Exception as error:  # noqa: BLE001 — một ô lỗi không nên chặn cả bộ dữ liệu
            log(f"  [{index}/{len(boxes)}] {label} — LỖI: {error}")
            continue

        log(f"  [{index}/{len(boxes)}] {label} — {len(alerts)} mục")
        if len(alerts) >= max_alerts:
            log(f"  đã đạt giới hạn {max_alerts} mục — dừng tải")
            break
        time.sleep(2)

    alerts = dedupe(alerts)
    alerts = alerts[:max_alerts]
    for alert in alerts:
        if not valid_coordinate(alert["lat"], alert["lng"]):
            alert["_drop"] = True
    return [alert for alert in alerts if not alert.get("_drop")]


def write_source(alerts: list[dict], path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    dataset = {
        "source": "osm",
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "sources": SOURCES,
        "alerts": alerts,
    }
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(dataset, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")


# --------------------------------------------------------------------------- tự kiểm tra

SAMPLE = {
    "elements": [
        {
            "type": "way", "id": 111, "tags": {"highway": "primary", "maxspeed": "60",
                                                "name": "Quốc lộ 1A", "ref": "QL1"},
            "geometry": [
                {"lat": 10.8000, "lon": 106.7000},
                {"lat": 10.8090, "lon": 106.7000},   # ~1 km
                {"lat": 10.8180, "lon": 106.7000},   # ~2 km
            ],
        },
        {
            "type": "way", "id": 112, "tags": {"highway": "motorway", "maxspeed": "none"},
            "geometry": [{"lat": 21.0, "lon": 105.0}, {"lat": 21.01, "lon": 105.0}],
        },
        {"type": "node", "id": 222, "lat": 10.801, "lon": 106.701,
         "tags": {"highway": "speed_camera"}},
        {"type": "node", "id": 333, "lat": 10.802, "lon": 106.702,
         "tags": {"amenity": "school", "name": "Tiểu học Ngọc Khánh"}},
        {"type": "node", "id": 444, "lat": 10.803, "lon": 106.703,
         "tags": {"railway": "level_crossing"}},
        {"type": "way", "id": 555, "tags": {"landuse": "residential", "name": "Khu A"},
         "center": {"lat": 10.804, "lon": 106.704}},
    ]
}


def self_test() -> int:
    problems = 0

    def check(condition: bool, message: str) -> None:
        nonlocal problems
        if condition:
            print(f"  \033[32m✔\033[0m {message}")
        else:
            print(f"  \033[31m✖\033[0m {message}")
            problems += 1

    check(parse_limit("50") == 50, "đọc maxspeed '50'")
    check(parse_limit("50 km/h") == 50, "đọc maxspeed '50 km/h'")
    check(parse_limit("none") is None, "bỏ maxspeed 'none'")
    check(parse_limit("VN:urban") is None, "bỏ maxspeed dạng ký hiệu")
    check(parse_limit("999") is None, "bỏ giới hạn ngoài bảng")
    check(len(tiles(3.0)) > 0, "chia ô bbox")

    samples = way_length_and_points(SAMPLE["elements"][0]["geometry"], 800)
    check(len(samples) == 3, f"lấy mẫu way 2 km mỗi 800 m → {len(samples)} điểm")

    alerts = parse_elements(SAMPLE["elements"], 800, residential=True)
    kinds = {alert["kind"] for alert in alerts}
    check(kinds == {"speed_sign", "speed_camera", "school_zone", "hazard", "residential_zone"},
          f"đủ 5 loại cảnh báo → {sorted(kinds)}")
    signs = [alert for alert in alerts if alert["kind"] == "speed_sign"]
    check(all(alert.get("speedLimit") == 60 for alert in signs), "biển tốc độ giữ đúng 60")
    check(not any(alert["id"].startswith("osm-sign-112") for alert in alerts),
          "way không có biển thật không sinh điểm")
    check(all(valid_coordinate(alert["lat"], alert["lng"]) for alert in alerts),
          "mọi toạ độ nằm trong Việt Nam")

    merged = dedupe(alerts)
    check(len(merged) <= len(alerts), "dedupe không làm tăng số mục")

    print()
    print("  \033[32mTự kiểm tra đạt\033[0m" if not problems else "  \033[31mTự kiểm tra có lỗi\033[0m")
    return 0 if not problems else 1


# --------------------------------------------------------------------------- CLI


def main() -> int:
    parser = argparse.ArgumentParser(description="Tải biển báo / camera từ OpenStreetMap")
    parser.add_argument("--spacing", type=float, default=800, help="mét giữa hai điểm mẫu trên một way")
    parser.add_argument("--tile", type=float, default=3.0, help="cạnh ô tải (độ)")
    parser.add_argument("--max-alerts", type=int, default=60000, help="giới hạn tổng số mục")
    parser.add_argument("--no-residential", action="store_true", help="bỏ khu dân cư (nhẹ hơn)")
    parser.add_argument("--out", default=OUT_DEFAULT, help="tệp đầu ra")
    parser.add_argument("--from-file", help="phân tích phản hồi Overpass đã lưu (không gọi mạng)")
    parser.add_argument("--dry-run", action="store_true", help="chỉ in các ô sẽ tải")
    parser.add_argument("--self-test", action="store_true", help="kiểm tra bộ phân tích (offline)")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    if args.dry_run:
        boxes = tiles(args.tile)
        print(f"{len(boxes)} ô:")
        for box in boxes:
            print(f"  {box[0]:.1f},{box[1]:.1f} → {box[2]:.1f},{box[3]:.1f}")
        return 0

    if args.from_file:
        with open(args.from_file, encoding="utf-8") as handle:
            payload = json.load(handle)
        alerts = dedupe(parse_elements(payload.get("elements") or [], args.spacing,
                                       residential=not args.no_residential))
    else:
        alerts = collect(args.spacing, args.tile, not args.no_residential, args.max_alerts)

    counts: dict[str, int] = {}
    for alert in alerts:
        counts[alert["kind"]] = counts.get(alert["kind"], 0) + 1

    write_source(alerts, args.out)
    print(f"\n  Đã ghi {len(alerts)} mục → {os.path.relpath(args.out, ROOT)}")
    for kind, count in sorted(counts.items()):
        print(f"    - {kind:<18} {count:>6}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

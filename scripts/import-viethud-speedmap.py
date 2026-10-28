#!/usr/bin/env python3
"""
import-viethud-speedmap.py — chuyển bộ dữ liệu nhị phân SpeedMap của dự án VietHUD
(`cameras.bin`, `signs.bin`, `metadata.bin`, `tiles.bin`) sang JSON của app này.

    ./scripts/import-viethud-speedmap.py --from-dir /tmp/viethud/speedmap \
        --kinds speed_sign,residential,camera,traffic_light --out data/curated/viethud.json

    ./scripts/import-viethud-speedmap.py --from-dir … --report   # chỉ in thống kê

Định dạng nhị phân (đọc từ `src/map/SpeedMapFormat.h` của VietHUD, little-endian, pack 1):

    CameraPoint[]     20 B: uint64 id, int32 latE7, int32 lonE7, int16 speed, uint16 dirDeg
    TrafficSignHeader 20 B: "VNSG", uint16 version, uint32 count, uint16 pad, uint32 crc, uint32 ts
    TrafficSignPoint[]20 B: uint32 id, int32 latE7, int32 lonE7, uint16 dirDeg,
                            uint8 type, uint8 speed, uint8 subType, uint8 flags, uint16 pad
    RoadSegment[]     28 B: uint32 id, 4×int32 toạ độ E7, uint16 heading, uint8 roadClass,
                            uint8 direction, int16 speed, uint8 source, uint8 flags

Loại biển (TrafficSignType): 1 giới hạn tốc độ, 2 khu dân cư, 3 cấm vượt, 4 camera,
5 trạm thu phí, 6 đèn tín hiệu, 10 nguy hiểm khác.

GIẤY PHÉP — ĐỌC KỸ TRƯỚC KHI PHÁT HÀNH
--------------------------------------
* `tiles.bin` / `metadata.bin` được sinh từ OpenStreetMap (metadata ghi rõ
  "(c) OpenStreetMap contributors, ODbL").
* `cameras.bin` / `signs.bin` trong repo VietHUD được tài liệu của chính dự án đó ghi là
  **trích xuất từ ứng dụng WYN** (`docs/VIETHUD_FW_2.2.0.md`), và repo VietHUD **không có
  tệp giấy phép**. Đây là dữ liệu của bên thứ ba, không phải OSM.
* Vì vậy công cụ này chỉ dùng để **tự chuyển đổi cho mục đích cá nhân / thử nghiệm**;
  không nên đóng gói kết quả vào bản phát hành công khai nếu bạn không có quyền.
  Dùng `--license-ack` để buộc phải xác nhận lại điều này.
"""
from __future__ import annotations

import argparse
import json
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CAMERA_FMT = "<QiihH"
SIGN_HEADER_FMT = "<4sHIHII"
SIGN_FMT = "<IiiHBBBBH"
SEGMENT_FMT = "<IiiiiHBBhBB"

assert struct.calcsize(CAMERA_FMT) == 20
assert struct.calcsize(SIGN_HEADER_FMT) == 20
assert struct.calcsize(SIGN_FMT) == 20
assert struct.calcsize(SEGMENT_FMT) == 28

ALLOWED_SPEEDS = {20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 80, 90, 100, 110, 120}

# TrafficSignType → AlertKind của app
SIGN_KIND = {
    1: "speed_sign",
    2: "residential_zone",
    3: "no_overtake",
    4: "speed_camera",
    5: "toll_station",
    6: "traffic_light",
    10: "hazard",
}

KIND_ALIASES = {
    "speed": "speed_sign",
    "speed_sign": "speed_sign",
    "residential": "residential_zone",
    "residential_zone": "residential_zone",
    "no_overtake": "no_overtake",
    "camera": "speed_camera",
    "speed_camera": "speed_camera",
    "toll": "toll_station",
    "toll_station": "toll_station",
    "traffic_light": "traffic_light",
    "light": "traffic_light",
    "hazard": "hazard",
}


def vn_coordinate(lat: float, lng: float) -> bool:
    return 7.5 <= lat <= 23.6 and 102.0 <= lng <= 110.5


def read_cameras(path: str) -> list[dict]:
    data = open(path, "rb").read()
    alerts = []
    for offset in range(0, len(data) - 20 + 1, 20):
        camera_id, lat, lng, speed, direction = struct.unpack(CAMERA_FMT, data[offset:offset + 20])
        lat, lng = lat / 1e7, lng / 1e7
        if not vn_coordinate(lat, lng):
            continue
        alert = {
            "id": f"vnsm-cam-{camera_id}",
            "kind": "speed_camera",
            "lat": round(lat, 6),
            "lng": round(lng, 6),
            "name": "Camera tốc độ",
            "detail": "Camera bắn tốc độ (bộ dữ liệu SpeedMap)",
            "confidence": 0.75,
            "source": "viethud-speedmap",
        }
        if speed in ALLOWED_SPEEDS:
            alert["speedLimit"] = speed
        if direction != 0xFFFF and 0 <= direction < 360:
            alert["bearing"] = float(direction)
        alerts.append(alert)
    return alerts


def read_signs(path: str) -> tuple[list[dict], dict]:
    data = open(path, "rb").read()
    magic, version, count, _pad, _crc, _ts = struct.unpack(SIGN_HEADER_FMT, data[:20])
    if magic != b"VNSG":
        raise SystemExit(f"{path}: không phải tệp VNSG (magic={magic!r})")

    alerts: list[dict] = []
    per_type: dict[int, int] = {}
    for index in range(20, min(len(data), 20 + count * 20), 20):
        sign_id, lat, lng, direction, sign_type, speed, sub_type, _flags, _r = \
            struct.unpack(SIGN_FMT, data[index:index + 20])
        lat, lng = lat / 1e7, lng / 1e7
        per_type[sign_type] = per_type.get(sign_type, 0) + 1
        if not vn_coordinate(lat, lng):
            continue
        kind = SIGN_KIND.get(sign_type)
        if kind is None:
            continue
        # subType 1 = hết hiệu lực (hết giới hạn / hết khu dân cư) — app chưa mô hình hoá.
        if sub_type == 1:
            continue
        # Biển tốc độ không có giá trị km/h hợp lệ thì bỏ (app bắt buộc speed_sign có speedLimit).
        if kind == "speed_sign" and speed not in ALLOWED_SPEEDS:
            continue

        alert = {
            "id": f"vnsm-sign-{sign_id}",
            "kind": kind,
            "lat": round(lat, 6),
            "lng": round(lng, 6),
            "name": {
                "speed_sign": f"Biển {speed} km/h" if speed in ALLOWED_SPEEDS else "Biển giới hạn tốc độ",
                "residential_zone": "Khu đông dân cư",
                "no_overtake": "Cấm vượt",
                "speed_camera": "Camera phạt nguội",
                "toll_station": "Trạm thu phí",
                "traffic_light": "Đèn tín hiệu",
                "hazard": "Điểm nguy hiểm",
            }[kind],
            "detail": "Bộ dữ liệu SpeedMap",
            "confidence": 0.7 if kind != "hazard" else 0.5,
            "source": "viethud-speedmap",
        }
        if speed in ALLOWED_SPEEDS:
            alert["speedLimit"] = speed
        elif kind == "residential_zone":
            alert["speedLimit"] = 60
        if direction != 0xFFFF and 0 <= direction < 360:
            alert["bearing"] = float(direction)
        alerts.append(alert)
    return alerts, per_type


def read_segments(path: str) -> list[dict]:
    """Mạng đường OSM kèm giới hạn tốc độ — dùng làm `speed_zone` (có độ dài)."""
    data = open(path, "rb").read()
    alerts = []
    for index in range(0, len(data) - 28 + 1, 28):
        seg_id, a, b, c, d, _heading, _cls, _dir, speed, _src, _flags = \
            struct.unpack(SEGMENT_FMT, data[index:index + 28])
        lat, lng = a / 1e7, b / 1e7
        if speed not in ALLOWED_SPEEDS or not vn_coordinate(lat, lng):
            continue
        alerts.append({
            "id": f"vnsm-seg-{seg_id}",
            "kind": "speed_zone",
            "lat": round(lat, 6),
            "lng": round(lng, 6),
            "speedLimit": speed,
            "length": 60,
            "detail": "Giới hạn tốc độ theo đoạn đường OSM",
            "confidence": 0.6,
            "source": "viethud-speedmap",
        })
    return alerts


def dedupe(alerts: list[dict], cell: float = 25.0) -> list[dict]:
    """Bỏ trùng: cùng kind + cùng speedLimit trong ô ~25 m (camera và biển hay trùng nhau)."""
    import math
    seen: set[tuple] = set()
    kept: list[dict] = []
    for alert in alerts:
        lat_scale = 111_320.0
        lng_scale = 111_320.0 * math.cos(math.radians(alert["lat"]))
        key = (alert["kind"],
               int(alert["lat"] * lat_scale / cell),
               int(alert["lng"] * lng_scale / cell),
               alert.get("speedLimit"))
        if key in seen:
            continue
        seen.add(key)
        kept.append(alert)
    return kept


def main() -> int:
    parser = argparse.ArgumentParser(description="Chuyển SpeedMap .bin của VietHUD sang JSON của app")
    parser.add_argument("--from-dir", required=True, help="thư mục chứa cameras.bin / signs.bin")
    parser.add_argument("--out", default=os.path.join(ROOT, "data", "imports", "viethud-speedmap.json"))
    parser.add_argument("--kinds", default="speed_sign,residential,camera,traffic_light,toll,hazard,no_overtake",
                        help="danh sách loại muốn lấy, cách nhau bởi dấu phẩy")
    parser.add_argument("--include-tiles", action="store_true",
                        help="kèm speed_zone từ tiles.bin (mạng đường OSM)")
    parser.add_argument("--max", type=int, default=0, help="giới hạn số mục (0 = không giới hạn)")
    parser.add_argument("--report", action="store_true", help="chỉ in thống kê, không ghi tệp")
    parser.add_argument("--compact", action="store_true",
                        help="bỏ tên/ghi chú lặp lại trong từng mục (nhẹ hơn ~3 lần)")
    parser.add_argument("--license-ack", action="store_true",
                        help="xác nhận bạn tự chịu trách nhiệm về nguồn dữ liệu (xem docstring)")
    args = parser.parse_args()

    if not args.license_ack:
        print("Dừng: dữ liệu cameras.bin/signs.bin có nguồn gốc từ ứng dụng WYN, repo gốc không có\n"
              "giấy phép. Đọc phần GIẤY PHÉP trong docstring; thêm --license-ack nếu bạn đã xác nhận.",
              file=sys.stderr)
        return 2

    wanted = {KIND_ALIASES.get(item.strip().lower(), item.strip().lower())
              for item in args.kinds.split(",") if item.strip()}

    alerts: list[dict] = []
    counts: dict[str, int] = {}

    cameras_path = os.path.join(args.from_dir, "cameras.bin")
    if os.path.isfile(cameras_path) and "speed_camera" in wanted:
        cameras = read_cameras(cameras_path)
        counts["cameras.bin"] = len(cameras)
        alerts.extend(cameras)

    signs_path = os.path.join(args.from_dir, "signs.bin")
    if os.path.isfile(signs_path):
        signs, per_type = read_signs(signs_path)
        counts["signs.bin"] = len(signs)
        for sign_type, number in sorted(per_type.items()):
            counts[f"type {sign_type} ({SIGN_KIND.get(sign_type, 'bỏ qua')})"] = number
        alerts.extend(alert for alert in signs if alert["kind"] in wanted)

    if args.include_tiles:
        tiles_path = os.path.join(args.from_dir, "tiles.bin")
        if os.path.isfile(tiles_path):
            zones = read_segments(tiles_path)
            counts["tiles.bin"] = len(zones)
            alerts.extend(zones)

    if args.compact:
        for alert in alerts:
            for key in ("name", "detail", "confidence", "source"):
                alert.pop(key, None)

    before = len(alerts)
    alerts = dedupe(alerts)
    if args.max:
        alerts = alerts[:args.max]

    by_kind: dict[str, int] = {}
    for alert in alerts:
        by_kind[alert["kind"]] = by_kind.get(alert["kind"], 0) + 1

    print(f"  đọc      : {counts}")
    print(f"  sau lọc  : {len(alerts)} mục (bỏ {before - len(alerts)} trùng)")
    print(f"  theo loại: {dict(sorted(by_kind.items()))}")

    if args.report:
        return 0

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    dataset = {
        "source": "viethud-speedmap",
        "sources": [{
            "id": "viethud-speedmap",
            "name": "Bộ dữ liệu SpeedMap (VietHUD) — trích xuất từ ứng dụng WYN",
            "url": "https://github.com/911273/VietHUD/tree/main/speedmap",
            "license": "Không rõ / không có giấy phép — dùng cho mục đích cá nhân",
            "note": "Toạ độ khớp mạng đường OSM (trung vị 3 m). Không phát hành công khai nếu chưa có quyền.",
        }],
        "alerts": alerts,
    }
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(dataset, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")
    size_mb = os.path.getsize(args.out) / 1024 / 1024
    print(f"  đã ghi   : {os.path.relpath(args.out, ROOT)} ({size_mb:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

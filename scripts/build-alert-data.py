#!/usr/bin/env python3
"""
build-alert-data.py — gộp các nguồn dữ liệu cảnh báo giao thông Việt Nam
thành MỘT tệp JSON nhúng vào app: App/Resources/Data/vn_alerts.json

Chạy (không cần Xcode, chỉ cần Python 3):

    ./scripts/build-alert-data.py            # sinh lại App/Resources/Data/vn_alerts.json
    ./scripts/build-alert-data.py --check    # chỉ kiểm tra tệp đã commit (dùng trong CI)

Nguồn dữ liệu
-------------
data/sources/*.json   Dữ liệu thô tải sẵn trong repo (camera TP.HCM, ...)
data/curated/*.json   Dữ liệu do bạn tự bổ sung: vùng tốc độ, biển báo, trạm thu phí...

Schema chung của mỗi cảnh báo (xem docs/ALERTS.md):

    {
      "id": "cam-abc",                 # duy nhất, bắt buộc
      "kind": "surveillance_camera",   # xem ALERT_KINDS
      "lat": 10.804985,                # bắt buộc
      "lng": 106.752707,               # bắt buộc
      "speedLimit": 60,                # km/h, tuỳ chọn (vùng/biển tốc độ)
      "bearing": 120,                  # hướng áp dụng 0..360, tuỳ chọn (thiếu = cả 2 chiều)
      "length": 800,                   # mét, độ dài vùng (chỉ với speed_zone)
      "road": "Mai Chí Thọ",
      "name": "Tên hiển thị",
      "district": "Thành phố Thủ Đức",
      "ward": "Phường An Khánh",
      "detail": "ghi chú ngắn",
      "imageUrl": "https://...",       # ảnh camera (nếu có)
      "videoUrl": "https://...",       # luồng HLS (nếu có)
      "bearing": 0,
      "confidence": 0.9,               # 0..1, độ tin cậy
      "source": "hcm-portal",
      "updatedAt": "2026-10-17"
    }
"""
from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "App", "Resources", "Data", "vn_alerts.json")
SOURCES_DIR = os.path.join(ROOT, "data", "sources")
CURATED_DIR = os.path.join(ROOT, "data", "curated")
IMPORTS_DIR = os.path.join(ROOT, "data", "imports")

SCHEMA_VERSION = 2
DATASET_VERSION = "2.0.0"

# Phải khớp với enum AlertKind trong App/Sources/Models/AlertModels.swift
ALERT_KINDS = {
    "speed_camera",
    "red_light_camera",
    "surveillance_camera",
    "speed_sign",
    "speed_zone",
    "residential_zone",
    "no_overtake",
    "toll_station",
    "school_zone",
    "checkpoint",
    "hazard",
    "traffic_light",
    "other",
}

CAMERA_KINDS = {"speed_camera", "red_light_camera", "surveillance_camera"}

# Việt Nam (kèm vùng biển đảo, Phú Quốc, Trường Sa được bỏ qua vì không có dữ liệu)
LAT_RANGE = (7.5, 23.6)
LNG_RANGE = (102.0, 110.5)

ALLOWED_SPEEDS = {20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 80, 90, 100, 110, 120}


def fail(message: str) -> None:
    print("  \033[31m✖\033[0m " + message, file=sys.stderr)
    raise SystemExit(1)


def warn(message: str) -> None:
    print("  \033[33m!\033[0m " + message)


def ok(message: str) -> None:
    print("  \033[32m✔\033[0m " + message)


def read_json(path: str):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def normalize(entry: dict, default_source: str, where: str) -> dict:
    """Chuẩn hoá + kiểm tra một cảnh báo. Trả về dict đã gọn."""
    if not isinstance(entry, dict):
        fail("%s: mục không phải object" % where)

    kind = str(entry.get("kind", "")).strip().lower()
    if kind not in ALERT_KINDS:
        fail("%s: kind không hợp lệ %r (cho phép: %s)" % (where, kind, ", ".join(sorted(ALERT_KINDS))))

    try:
        lat = float(entry["lat"])
        lng = float(entry["lng"])
    except (KeyError, TypeError, ValueError):
        fail("%s: thiếu toạ độ lat/lng" % where)

    if not (LAT_RANGE[0] <= lat <= LAT_RANGE[1] and LNG_RANGE[0] <= lng <= LNG_RANGE[1]):
        fail("%s: toạ độ ngoài Việt Nam (%.5f, %.5f)" % (where, lat, lng))

    alert_id = str(entry.get("id") or "").strip()
    if not alert_id:
        fail("%s: thiếu id" % where)
    if len(alert_id) > 80:
        fail("%s: id quá dài (tối đa 80 ký tự)" % where)

    result = {
        "id": alert_id,
        "kind": kind,
        "lat": round(lat, 6),
        "lng": round(lng, 6),
    }

    speed = entry.get("speedLimit", entry.get("speed_limit"))
    if speed is not None:
        try:
            speed = int(speed)
        except (TypeError, ValueError):
            fail("%s: speedLimit không phải số nguyên" % where)
        if speed not in ALLOWED_SPEEDS:
            fail("%s: speedLimit %d km/h không nằm trong bảng hợp lệ" % (where, speed))
        result["speedLimit"] = speed

    bearing = entry.get("bearing")
    if bearing is not None:
        try:
            bearing = float(bearing) % 360
        except (TypeError, ValueError):
            fail("%s: bearing không phải số" % where)
        result["bearing"] = round(bearing, 1)

    length = entry.get("length")
    if length is not None:
        try:
            length = int(length)
        except (TypeError, ValueError):
            fail("%s: length không phải số nguyên" % where)
        if not 10 <= length <= 50000:
            fail("%s: length phải trong 10..50000 mét" % where)
        result["length"] = length

    for key in ("road", "name", "district", "ward", "detail", "imageUrl", "videoUrl", "updatedAt"):
        value = entry.get(key)
        if value:
            result[key] = str(value)[:400]

    confidence = entry.get("confidence")
    if confidence is not None:
        try:
            confidence = float(confidence)
        except (TypeError, ValueError):
            fail("%s: confidence không phải số" % where)
        if not 0 <= confidence <= 1:
            fail("%s: confidence phải trong 0..1" % where)
        result["confidence"] = round(confidence, 2)

    result["source"] = str(entry.get("source") or default_source)[:60]

    # Kiểm tra chéo: vùng tốc độ phải có speedLimit
    if kind == "speed_zone" and "speedLimit" not in result:
        fail("%s: speed_zone bắt buộc có speedLimit" % where)
    if kind == "speed_sign" and "speedLimit" not in result:
        fail("%s: speed_sign bắt buộc có speedLimit" % where)

    return result


def road_from_name(name: str) -> str:
    """'Mai Chí Thọ - Võ Nguyên Giáp (Cát Lái cầu A)' -> 'Mai Chí Thọ'."""
    text = (name or "").strip()
    for separator in (" – ", " - ", " –", "- "):
        if separator in text:
            text = text.split(separator, 1)[0]
            break
    return text.strip()[:80]


def load_cameras() -> tuple[list[dict], dict]:
    """Camera TP.HCM (nguồn đã tải sẵn trong data/sources/cameras-hcm.json)."""
    path = os.path.join(SOURCES_DIR, "cameras-hcm.json")
    if not os.path.isfile(path):
        warn("không có data/sources/cameras-hcm.json — bỏ qua camera TP.HCM")
        return [], {}

    payload = read_json(path)
    cameras = payload.get("cameras") or []
    if len(cameras) < 300:
        fail("cameras-hcm.json chỉ có %d camera — dữ liệu có vẻ hỏng" % len(cameras))

    alerts = []
    for camera in cameras:
        name = str(camera.get("name") or "Camera giao thông")
        entry = {
            "id": "cam-" + str(camera.get("id", "")).strip(),
            "kind": "surveillance_camera",
            "lat": camera.get("latitude"),
            "lng": camera.get("longitude"),
            "name": name,
            "road": road_from_name(name),
            "district": camera.get("district") or camera.get("oldProvince") or "",
            "ward": camera.get("ward") or "",
            "imageUrl": camera.get("imageUrl") or "",
            "videoUrl": camera.get("videoUrl") or "",
            "detail": "Camera giám sát giao thông (ảnh cập nhật từ cổng TP.HCM)",
            "confidence": 0.9,
            "source": "hcm-portal",
            "updatedAt": str(payload.get("updatedAt") or "")[:10],
        }
        alerts.append(normalize(entry, "hcm-portal", "cameras-hcm.json"))

    source = {
        "id": "hcm-portal",
        "name": "Cổng thông tin giao thông TP.HCM",
        "url": "https://giaothong.hochiminhcity.gov.vn/Map.aspx",
        "license": "Danh mục cộng đồng MIT (tranlong5252) + dữ liệu công khai của cổng",
        "note": "%d camera giám sát, đồng bộ %s" % (len(alerts), str(payload.get("updatedAt") or "?")[:10]),
    }
    return alerts, source


def load_curated() -> tuple[list[dict], list[dict]]:
    alerts: list[dict] = []
    sources: dict[str, dict] = {}

    for path in sorted(glob.glob(os.path.join(CURATED_DIR, "*.json"))):
        if os.path.basename(path).endswith(".example.json"):
            continue
        payload = read_json(path)
        default_source = str(payload.get("source") or os.path.basename(path).replace(".json", ""))
        for index, entry in enumerate(payload.get("alerts") or []):
            where = "%s[%d]" % (os.path.basename(path), index)
            alerts.append(normalize(entry, default_source, where))
        for source in payload.get("sources") or []:
            if isinstance(source, dict) and source.get("id"):
                sources[str(source["id"])] = source

    return alerts, list(sources.values())


def load_imports() -> tuple[list[dict], list[dict]]:
    """Dữ liệu người dùng tự chuyển đổi (vd. SpeedMap .bin → JSON).

    Chỉ nhúng khi chạy `--with-imports`: các tệp này thường không có giấy phép rõ ràng
    nên mặc định không vào bản phát hành (xem docs/DATA-SPEEDMAP.md).
    """
    alerts: list[dict] = []
    sources: dict[str, dict] = {}

    for path in sorted(glob.glob(os.path.join(IMPORTS_DIR, "*.json"))):
        payload = read_json(path)
        default_source = str(payload.get("source") or os.path.basename(path).replace(".json", ""))
        for index, entry in enumerate(payload.get("alerts") or []):
            where = "%s[%d]" % (os.path.basename(path), index)
            item = dict(entry)
            item.setdefault("source", default_source)
            alerts.append(normalize(item, default_source, where))
        for source in payload.get("sources") or []:
            if isinstance(source, dict) and source.get("id"):
                sources[str(source["id"])] = source

    return alerts, list(sources.values())


def build(with_imports: bool = False) -> dict:
    camera_alerts, camera_source = load_cameras()
    curated_alerts, curated_sources = load_curated()
    import_alerts, import_sources = load_imports() if with_imports else ([], [])

    alerts = camera_alerts + curated_alerts + import_alerts

    seen: dict[str, int] = {}
    for alert in alerts:
        seen[alert["id"]] = seen.get(alert["id"], 0) + 1
    duplicates = [key for key, count in seen.items() if count > 1]
    if duplicates:
        fail("id trùng: %s" % ", ".join(duplicates[:5]))

    # Lọc trùng gần như tuyệt đối (cùng kind, cách nhau < 8 m) — hay gặp khi gộp nhiều nguồn.
    alerts.sort(key=lambda item: (item["kind"], item["lat"], item["lng"]))

    sources = [camera_source] if camera_source else []
    sources.extend(curated_sources)
    sources.extend(import_sources)
    if not sources:
        sources = [{
            "id": "vietmap-app",
            "name": "Bộ dữ liệu mẫu của ứng dụng",
            "url": "https://github.com/TradingLeak/IOS",
            "license": "MIT",
            "note": "%d mục" % len(alerts),
        }]

    counts: dict[str, int] = {}
    for alert in alerts:
        counts[alert["kind"]] = counts.get(alert["kind"], 0) + 1

    return {
        "schema": SCHEMA_VERSION,
        "version": DATASET_VERSION,
        "generatedAt": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "sources": sources,
        "counts": counts,
        "alerts": alerts,
    }


def write_dataset(dataset: dict) -> None:
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    handle, temp_path = tempfile.mkstemp(dir=os.path.dirname(OUTPUT), suffix=".json")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(dataset, stream, ensure_ascii=False, separators=(",", ":"), sort_keys=False)
            stream.write("\n")
        os.replace(temp_path, OUTPUT)
    except BaseException:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        raise


def check() -> None:
    if not os.path.isfile(OUTPUT):
        fail("chưa có %s — chạy ./scripts/build-alert-data.py" % os.path.relpath(OUTPUT, ROOT))

    dataset = read_json(OUTPUT)
    for key in ("schema", "version", "sources", "alerts"):
        if key not in dataset:
            fail("vn_alerts.json thiếu khoá %r" % key)

    alerts = dataset["alerts"]
    if len(alerts) < 100:
        fail("vn_alerts.json chỉ có %d cảnh báo — quá ít" % len(alerts))

    seen = set()
    for index, alert in enumerate(alerts):
        where = "alerts[%d]" % index
        if alert.get("kind") not in ALERT_KINDS:
            fail("%s: kind lạ %r" % (where, alert.get("kind")))
        if alert["id"] in seen:
            fail("%s: id trùng %r" % (where, alert["id"]))
        seen.add(alert["id"])
        if not (LAT_RANGE[0] <= alert["lat"] <= LAT_RANGE[1]):
            fail("%s: lat ngoài Việt Nam" % where)
        if not (LNG_RANGE[0] <= alert["lng"] <= LNG_RANGE[1]):
            fail("%s: lng ngoài Việt Nam" % where)
        if "speedLimit" in alert and alert["speedLimit"] not in ALLOWED_SPEEDS:
            fail("%s: speedLimit lạ %r" % (where, alert["speedLimit"]))

    size_kb = os.path.getsize(OUTPUT) / 1024
    ok("vn_alerts.json hợp lệ: %d cảnh báo, %.0f KB, sinh lúc %s"
       % (len(alerts), size_kb, dataset.get("generatedAt", "?")))
    for kind, count in sorted((dataset.get("counts") or {}).items()):
        print("      - %-20s %5d" % (kind, count))


def main() -> None:
    parser = argparse.ArgumentParser(description="Gộp dữ liệu cảnh báo giao thông Việt Nam")
    parser.add_argument("--check", action="store_true", help="chỉ kiểm tra tệp đã commit")
    parser.add_argument("--with-imports", action="store_true",
                        help="nhúng thêm data/imports/*.json (dữ liệu tự chuyển đổi, không rõ giấy phép)")
    args = parser.parse_args()

    print("\n\033[1mDữ liệu cảnh báo giao thông Việt Nam\033[0m")
    if args.check:
        check()
        return

    dataset = build(with_imports=args.with_imports)
    write_dataset(dataset)
    check()


if __name__ == "__main__":
    main()

# Nhập bộ dữ liệu SpeedMap (.bin) của VietHUD

Bộ dữ liệu nhị phân trong
[`911273/VietHUD/speedmap`](https://github.com/911273/VietHUD/tree/main/speedmap) chứa
biển báo, camera, đèn tín hiệu và mạng đường kèm giới hạn tốc độ. Tài liệu này ghi lại
định dạng, cách chuyển sang JSON của app, và **vấn đề giấy phép** cần biết trước khi dùng.

## 1. Định dạng (đọc từ `src/map/SpeedMapFormat.h`)

Little-endian, `#pragma pack(1)`, toạ độ là `int32` độ × 1e7.

| Tệp | Bản ghi | Kích thước | Ghi chú |
|---|---|---|---|
| `metadata.bin` | `SpeedMapMetadata` | 140 B | magic `SLMP`, `region`, `tileSizeDeg`, `attribution` |
| `index.bin` | `TileIndexEntry` | 28 B/ô | chỉ mục ô lưới 0,01° |
| `tiles.bin` | `RoadSegment` | 28 B/đoạn | mạng đường + `speedLimitKmh`, `roadClass`, `flags` |
| `cameras.bin` | `CameraPoint` | 20 B/điểm | `id`, toạ độ, tốc độ, hướng quét (`0xFFFF` = mọi hướng) |
| `signs.bin` | `TrafficSignHeader` + `TrafficSignPoint` | 20 B + 20 B/điểm | magic `VNSG`, `signType`, `speedLimitKmh`, `subType` |
| `names.bin`, `seg_names.bin` | `VNNM` | — | từ điển tên đường (không dùng trong app này) |

`signType`: 1 biển tốc độ (P.127), 2 khu dân cư (R.420/421), 3 cấm vượt (P.125),
4 camera, 5 trạm thu phí (P.135), 6 đèn tín hiệu, 10 nguy hiểm khác.
`subType = 1` là điểm **hết hiệu lực** — công cụ bỏ qua vì app chưa mô hình hoá.

## 2. Chuyển đổi

```bash
git clone --depth 1 https://github.com/911273/VietHUD /tmp/viethud

# chỉ xem thống kê
python3 scripts/import-viethud-speedmap.py \
  --from-dir /tmp/viethud/speedmap --report --license-ack

# xuất JSON để nhập vào app
python3 scripts/import-viethud-speedmap.py \
  --from-dir /tmp/viethud/speedmap --license-ack --compact \
  --out data/imports/viethud-speedmap.json
```

Kết quả đọc từ bản 2026.10.24 (93.021 điểm sau khi bỏ trùng 25 m):

| Loại | Số điểm |
|---|---|
| Biển giới hạn tốc độ | 36.300 |
| Khu đông dân cư | 25.102 |
| Đèn tín hiệu | 15.148 |
| Điểm nguy hiểm | 7.784 |
| Camera tốc độ | 7.144 |
| Cấm vượt | 1.543 |

Độ chính xác: đối chiếu 885 camera và 6.000 biển trong vùng Hà Nội với mạng đường OSM
(`tiles.bin`) cho **trung vị 3 m, 99% trong 15 m** — toạ độ dùng được, không lệch hệ quy chiếu.
(Lưu ý: tài liệu cũ của VietHUD nói bản trích xuất WYN cũ lệch ~1 km và có điểm ngoài biển;
bản 2026.10 đã hết lỗi đó.)

## 3. Nhập vào app không cần build lại

App đã có sẵn chức năng nhập dữ liệu: **Cảnh báo → Dữ liệu → Nhập tệp JSON**
(`AlertsSheet` → `MapViewModel.importAlerts(from:)`). Chỉ cần chép tệp JSON vào ứng dụng
**Files** trên iPhone rồi chọn tệp. Dữ liệu nằm trong `Documents/imported-alerts.json`,
không ghi vào bundle và không gửi đi đâu.

## 4. ⚠️ Giấy phép

- `tiles.bin` / `metadata.bin`: sinh từ **OpenStreetMap**, metadata ghi
  `(c) OpenStreetMap contributors, ODbL` — dùng được, giữ ghi công ODbL.
- `cameras.bin` / `signs.bin`: tài liệu của chính VietHUD
  (`docs/VIETHUD_FW_2.2.0.md`, `docs/QUY_TRINH_CAP_NHAT_DU_LIEU_SPEEDMAP.md`) ghi rõ dữ liệu
  **trích xuất từ ứng dụng WYN** (kể cả tệp âm thanh tiếng Việt lấy từ `wyn_assets/`), và
  **repo VietHUD không có tệp LICENSE**.
- Vì vậy việc đóng gói vào IPA phát hành công khai là **phân phối lại dữ liệu của bên thứ ba**
  khi chưa có phép.
- **Quyết định của chủ dự án (2026-10-28): vẫn nhúng.** Từ 3.1, `data/imports/viethud-speedmap.json`
  (8,4 MB → 82.608 điểm) được commit và gộp vào `App/Resources/Data/vn_alerts.json` (108.528 điểm,
  17 MB). Trách nhiệm về quyền sử dụng thuộc về người phát hành.
- Muốn bỏ: xoá tệp trong `data/imports/` rồi chạy lại `build-alert-data.py`; app trở về
  25.920 điểm OSM + camera TP.HCM.

## 5. Thay thế hợp pháp

Những gì bộ dữ liệu này bổ sung đều có nguồn ODbL tương ứng, pipeline `fetch-osm-alerts.py`
đã lấy được phần lớn:

```bash
python3 scripts/fetch-osm-alerts.py --residential-only --tile 3   # khu dân cư
```

Đèn tín hiệu (`highway=traffic_signals`) và camera (`highway=speed_camera`) có thể bật thêm
trong cùng pipeline — phủ ít hơn WYN nhưng giấy phép rõ ràng.

# Thư mục dữ liệu cảnh báo

```
data/
├── sources/                      # dữ liệu thô tải sẵn (chỉ đọc, ghi rõ nguồn + giấy phép)
│   ├── cameras-hcm.json          # 795 camera giao thông TP.HCM
│   └── CAMERAS-NOTICES.md        # giấy phép/nguồn của danh mục camera
└── curated/                      # dữ liệu bạn tự bổ sung (biển báo, vùng tốc độ, trạm phí…)
    └── speed-zones.example.json  # tệp mẫu — KHÔNG được nạp (script bỏ qua *.example.json)
```

## Sinh bộ dữ liệu nhúng

```bash
python3 scripts/build-alert-data.py           # → App/Resources/Data/vn_alerts.json
python3 scripts/build-alert-data.py --check   # chỉ kiểm tra tệp đã commit (CI dùng lệnh này)
```

Script gộp `sources/*.json` + `curated/*.json`, kiểm tra toạ độ/id/speedLimit rồi ghi **một**
tệp JSON nhúng vào app. Tệp sinh ra được commit vào repo để build không cần mạng.

## Thêm dữ liệu địa phương

1. Sao chép `curated/speed-zones.example.json` → `curated/<tỉnh-thành>.json`.
2. Sửa `source`, `sources[].name`, rồi thêm các mục thật (id duy nhất, `lat/lng` chính xác).
3. Chạy `python3 scripts/build-alert-data.py` và commit cả tệp nguồn lẫn
   `App/Resources/Data/vn_alerts.json`.

Định dạng đầy đủ: [docs/ALERTS.md](../docs/ALERTS.md).

> Người dùng cuối **không cần** build lại app để thêm dữ liệu: chỉ cần nhập tệp JSON trong
> app (Cảnh báo → Dữ liệu → Nhập JSON).

## Giấy phép & nguồn

| Nguồn | Nội dung | Giấy phép |
|---|---|---|
| [Cổng thông tin giao thông TP.HCM](https://giaothong.hochiminhcity.gov.vn/Map.aspx) | Danh mục 795 camera (tên, toạ độ, URL ảnh/video) | Dữ liệu công khai của cổng; danh mục cộng đồng MIT (`tranlong5252`) |
| Ranh giới quận/phường trong danh mục camera | Trường `district` / `ward` | © OpenStreetMap contributors, ODbL 1.0 |
| OpenStreetMap (tải trong app) | `maxspeed`, `highway=speed_camera` | © OpenStreetMap contributors, ODbL 1.0 |
| Thông tư 38/2024/TT-BGTVT | Bảng tốc độ mặc định (mã nguồn, không phải dữ liệu) | Văn bản quy phạm pháp luật |

App **không** đóng gói hình ảnh/video camera và không tái phân phối chúng: ảnh được tải trực
tiếp từ máy chủ của cổng khi người dùng mở chi tiết camera.

Xem thêm [`sources/CAMERAS-NOTICES.md`](sources/CAMERAS-NOTICES.md).

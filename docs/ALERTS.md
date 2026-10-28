# Cảnh báo giao thông & dữ liệu tốc độ / camera

Tài liệu này mô tả tính năng cảnh báo của **VietMap 2.0**: nguồn dữ liệu, định dạng JSON,
cách nhập/xuất, cách app chọn giới hạn tốc độ, và những giới hạn cần biết.

---

## 1. App cảnh báo những gì?

| Nhóm | `kind` | Ghi chú |
|---|---|---|
| Camera bắn tốc độ | `speed_camera` | Cảnh báo theo chiều đi nếu có `bearing` |
| Camera đèn đỏ | `red_light_camera` | |
| Camera giám sát | `surveillance_camera` | Camera giao thông (không phải máy bắn tốc độ) |
| Biển giới hạn tốc độ | `speed_sign` | Bắt buộc có `speedLimit` |
| Vùng giới hạn tốc độ | `speed_zone` | Bắt buộc có `speedLimit`, nên có `length` (mét) |
| Khu đông dân cư (R.420/R.421) | `residential_zone` | Có thể kèm `speedLimit` |
| Cấm vượt (P.125/DP.133) | `no_overtake` | |
| Trạm thu phí | `toll_station` | |
| Khu vực trường học | `school_zone` | |
| Điểm kiểm tra tốc độ | `checkpoint` | |
| Sự cố / ngập | `hazard` | |
| Khác | `other` | Mọi `kind` lạ đều được đọc thành `other` |

Mỗi cảnh báo được cảnh báo theo 3 kênh:

1. **Trên bản đồ**: ghim camera/cảnh báo dọc tuyến (bật/tắt trong Cài đặt).
2. **Băng cảnh báo + HUD**: hiện khoảng cách còn lại và biển giới hạn.
3. **Giọng nói tiếng Việt** (AVSpeechSynthesizer, chạy offline).

---

## 2. Ngưỡng cảnh báo động `D_warn`

Công thức lấy từ các HUD dẫn đường Việt Nam, tính theo tốc độ hiện tại:

```
D_warn = clamp(v_kmh × 3,0 m; 150 m; 500 m)
```

- Đi 40 km/h → 150 m (sàn).
- Đi 80 km/h → 240 m.
- Đi 170 km/h trở lên → 500 m (trần).

Cảnh báo chỉ đọc lên khi còn cách ≤ `D_warn` và mỗi cảnh báo có **cooldown 60 giây**
(cảnh báo vượt tốc độ: 45 giây) để không nói lặp.

---

## 3. App lấy giới hạn tốc độ từ đâu?

Theo thứ tự ưu tiên:

1. **Vùng giới hạn** (`speed_zone`) đang chứa vị trí hiện tại.
2. **Biển báo** (`speed_sign`) hoặc **khu đông dân cư** đã đi qua gần nhất.
3. **Bảng mặc định theo Thông tư 38/2024/TT-BGTVT** (hiệu lực 01/01/2025), suy ra từ tên
   đường trong chỉ dẫn của Apple Maps:

| Xe | Trong khu đông dân cư (đường đôi / ≥2 làn) | (2 chiều / 1 làn) | Ngoài khu đông dân cư (đôi) | (2 chiều) |
|---|---|---|---|---|
| Xe mô tô / xe máy trên 50 cm³ | 60 | 50 | 70 | 60 |
| Xe gắn máy ≤ 50 cm³, xe đạp điện | 40 | 40 | 40 | 40 |
| Ô tô con | 60 | 50 | 90 | 80 |
| Đường cao tốc (ô tô) | — | — | 120 | 120 |
| Xe máy trên cao tốc | **không được phép đi** | | | |

> Bảng này là **giá trị luật định mặc định**, không thay thế biển báo thực tế. App hiển thị
> rõ nguồn: `Biển báo`, `Vùng giới hạn`, `Ước tính TT 38/2024`.

Chọn nhóm xe ở **Cài đặt → Dẫn đường xe máy → Nhóm xe hai bánh**:

- **Xe mô tô** (mặc định): áp bảng 60/50 – 70/60 như trên.
- **Xe gắn máy ≤ 50 cm³ / xe đạp điện**: luôn **40 km/h** (Điều 8 Thông tư 38/2024),
  không áp dụng mức 60/70 kể cả trên đường đôi hay quốc lộ.

Nhận diện loại đường từ tên: `cao tốc / CT` → cao tốc; `quốc lộ / QL` → quốc lộ;
`tỉnh lộ / ĐT` → tỉnh lộ; `phố / đường` → đường đô thị; `hẻm / ngõ / kiệt` → hẻm.

---

## 4. Nguồn dữ liệu

### 4.1 Camera giao thông TP.HCM (có sẵn trong app)

- **795 camera** giám sát giao thông, cập nhật 2026-10-17.
- Nguồn: danh mục cộng đồng [`MeoPaoo/camera-giao-thong-data`](https://github.com/MeoPaoo/camera-giao-thong-data)
  (giấy phép MIT cho danh mục, tác giả gốc `tranlong5252`), đồng bộ từ
  [Cổng thông tin giao thông TP.HCM](https://giaothong.hochiminhcity.gov.vn/Map.aspx).
- App chỉ lưu **tên + toạ độ + URL ảnh**, không đóng gói ảnh/video. Ảnh trong app được tải
  trực tiếp từ máy chủ của cổng.
- Đây là **camera giám sát**, không phải danh sách máy bắn tốc độ của cơ quan chức năng.

### 4.2 OpenStreetMap (tải khi cần)

Trong **Cảnh báo → Dữ liệu → Tải biển tốc độ từ OpenStreetMap**, app gọi Overpass API cho
khu vực quanh tuyến đang chọn:

- `highway=speed_camera`, `enforcement=speed` → camera.
- `maxspeed` trên `way` → vùng giới hạn (mốc = điểm đầu của way, `length` = độ dài way,
  tối đa 5 km).

Dữ liệu © OpenStreetMap contributors, **ODbL 1.0**. Độ phủ `maxspeed` ở Việt Nam còn thấp
(cao tốc ~89%, quốc lộ ~20%, đường phố rất ít) — vì vậy app luôn có bảng mặc định ở mục 3.

### 4.3 Dữ liệu bạn tự nhập

Xem mục 5. Bạn có thể nhập tay biển báo, vùng tốc độ, camera ở địa phương mình.

---

## 5. Định dạng JSON

Một tệp có thể chứa toàn bộ hoặc một phần các trường sau:

```json
{
  "schema": 2,
  "version": "2.0.0",
  "sources": [
    {"id": "cua-toi", "name": "Dữ liệu tổ dân phố", "license": "CC0"}
  ],
  "alerts": [
    {
      "id": "zone-cau-giay-1",
      "kind": "speed_zone",
      "lat": 21.0333,
      "lng": 105.8000,
      "speedLimit": 50,
      "length": 800,
      "bearing": 180,
      "road": "Xuân Thuỷ",
      "name": "Vùng 50 km/h Xuân Thuỷ",
      "detail": "Từ ngã tư đến cầu",
      "confidence": 0.8,
      "source": "cua-toi"
    },
    {
      "id": "cam-nga-tu-kim-ma",
      "kind": "speed_camera",
      "lat": 21.0310,
      "lng": 105.8020,
      "bearing": 270,
      "name": "Camera tốc độ Kim Mã"
    }
  ]
}
```

### Quy tắc trường

| Trường | Bắt buộc | Ý nghĩa |
|---|---|---|
| `id` | ✅ | Duy nhất. Trùng id → mục mới thay mục cũ |
| `kind` | ✅ | Xem bảng ở mục 1 |
| `lat`, `lng` | ✅ | WGS-84, phải nằm trong Việt Nam (8–24°B, 102–110,5°Đ) |
| `speedLimit` | với `speed_sign` / `speed_zone` | km/h, một trong 20…120 |
| `length` | nên có với `speed_zone` | Chiều dài vùng (m), vùng bắt đầu tại `lat/lng` và kéo dài **theo chiều đi** |
| `bearing` | không | Hướng áp dụng 0–360° (0 = Bắc). Bỏ trống = cả hai chiều |
| `road`, `name`, `detail` | không | Hiển thị trong danh sách / HUD |
| `imageUrl` | không | Ảnh minh hoạ (chỉ `http/https`) |
| `confidence` | không | 0–1, hiện trong chi tiết |
| `source` | không | Khoá nguồn, hiển thị ở phần “Nguồn dữ liệu” |

Giá trị số có thể viết dạng chuỗi (`"speedLimit": "50"` vẫn đọc được), dấu phẩy thập phân
cũng được hiểu.

Ví dụ đầy đủ: [`data/curated/speed-zones.example.json`](../data/curated/speed-zones.example.json).

---

## 6. Nhập / xuất / tải dữ liệu

- **Nhập**: mở app → nút **camera** trên bản đồ (hoặc Cài đặt → Cảnh báo → *Quản lý dữ liệu*) →
  tab **Dữ liệu** → *Nhập JSON* → chọn tệp trong Files/iCloud.
  Dữ liệu được lưu vào `Documents/imported-alerts.json` của app (không nằm trong bundle).
- **Xuất**: cùng màn hình → *Xuất toàn bộ dữ liệu* → AirDrop/Files.
- **Xoá dữ liệu đã nhập**: chỉ xoá phần bạn nhập/OSM, giữ bộ camera có sẵn.
- Dòng dữ liệu hỏng (toạ độ sai) bị bỏ qua và app báo số dòng đã bỏ.

---

## 7. Sinh lại bộ dữ liệu nhúng

```bash
python3 scripts/build-alert-data.py           # gộp data/sources + data/curated → App/Resources/Data/vn_alerts.json
python3 scripts/build-alert-data.py --check   # chỉ kiểm tra (CI chạy bước này)
```

Quy trình cập nhật camera TP.HCM: tải `docs/cameras.json` mới từ
`MeoPaoo/camera-giao-thong-data` → ghi đè `data/sources/cameras-hcm.json` → chạy script trên
→ commit cả hai tệp.

Script sẽ **dừng và không ghi** nếu: thiếu < 300 camera, id trùng, toạ độ ngoài Việt Nam,
`speedLimit` lạ, hoặc `speed_zone` thiếu `speedLimit`.

---

## 8. Giới hạn & pháp lý

- Ứng dụng **không** phải thiết bị đo tốc độ. Giới hạn hiển thị có thể lệch so với biển báo
  thực tế; người lái luôn phải tuân theo biển báo và hiệu lệnh của CSGT.
- Việc cảnh báo vị trí camera không bị pháp luật Việt Nam cấm; app hiển thị dòng
  “dữ liệu tham khảo” trong phần Nguồn dữ liệu.
- Toàn bộ tính toán cảnh báo chạy **trên máy**, không gửi vị trí đi đâu — app không có
  máy chủ riêng và không có tính năng nào gửi dữ liệu ra ngoài.
- Mức phạt tham khảo (Nghị định 168/2024/NĐ-CP, xe máy): vượt 5–10 km/h phạt 800.000 –
  1.000.000 đ; 10–20 km/h phạt 4–6 triệu và tước GPLX 1–3 tháng; trên 20 km/h phạt 6–8
  triệu, tước GPLX 1–3 tháng.

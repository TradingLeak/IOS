# VietMap — Demo HTML để duyệt giao diện

## Mở ngay

- Mở trực tiếp **`VietMap-demo.html`** trong trình duyệt: file độc lập, không cần cài gì,
  không cần máy chủ hoặc kết nối Internet.
- Hoặc chạy source để sửa giao diện:

```bash
# Chạy từ thư mục gốc repository
python3 -m http.server 8080 --bind 0.0.0.0 --directory demo
```

Mở trang của server trên cổng 8080. Trên Arena, dùng Live Preview đã được mở cho phiên này.

## Các luồng có thể duyệt

1. **Bản đồ:** nguồn Apple Maps mặc định, ghim/tuyến minh hoạ Hà Nội, phóng to và về vị trí.
2. **Chuyển sang OSM:** bấm Apple Maps → OpenStreetMap. Nếu chưa tải, hiện yêu cầu tải gói Việt Nam.
3. **Tải dữ liệu:** bấm tải, thử huỷ rồi tải lại. Sau khoảng 5 giây và bước kiểm tra giả lập,
   nhận trạng thái hoàn tất và có thể mở OSM. Không tải file hoặc thực sự kiểm tra SHA-256.
4. **Tìm địa điểm:** có 4 địa điểm mẫu, hỗ trợ tìm tên tiếng Việt không dấu. Đổi điểm đến chỉ đổi tên;
   đường trên sơ đồ vẫn là minh hoạ, không tính lại tuyến thật.
5. **Bắt đầu:** mô phỏng đếm khoảng cách đến camera; bấm Kết thúc để dừng.
6. **HUD:** kéo thanh tốc độ, vượt 62 km/h để thấy cảnh báo ở giới hạn 60; thử GPS và phản chiếu.
7. **Dữ liệu:** quản lý trạng thái gói, xoá để xem lại trải nghiệm chưa có bản đồ.
8. **Cài đặt:** đổi nguồn, Wi-Fi, giọng nói, phản chiếu và đặt lại toàn bộ demo.

Trạng thái nguồn bản đồ, đã tải và tuỳ chọn được lưu bằng **localStorage** nếu trình duyệt cho phép.
Nếu chặn localStorage thì demo vẫn chạy, nhưng không lưu được giữa các lần mở.

## Giới hạn quan trọng

Đây là **prototype giao diện**, không phải bản port iOS chạy thật:

- Sơ đồ vẽ bằng SVG tự tạo, không lấy dữ liệu từ Apple Maps hoặc OpenStreetMap.
- Vị trí, tốc độ, biển báo, camera, lộ trình, ETA và dung lượng 1,26 GB đều minh hoạ.
- Không xin quyền GPS, không gọi API, không tải MBTiles, không dùng microphone hoặc giọng nói.
- Tuỳ chọn giữ sáng/Wi-Fi/âm thanh chỉ mô phỏng trạng thái, không điều khiển thiết bị.
- Không dùng demo để lái xe hoặc làm bằng chứng dữ liệu bản đồ đã đầy đủ.
- Không cần CDN, font bên ngoài, ảnh ngoài hoặc kết nối mạng sau khi mở file độc lập.

Chức năng iOS thật được triển khai riêng trong `App/`; blocker gói MBTiles Việt Nam thật vẫn
được mô tả ở `docs/OFFLINE-MAPS.md`. Demo không giải quyết nguồn hoặc giấy phép phân phối gói.

## Chỉnh sửa và xuất lại

Nguồn chính: `index.html`, `styles.css`, `app.js`. Sau khi sửa:

```bash
python3 demo/build-standalone.py
node --check demo/app.js
```

`VietMap-demo.html` là deliverable tạo từ ba file nguồn để người dùng tải/mở trực tiếp.
Thay đổi demo không làm thay đổi giao diện SwiftUI hoặc tạo IPA.

## Kiểm tra đã chạy

Kiểm thử trình duyệt Chromium tự động cho: chuyển nguồn, thiếu dữ liệu, tải/huỷ/xác minh giả lập,
lưu trạng thái sau reload, tìm mẫu không dấu, bắt đầu/kết thúc, vượt tốc, mất GPS, phản chiếu,
lưu tuỳ chọn, xoá gói và reset. Không có lỗi JavaScript hoặc request tới host bên ngoài.
Đã kiểm tra không tràn ngang ở độ rộng 320, 390, 768 và 1440 px; HUD trên khung desktop vừa màn hình.
Chưa kiểm thử Safari hoặc thiết bị iPhone thật.

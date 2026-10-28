# Demo giao diện VietMap 3.0

Bản dựng **HTML một file** để duyệt bố cục trước khi sửa Swift và build IPA.

```bash
# cách 1: mở trực tiếp
open demo/index.html

# cách 2: chạy server (dùng được trên điện thoại cùng Wi-Fi)
cd demo && python3 -m http.server 8000
```

## Demo có gì

- **Không còn HUD**: biển giới hạn tốc độ (P.127), camera phạt nguội/đèn đỏ/giám sát,
  vùng trường học 40 km/h vẽ **trực tiếp trên bản đồ**.
- **Cảnh báo bám điểm**: callout khoảng cách đếm lùi, viền đỏ + rung khi vượt tốc độ.
- **Bản đồ 3D/2D**: nghiêng + xoay theo hướng đi, zoom theo tốc độ, kéo để xem trước.
- **Tuyến thông minh**: 3 phương án, điểm 0–100, tab *Nhanh nhất / Ít camera / Tránh cao tốc*,
  phí cầu đường, giờ tới nơi.
- **AI tuỳ chọn**: nhập câu tiếng Việt → JSON ý định → tuyến; tắt AI vẫn chạy bằng parser offline.
- **Kịch bản mô phỏng**: chạy xe, vượt tốc độ, đi lệch tuyến, tới nơi.

## Không phải bản build

Đây là prototype UI (SVG + JS thuần, không thư viện, không gọi mạng, không dùng dữ liệu thật).
Sau khi duyệt, các thay đổi sẽ được viết lại bằng SwiftUI/MapKit trong `App/Sources`.

# Demo giao diện VietMap 3.0

Bản dựng **HTML một file** để duyệt bố cục trước khi sửa Swift và build IPA.

```bash
# cách 1: mở trực tiếp file (không cần server)
open demo/index.html

# cách 2: chạy server kèm sẵn cho preview / điện thoại cùng Wi-Fi
python3 demo/serve.py            # → http://<ip-máy>:8000
python3 demo/serve.py 8080       # đổi cổng
```

`serve.py` là server tĩnh nhỏ (chuẩn hoá `charset=utf-8`, `Cache-Control: no-store`,
mọi đường dẫn lạ đều trả `index.html`) để preview không bị lỗi font tiếng Việt hoặc hiện
bản demo cũ sau khi sửa file.

## Demo có gì

- **Không còn HUD**: biển giới hạn tốc độ (P.127), camera phạt nguội/đèn đỏ/giám sát,
  vùng trường học 40 km/h vẽ **trực tiếp trên bản đồ**.
- **Cảnh báo bám điểm**: callout khoảng cách đếm lùi, viền đỏ + rung khi vượt tốc độ.
- **Bản đồ 3D/2D**: nghiêng + xoay theo hướng đi, zoom theo tốc độ, kéo để xem trước.
- **Tuyến thông minh**: 3 phương án, điểm 0–100, tab *Nhanh nhất / Ít camera / Tránh cao tốc*,
  phí cầu đường, giờ tới nơi.
- **AI tuỳ chọn**: nhập câu tiếng Việt → JSON ý định → tuyến; tắt AI vẫn chạy bằng parser offline.
- **Kịch bản mô phỏng**: chạy xe, vượt tốc độ, đi lệch tuyến, tới nơi.

## Kiểm tra nhanh

```bash
curl -sI http://127.0.0.1:8000/ | head -6      # 200, charset utf-8, no-store
```

Các kịch bản trong console bên phải: **Bản đồ tự do → Tìm tuyến → Bắt đầu dẫn đường →
Vượt tốc độ → Đi lệch tuyến → Tới nơi → Reset**, kèm slider tốc độ và công tắc 3D/2D,
ngày/đêm, từng lớp hiển thị.

## Không phải bản build

Đây là prototype UI (SVG + JS thuần, không thư viện, không gọi mạng, không dùng dữ liệu thật).
Sau khi duyệt, các thay đổi sẽ được viết lại bằng SwiftUI/MapKit trong `App/Sources`.

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

---

## `vietmap.html` — bản demo 3.0 (duyệt trước khi code)

Mở `http://127.0.0.1:8000/vietmap.html` (hoặc `open demo/vietmap.html`).

Mục tiêu: **giao diện dẫn đường kiểu VietMap nhưng không dùng API VietMap**, kèm
**dữ liệu biển báo / cảnh báo / camera tự có**.

Có trong bản này:

- **Thẻ chỉ dẫn 2 dòng** + thanh tiến trình tới chỗ rẽ + dòng “Sau đó…”.
- **Bảng tốc độ**: vòng cung theo tốc độ thực, biển giới hạn (tự vẽ theo QCVN 41:2019),
  chuyển đỏ + “Vượt X km/h”.
- **Banner cảnh báo** theo từng loại: biển tốc độ, khu dân cư (R.420), trường học,
  camera, đường cong nguy hiểm, trạm thu phí — kèm đếm lùi và thanh chạy.
- **Gợi ý làn đường** khi còn < 400 m tới chỗ rẽ.
- **Thanh dưới**: còn km / phút / giờ đến, Kết thúc, Báo cáo.
- **Bảng dữ liệu** (nút ổ đĩa bên phải): nguồn, giấy phép, kết quả khảo sát repo ESP32.

Nút **Chạy mô phỏng** chạy tuyến 2,4 km với 6 điểm cảnh báo thật theo thứ tự.

### Kết luận khảo sát ESP32 (ghi lại để khỏi rà lại)

| Repo | Có gì | Dữ liệu toạ độ? |
|---|---|---|
| `nhoxboo/vietmap-hud-web-flasher` | web flasher + `assets_icons.h` (icon biển báo nhúng) + BLE `0xFFF0` | không |
| `vthang87/esp32_vietmap_hud` | `output.txt` (Wireshark BLE), `log.pcap` | không |
| `daotronghieucm-afk/hud-firmware` | chỉ `README.md` 69 B | không |
| `dangkhoa116/mzd-vietnav-hud` | bridge Mazda HUD + emu ESP32, `hud_data.h` | không |
| `Tthanh2k6/moto-nav` | BLE turn-by-turn + LovyanGFX fonts | không |

Giá trị lấy được từ nhóm này **không phải dữ liệu** mà là **hợp đồng dữ liệu HUD**:
`speed_limit`, `turn_icon`, `distance_to_turn`, `exit_num`, `lanes`, `alerts`.
App sẽ xuất đúng bộ trường đó nếu sau này bật lại HUD BLE.

Dữ liệu thật dùng nguồn khác: cổng camera TP.HCM (795 điểm, đã có) + OpenStreetMap (ODbL)
+ suy luận tốc độ theo TT 38/2024 + người dùng báo camera mới.

---

## `map-style.html` — bản demo 3.2 (biển báo trên đường)

`http://127.0.0.1:8000/map-style.html`

Duyệt kiểu hiển thị mới: biển tròn trắng–đỏ + chân ghim cắm xuống đường, thẻ tốc độ khối tối
góc trái, banner cảnh báo cùng chất liệu, hai nút pill “Về giữa” / “Tắt âm cảnh báo”.
Đã duyệt và triển khai trong `App/Sources/Views/MapContainer.swift`
(`AlertMapStyle.badge`, `AlertSignAnnotationView`) và `MapScreen.speedCard`.

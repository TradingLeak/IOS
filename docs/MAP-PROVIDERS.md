# Apple Maps hoặc OpenStreetMap Việt Nam offline

## Hành vi hiện tại

- Apple Maps giữ nguyên: tiêu chuẩn/vệ tinh/giao thông Apple, không yêu cầu gói OSM.
- OSM **chỉ đọc file PNG MBTiles Việt Nam trên thiết bị**, không gọi máy chủ tile công cộng.
- Lần mở app nếu chưa có file hợp lệ: hiện màn hình tải gói Việt Nam; có thể bỏ qua để dùng Apple.
- Chọn OSM mà chưa tải: yêu cầu tải, màn hình bản đồ có nút mở lại trình tải.
- Có gói hợp lệ: lần mở sau dùng file đã lưu, không tự tải lại và không tự kiểm tra cập nhật qua mạng.
- Menu **☰ → Bản đồ → Tải bản đồ Việt Nam offline** hoặc phần Bản đồ trong Cài đặt để
  tải/cập nhật/xoá gói. Nguồn bản đồ được lưu giữa các lần mở app.
- Nếu gói bị xoá hoặc metadata/file không hợp lệ, app không coi là đã tải.

## Nguồn mặc định đã phát hành

App 1.0.1 cấu hình sẵn:
<https://github.com/TradingLeak/IOS/releases/download/offline-vietnam/manifest.json>.
Mở trình tải khi chưa có gói sẽ tự lấy metadata để hiện dung lượng trước khi xác nhận tải.

Gói đầu tiên: `20261029-1`, 854.712.320 byte (~855 MB), 58.527 PNG tile, native zoom 5–13,
được dựng từ 3.256.313 feature OSM/Geofabrik. Đây là **VietMap Basic**, style cơ bản gồm
đường, sông/closed-way hồ, một số mảng xanh và nhãn địa điểm; không đầy đủ như OSM Carto.
Mask theo polygon extract Geofabrik và envelope VN, không phải xác nhận ranh giới hành chính.

Release: <https://github.com/TradingLeak/IOS/releases/tag/offline-vietnam>.
Build dữ liệu: <https://github.com/TradingLeak/IOS/actions/runs/40815945473>.
Nguồn, giấy phép và cách tái tạo: [pipeline bản đồ](../scripts/maps/README.md).

## Phạm vi offline

| Chức năng | Apple Maps | OpenStreetMap |
| --- | --- | --- |
| Bản đồ nền | Dịch vụ Apple | PNG tile từ MBTiles Việt Nam đã tải |
| Mật độ giao thông Apple | Có tuỳ chọn | Không ghép vào OSM |
| POI/nhãn trên nền | Có thể bật/tắt POI Apple | Nằm trong ảnh PNG, không tắt riêng được |
| Tìm địa điểm/địa chỉ | Apple | Vẫn là Apple, có thể cần mạng |
| Tính tuyến/chỉ đường | Apple | Vẫn là Apple, có thể cần mạng |
| Camera/biển báo | Speedmap cục bộ | Cùng Speedmap cục bộ, không phụ thuộc MBTiles |
| Vùng bản đồ OSM | Không áp dụng | Chỉ vùng/mức zoom nhà xuất bản đã đưa vào gói Việt Nam |

MapKit vẫn là framework hiển thị cho cả hai lựa chọn. Không phải hệ thống tìm kiếm/tính tuyến
OSM offline độc lập. Muốn có tuyến offline còn cần engine routing và dữ liệu graph riêng.

## Lưu trữ và tải

- Tải một file MBTiles, hiển thị dung lượng/phiên bản từ manifest trước khi xác nhận.
- Mặc định chỉ Wi-Fi; có thể cho phép dữ liệu di động. Có tiến trình và huỷ tải.
- Giữ app mở lúc tải. Chưa triển khai background download hoặc resume phần tải dở;
  nếu bị gián đoạn thì thử lại từ đầu. File đã cài trước đó vẫn giữ nguyên.
- Tải vào file tạm, kiểm tra dung lượng/SHA-256/schema SQLite/metadata VN rồi mới ghi receipt
  nguyên tử và chuyển sang bản mới. Không nạp toàn bộ gói vào RAM.
- File ở Application Support, loại khỏi iCloud backup. Không phải cache hệ thống tự dọn.
  Gỡ app/xoá gói sẽ phải tải lại. Lúc khởi động kiểm tra file, kích thước và metadata;
  không băm lại hàng GB mỗi lần mở. Tile được kiểm tra khi đọc.
- Khi cập nhật, bản cũ vẫn tồn tại đến khi bản mới hợp lệ. Cần dung lượng trống tối thiểu
  bằng file mới + 128 MB ngoài dữ liệu cũ đang chiếm chỗ.
- MBTiles dùng TMS; reader đổi hàng XYZ của MapKit bằng `(1 << z) - 1 - y`.
- Ngoài vùng gói: không có tile. App 1.0.1 phóng ảnh tile cha cục bộ nếu zoom vượt mức gốc
  (tới zoom hiển thị 19), không thêm chi tiết và **không fallback qua Internet**.
  Camera OSM bị giới hạn theo envelope khai báo của gói. Envelope không thay polygon biên giới.

## Quyền riêng tư và nguồn

Khi tải, máy chủ manifest/file nhận IP và các thông tin HTTP thông thường. Khi đã có gói,
reader OSM không cần mạng. Các tính năng Apple Maps/AI vẫn có luồng mạng riêng.
SHA-256 bảo vệ tính toàn vẹn khi tải, không phải chữ ký xác thực nhà xuất bản;
chỉ cấu hình nguồn HTTPS đáng tin cậy và có quyền phân phối dữ liệu/style offline.

Link **© OpenStreetMap contributors** luôn hiển thị trên màn hình OSM.
Giữ attribution của style/nguồn dữ liệu khác trong manifest và giao diện quản lý gói.
Không dùng `tile.openstreetmap.org` để tải hàng loạt: client từ chối host OSM công cộng
cho việc tải gói. Thay đổi này đã bỏ lớp tile OSM trực tuyến của phiên bản trước.

## Kiểm chứng

```bash
./scripts/selfcheck.sh
python3 scripts/test_offline_map.py
```

9 test Python chạy được trên Linux với SQLite giả lập nhỏ: manifest/hash/kích thước,
VN/format, bounds, tile ngoài vùng, PNG và URL không an toàn. Không tải dữ liệu thật.

Các test Swift `MapProviderTests.swift` và `OfflineMapTests.swift` cần Xcode/Simulator:
chuyển nguồn, đọc tile TMS, checksum, khôi phục file thật qua receipt, xoá gói, thiếu/hỏng dữ liệu.
Môi trường Linux chưa biên dịch hoặc chạy được các test iOS này.

Checklist máy thật trước khi phát hành:

1. Cài mới → thấy yêu cầu tải, có thể chọn Apple; quay lại OSM vẫn yêu cầu tải.
2. Cấu hình manifest thật → thấy đúng dung lượng và phiên bản trước khi tải.
3. Huỷ/mất Wi-Fi/hết dung lượng/hash sai → không cài file dở, bản cũ không mất.
4. Tải xong, bật chế độ máy bay → mở lại, pan/zoom các vùng VN có trong gói vẫn thấy tile.
5. Đổi Apple ↔ OSM, giữ tuyến/ghim và không trùng overlay; cập nhật gói thay renderer.
6. Kiểm tra tile/nhãn mọi mức zoom, đầy đủ khu vực VN cần phục vụ và không có dữ liệu nước ngoài
   ngoài chính sách cắt polygon của nhà xuất bản.
7. Xoá gói → renderer không dùng dữ liệu cũ và có nút tải lại.
8. Attribution, xoay ngang, giọng HUD và tính năng Apple online vẫn được phân biệt rõ.

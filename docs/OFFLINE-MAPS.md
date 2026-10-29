# Chuẩn bị và phát hành gói OpenStreetMap Việt Nam

## Phần còn thiếu trước khi dùng thực tế

Cần **một file PNG MBTiles Việt Nam thực sự** và máy chủ HTTPS cho file + manifest.
Repository này chỉ triển khai reader/downloader/validator, chưa tạo bản đồ toàn Việt Nam,
chưa cấp máy chủ và chưa nhúng URL nguồn vào IPA. Không có gói giả hay link tải mẫu được
coi là dữ liệu thật. Nút tải chỉ hoạt động sau khi cấu hình nguồn hợp lệ.

Không dùng tile OSM công cộng để scrape/prefetch hàng loạt. Không đổi tên `.osm.pbf`
thành `.mbtiles`: PBF là dữ liệu thô, không phải ảnh bản đồ mà MapKit có thể đọc trực tiếp.
Vector MBTiles (`format=pbf`) cũng chưa được reader raster này hỗ trợ.

## Quy trình nhà xuất bản

1. Chọn nguồn OSM được phép xử lý/phân phối offline (ví dụ extract Việt Nam từ nhà cung cấp
   phù hợp, hoặc tự trích từ dữ liệu OSM). Kiểm tra giấy phép dữ liệu, style, font, icon.
2. Dùng pipeline render tự quản (ví dụ Mapnik) dựng tile PNG 256×256 và xuất MBTiles TMS.
3. **Cắt/mask nội dung theo polygon Việt Nam**, kể cả ở zoom thấp. Không chỉ chọn bbox:
   tile giao biên giới có thể chứa phần lãnh thổ bên ngoài. Kiểm tra phạm vi và độ phủ thực tế,
   bao gồm các khu vực cần hỗ trợ. Phạm vi cụ thể thuộc trách nhiệm nhà xuất bản.
4. Chọn mức zoom phù hợp dung lượng. Toàn quốc ở mức zoom rất cao có thể cực lớn;
   không đưa ra dung lượng/cam kết đầy đủ khi chưa đo gói thật.
5. Ghi các metadata bên dưới và bảo đảm truy vấn tile có index theo zoom/x/y.
6. Chạy validator để kiểm tra SQLite/PNG/tile envelope/zoom rồi tạo manifest SHA-256.
7. Host file và manifest trên HTTPS đáng tin cậy, đủ quota và cho phép tải file lớn.
   Nên dùng URL file bất biến theo phiên bản, cập nhật manifest sau khi file đã upload xong.
8. Ghi URL manifest thật vào `VNOfflineMapManifestURL` trong `App/Info.plist` trước build.
   Hoặc dán URL manifest trong màn hình tải để kiểm tra trên thiết bị.

Client/validator kiểm tra `countryCode=VN`, envelope trong khu vực VN và metadata;
**không thể chứng minh nội dung PNG đã cắt đúng polygon** hoặc dữ liệu toàn quốc đã đầy đủ.
Không quảng cáo “chỉ Việt Nam”/“toàn quốc đầy đủ” nếu nguồn chưa được kiểm chứng.

## MBTiles yêu cầu

Hai bảng/view SQLite chuẩn:

```sql
CREATE TABLE metadata (name TEXT PRIMARY KEY, value TEXT);
CREATE TABLE tiles (
  zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB,
  PRIMARY KEY (zoom_level, tile_column, tile_row)
);
```

Metadata bắt buộc:

| name | value |
| --- | --- |
| `country_code` | `VN` |
| `format` | `png` |
| `scheme` | `tms` |
| `bounds` | `west,south,east,north`, số hữu hạn, đúng phạm vi gói |
| `minzoom` / `maxzoom` | Số nguyên 0–19, đúng các mức zoom thực có |
| `attribution` | Ít nhất `© OpenStreetMap contributors` và thông tin nguồn/style cần thiết |

Envelope an toàn sơ bộ client chấp nhận: kinh độ 102…118, vĩ độ 6…24.
Đây chỉ là giới hạn vùng kỹ thuật, không phải mô tả ranh giới hoặc khẳng định chủ quyền.
Bounds trong manifest phải trùng metadata. Tile PNG 256×256, không phải JPEG/vector;
validator kiểm tra chữ ký PNG nhưng nhà xuất bản vẫn phải xác minh ảnh giải mã đúng.
Tổng file tối đa 50 GB trong phiên bản reader này. Không bundle MBTiles vào Git/IPA.

## Tạo manifest

```bash
python3 scripts/prepare-vietnam-map.py /path/to/vietnam.mbtiles \
  --url https://YOUR-HOST/maps/vietnam-2026-10.mbtiles \
  --version 2026-10 \
  --output /path/to/publish/manifest.json
```

`YOUR-HOST` là chỗ cần thay bằng host thật, không phải nguồn app đã cung cấp.
Script chỉ đọc/kiểm tra và tạo manifest, **không tải hoặc render dữ liệu**.

Schema JSON (hash/kích thước phải do script tính từ file thật):

| Trường | Ý nghĩa |
| --- | --- |
| `schemaVersion` | `1` |
| `countryCode` | `VN` |
| `version` | Phiên bản gói |
| `downloadURL` | URL HTTPS file MBTiles |
| `byteCount` | Kích thước chính xác theo byte |
| `sha256` | SHA-256 file, chuỗi hex 64 ký tự |
| `format` | `png` |
| `bounds` | Mảng `[west,south,east,north]` |
| `minZoom`, `maxZoom` | Mức zoom có dữ liệu |
| `attribution` | Thông tin bản quyền/nguồn |

Không nhúng mật khẩu/token vào URL manifest hoặc file phát hành công khai. Không tắt TLS.
Nguồn chưa được pin bằng chữ ký: bảo vệ máy chủ manifest, vì ai sửa được manifest cũng có thể
sửa hash. Nếu cần cập nhật tự động từ nhiều mirror, bổ sung chữ ký nhà xuất bản trước.

## Giới hạn triển khai

- Tải foreground, không resume/background transfer. Có thể thử lại từ đầu sau khi gián đoạn.
- Tải xong có kiểm tra byte count và SHA-256 streaming; chỉ ghi receipt sau khi SQLite hợp lệ.
- Receipt `.atomic` trỏ tới file UUID mới; bản cũ giữ đến lúc cài thành công. Sau đó dọn file cũ.
- Startup kiểm tra file/size/metadata chứ không băm lại hàng GB. File/tile hỏng sau cài có thể cần tải lại.
- Nguồn chưa có gói thật là blocker phát hành, không phải chức năng tự sinh bản đồ trên iPhone.

Kiểm thử trước phát hành: [MAP-PROVIDERS.md](MAP-PROVIDERS.md).

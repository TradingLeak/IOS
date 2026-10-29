# VietMap Basic: dựng gói Việt Nam từ dữ liệu OSM thật

Pipeline này thay cho việc yêu cầu người dùng tự tìm MBTiles. Không gọi/tải hàng loạt
`tile.openstreetmap.org`, không lấy file PBF rồi đổi đuôi thành MBTiles.

## Nguồn và style

- Dữ liệu: Geofabrik `vietnam-latest.osm.pbf`, kiểm tra checksum MD5 do nguồn cung cấp.
- Mask vùng: `https://download.geofabrik.de/asia/vietnam.poly`, gồm nhiều polygon và holes.
  Đây là polygon của extract, không phải ranh giới hành chính chính thức; vùng giáp biên/
  ven biển/hải đảo phụ thuộc nguồn này.
- Style tự dựng bằng Pillow: đường, sông, một số polygon nước/công viên và tên nơi chốn.
- Không có vệ tinh, nhà cửa đầy đủ, toàn bộ POI/địa chỉ hoặc graph tính tuyến offline.
- Chưa tái dựng các relation multipolygon phức tạp, nên mặt nước/land cover có thể thiếu.
- Native zoom 5–13, PNG 256×256, TMS. App mới phóng ảnh tile cha khi zoom cao hơn;
  phóng ảnh không bổ sung chi tiết. Không quảng cáo là tương đương OSM Carto đầy đủ.
- Pixel ngoài mask extract Việt Nam được đặt trong suốt, không tải cả thế giới.
- Attribution/giấy phép: [DATA-LICENSE.txt](DATA-LICENSE.txt).

## Dựng trên máy Linux

Cần Python, font DejaVu Sans, RAM/đĩa trống đủ cho extract và index. Không đưa file PBF,
SQLite trung gian hoặc MBTiles lớn vào Git.

```bash
python3 -m venv build/map-env
. build/map-env/bin/activate
pip install -r scripts/maps/requirements.txt
python scripts/maps/test_builder.py
# Tải extract/polygon từ nguồn Geofabrik và kiểm tra MD5 như trong workflow.
python -u scripts/maps/build_vietnam.py \
  --source build/map-input/vietnam-latest.osm.pbf \
  --polygon build/map-input/vietnam.poly \
  --output build/map-publish/vietnam-basic.mbtiles \
  --work build/map-work --workers 3 --min-zoom 5 --max-zoom 13 --version VERSION
```

`osmium` đọc dữ liệu tuần tự, lưu geometry vào SQLite + R-tree. Worker đọc index ở chế độ
read-only, render từng tile, áp mask vùng và lưu MBTiles. Không giữ toàn bộ ảnh quốc gia
trong RAM. Có giới hạn gói 1,9 GB để phát hành một asset GitHub Release dưới giới hạn 2 GB.
Nếu vượt giới hạn, build fail thay vì công bố gói bị cắt dở.

Sau đó dùng `scripts/prepare-vietnam-map.py` tạo manifest với byte count và SHA-256 thật.
Các test nhỏ dựng OSM XML → spatial index → PNG/TMS → validator, kiểm tra alpha ngoài vùng.
Dữ liệu fixture không được đưa vào gói phát hành thật.

## GitHub Actions

Workflow `build-vietnam-map.yml` chạy bằng `workflow_dispatch` hoặc commit có marker
`[map-data]` thay đổi pipeline. Job dữ liệu có timeout 180 phút; không đồng nghĩa với
cam kết thời gian thực tế. Mạng nguồn, mật độ dữ liệu và CPU có thể khiến render lâu.

Luồng publish:

1. Tải extract và `.poly`, xác minh MD5.
2. Index/render toàn vùng và ghi báo cáo.
3. Kiểm tra SQLite, zoom, tile PNG/envelope, SHA-256.
4. Upload file MBTiles theo tên phiên bản bất biến + giấy phép + báo cáo.
5. **Upload `manifest.json` cuối cùng**, sau khi asset MBTiles đã có.

Release dữ liệu: `offline-vietnam` trong repository này. URL mặc định app mới:
`https://github.com/TradingLeak/IOS/releases/download/offline-vietnam/manifest.json`.
Không coi URL này là dữ liệu đã tồn tại trước khi job publish thành công.

Marker `[map-data]` bỏ qua build IPA để không phát hành app giữa lúc tạo gói.
Cập nhật code app là commit bình thường, build IPA riêng. Không tự chạy cập nhật dữ liệu
trong app mỗi lần mở; người dùng kiểm tra phiên bản mới từ trình quản lý gói.

## Giới hạn kiểm thử

Pipeline/reader có test dữ liệu nhỏ và build iOS tự động. Một lần render/publish thành công
không chứng minh mọi con đường/địa danh đều đầy đủ. Cần duyệt mẫu nhiều tỉnh, đảo và mức zoom
trên máy thật trước khi tuyên bố chất lượng điều hướng. Luôn tuân thủ biển báo thực tế.

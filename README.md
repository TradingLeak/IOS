# 🗺️ Bản đồ & Chỉ đường Việt Nam (iOS) — MapKit 3D + cảnh báo giao thông

[![Build unsigned IPA](https://github.com/TradingLeak/IOS/actions/workflows/build-unsigned-ipa.yml/badge.svg)](https://github.com/TradingLeak/IOS/actions/workflows/build-unsigned-ipa.yml)

App chỉ đường cho Việt Nam, giao diện **kính mờ hiện đại** (card nổi, HUD tốc độ, bottom
sheet), dùng **Apple Maps (MapKit)** để vẽ bản đồ và tính tuyến, **camera dẫn đường 3D/2D
xoay theo hướng đi và tốc độ thời gian thực**, **VietMap Route v4** cho hồ sơ xe máy,
cảnh báo **tốc độ / biển báo / camera**.

**Không cần mạng để tính điểm tuyến, không cần API key nào để dùng app** — mọi tính năng
dẫn đường chạy offline trên máy (chỉ có VietMap là tuỳ chọn nếu bạn muốn tuyến xe máy chính xác).

Build ra **file IPA unsigned trên GitHub Actions** — không cần máy Mac, không cần tài khoản
Apple Developer.

```
┌───────────────┐   MKDirections   ┌───────────────┐   so sánh + chấm điểm   ┌────────────────┐
│ Tuyến thật từ │ ───────────────► │ 0–100 điểm,   │ ──────────────────────► │ Chọn tuyến →   │
│ Apple Maps /  │   + cảnh báo     │ camera/cao tốc│   nhận xét offline      │ dẫn đường 3D   │
│ VietMap v4    │   dọc tuyến      │ /phí cầu đường│                         │ bám vị trí     │
└───────────────┘                  └───────────────┘                         └────────────────┘
```

## 📥 Tải IPA

**[https://github.com/TradingLeak/IOS/releases/download/latest-ipa/VietMap-unsigned.ipa](https://github.com/TradingLeak/IOS/releases/download/latest-ipa/VietMap-unsigned.ipa)**

Phiên bản hiện tại: **2.1.0 (3)** · ~3,5 MB · `arm64` · iOS ≥ 16.0 · không cần đăng nhập.

Link cố định, cập nhật mỗi lần build. Hoặc vào tab **Actions** → *Build unsigned IPA* →
**Run workflow** để tự build với bundle ID / tên hiển thị riêng.

Cài lên iPhone: xem **[docs/INSTALL.md](docs/INSTALL.md)** (TrollStore nếu iOS ≤ 17.0, hoặc
Sideloadly/SideStore với Apple ID miễn phí).

## ✨ Tính năng

**🆕 2.0 — cảnh báo & dẫn đường xe máy**
- **Tuyến xe máy thật**: Apple Maps không có hồ sơ xe máy, nên app dùng
  **VietMap Route v4** (`vehicle=motorcycle`) khi bạn nhập API key; không có key thì lấy
  tuyến Apple Maps, **loại tuyến đi cao tốc** (xe máy không được phép) và hiệu chỉnh thời
  gian — có ghi chú rõ trong app.
- **Cảnh báo tốc độ & biển báo**: HUD toàn màn hình với tốc độ hiện tại, biển tròn giới hạn
  (kiểu P.127), nguồn giới hạn (biển báo / vùng / OSM / bảng mặc định **TT 38/2024**).
  Chọn **nhóm xe hai bánh** trong Cài đặt: xe mô tô (> 50 cm³) dùng bảng 60/50 – 70/60,
  xe gắn máy ≤ 50 cm³ và xe đạp điện luôn **40 km/h**.
- **Cảnh báo camera**: 795 camera giao thông TP.HCM có sẵn (kèm ảnh tải trực tiếp từ cổng),
  tải thêm biển tốc độ/camera từ **OpenStreetMap**, hoặc **nhập JSON** tự làm.
- **Ngưỡng cảnh báo động** `D_warn = clamp(v × 3 m; 150; 500)`, đọc bằng **giọng tiếng Việt**
  (offline), có cooldown chống nói lặp.
- **Tìm đường thông minh (offline)**: chấm điểm 0–100 cho từng phương án (thời gian, quãng
  đường, mật độ camera, % cao tốc, phí cầu đường), nhận xét vì sao nên chọn tuyến đó, gợi ý
  điểm dừng (xăng/cà phê) dọc đường.

**🆕 2.1 — dẫn đường kiểu ứng dụng thương mại**
- **Bản đồ 3D / 2D theo thời gian thực**: khi dẫn đường, camera nghiêng 55° và **xoay theo
  hướng đi**, tự **phóng to khi chậm, thu nhỏ khi nhanh** (180 m → 900 m), cập nhật mượt
  theo GPS. Bấm nút `view.3d` để chuyển 2D nhìn từ trên xuống.
- **Kéo bản đồ để xem trước, bấm mũi tên để bám lại** — giống Google Maps/Apple Maps.
- **Banner chỉ dẫn thương mại**: khoảng cách tới ngã rẽ kế tiếp, còn bao xa, còn bao lâu,
  **giờ tới nơi dự kiến** và thanh tiến độ chuyến đi.
- **Tự tính lại tuyến khi đi lệch** (> 60 m, tối đa 1 lần/25 giây), **tự kết thúc khi tới
  nơi** (≤ 45 m), **rung nhẹ khi vượt tốc độ**, màn hình gọn lại khi đang chạy (ẩn tìm kiếm,
  danh mục, POI).
- **Bỏ hoàn toàn phần AI**: không cần API key, không gọi máy chủ ngoài, không gửi dữ liệu đi.
  Nhận xét tuyến vẫn có, nhưng tính trực tiếp từ số liệu trên máy.

**Bản đồ (Apple Maps / MapKit — miễn phí, không cần API key)**
- Bản đồ toàn Việt Nam, 12 thành phố preset (Hà Nội, TP.HCM, Đà Nẵng, Đà Lạt, Phú Quốc…).
- Tìm địa điểm/địa chỉ với gợi ý trực tiếp (MKLocalSearchCompleter), thiên vị khu vực VN.
- 14 chip danh mục quanh đây: ăn uống, cà phê, xăng, khách sạn, bệnh viện, ATM, biển…
- Nhấn giữ trên bản đồ → chọn điểm đến tại chỗ (tự reverse-geocode ra địa chỉ).
- 4 kiểu bản đồ (tiêu chuẩn / vệ tinh lai / vệ tinh / tối giản), lớp giao thông, POI.

**Chỉ đường**
- Ô tô / **xe máy** / đi bộ / xe buýt, nhiều phương án tuyến để chọn, đường vẽ 2 lớp (viền + màu).
- Danh sách chỉ dẫn từng bước có icon rẽ trái/phải/vòng xuyến/cao tốc/đến nơi.
- Điểm dừng giữa đường (ghép nhiều chặng `MKDirections` thành một tuyến duy nhất).
- Chế độ điều hướng: banner bước kế tiếp, tự chuyển bước khi bạn tới gần (GPS).
- Lưu lịch sử tìm kiếm và địa điểm yêu thích (UserDefaults + JSON).

**Quyền riêng tư**
- Không có tài khoản, không telemetry, không quảng cáo.
- Vị trí chỉ dùng trong máy để dẫn đường; không gửi lên máy chủ nào.
- API key VietMap (tuỳ chọn) lưu trong **Keychain**, không nằm trong repo, không ghi log.

## 🧱 Cấu trúc mã nguồn

```
App/
├── Info.plist                     # quyền vị trí, phiên bản, commit build
├── Resources/Assets.xcassets      # AppIcon 1024×1024, màu nhấn, nền launch
├── Sources/
│   ├── App/VietMapApp.swift       # entry point
│   ├── Design/                    # Theme (màu, card, gradient) + Components (nút, chip, field)
│   ├── Models/                    # Place, RouteOption, TravelMode, RoadAlert, Geo, Format…
│   ├── Services/
│   │   ├── AlertDatabase.swift    # chỉ mục lưới cảnh báo + truy vấn dọc tuyến
│   │   ├── AlertEngine.swift      # D_warn, giới hạn tốc độ hiện tại, câu đọc tiếng Việt
│   │   ├── AlertFileStore.swift   # nhập/xuất JSON cảnh báo (Documents)
│   │   ├── SpeedLimitRules.swift  # bảng TT 38/2024 + nhận diện loại đường
│   │   ├── RouteScorer.swift      # chấm điểm tuyến thông minh
│   │   ├── RoutingService.swift   # chọn Apple Maps / VietMap theo phương tiện
│   │   ├── VietMapRoutingService.swift # Route v4, hồ sơ xe máy
│   │   ├── OSMAlertService.swift  # tải biển tốc độ/camera từ Overpass
│   │   ├── VoiceAlertService.swift# đọc cảnh báo bằng AVSpeechSynthesizer
│   │   ├── RouteInsight.swift     # nhận xét + đề xuất tuyến soạn offline (không cần mạng)
│   │   ├── SearchService.swift    # MKLocalSearchCompleter + MKLocalSearch + reverse geocode
│   │   ├── DirectionsService.swift# MKDirections, ghép chặng, đổi sang model của app
│   │   ├── LocationService.swift  # CLLocationManager, quyền, cập nhật vị trí
│   │   ├── AppSettings.swift      # cài đặt: cảnh báo, xe hai bánh, camera 3D/2D
│   │   ├── KeychainStore.swift    # lưu API key an toàn
│   │   └── PlacesStore.swift      # lịch sử + yêu thích
│   ├── ViewModels/MapViewModel.swift  # trạng thái trung tâm (tuyến, camera dẫn đường, cảnh báo)
│   └── Views/                     # MapScreen, MapContainer (MKMapView + camera 3D), HUDView,
│                                  # AlertsSheet, RouteSheet, SearchSheet, SettingsView…
├── Resources/Data/vn_alerts.json  # 795 camera + dữ liệu cảnh báo (sinh bằng script)
└── Tests/                         # cảnh báo, tốc độ, xe máy, polyline, chấm điểm, format
```

## 🚀 Build

**Trên GitHub (không cần Mac):** push code → workflow tự chạy 3 job: `lint` (ubuntu),
`unit-tests` (macOS Simulator), `build` (macOS → IPA + Release). Hoặc bấm **Run workflow**.

**Trên máy Mac:**

```bash
brew install xcodegen
./scripts/setup-macos.sh          # kiểm tra Xcode + sinh VietMap.xcodeproj
./scripts/make-ipa.sh             # → dist/VietMap-2.1.0-3-unsigned.ipa
```

**Kiểm tra không cần Xcode:**

```bash
./scripts/selfcheck.sh                        # shell, plist, icon, cú pháp Swift, dữ liệu cảnh báo
./scripts/test-pack.sh                        # tạo app giả → đóng gói IPA → verify cấu trúc
python3 scripts/build-alert-data.py --check   # kiểm tra App/Resources/Data/vn_alerts.json
```

## ✅ Kiểm chứng tự động trên mỗi build

Workflow giải nén IPA và **fail nếu sai**: binary phải có `arm64`, platform `IOS`
(không phải Simulator), `Info.plist` đủ khoá, không còn dấu chữ ký.
Unit test chạy trên Simulator cho cảnh báo, giới hạn tốc độ, tuyến xe máy, format và lưu trữ.

## 📚 Tài liệu

| File | Nội dung |
|---|---|
| [docs/NAVIGATION.md](docs/NAVIGATION.md) | Camera dẫn đường 2D/3D, bám vị trí, ETA, tiến độ |
| [docs/ALERTS.md](docs/ALERTS.md) | Cảnh báo tốc độ/camera: nguồn dữ liệu, định dạng JSON, TT 38/2024, D_warn |
| [docs/BUILD.md](docs/BUILD.md) | Cơ chế build IPA unsigned, tuỳ biến project, thêm package |
| [docs/INSTALL.md](docs/INSTALL.md) | Cài IPA lên iPhone: TrollStore, Sideloadly, SideStore… |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Lỗi thường gặp (build, MapKit, GPS, cảnh báo) |

## 🔧 Cấu hình xe máy (VietMap)

1. Đăng ký key tại <https://maps.vietmap.vn/console-v2/register> (có gói miễn phí).
2. App → ☰ → **Cài đặt** → **Dẫn đường xe máy** → dán key.
3. Chọn phương tiện mặc định = **Xe máy**.

Không có key: app vẫn dẫn đường xe máy được nhưng là **ước lượng** từ Apple Maps (đã loại
tuyến cao tốc). Key lưu trong Keychain, không nằm trong repo.

## ⚖️ Lưu ý

- Bản đồ và tuyến đường do **Apple Maps** cung cấp (hoặc VietMap khi có key); dữ liệu giao
  thông Việt Nam có thể chưa đầy đủ như Google Maps/Goong — app nêu rõ khi không tìm được tuyến.
- **Cảnh báo chỉ để tham khảo**: giới hạn tốc độ có thể lệch so với biển báo thực tế. Luôn
  tuân theo biển báo và hiệu lệnh của CSGT. Chi tiết + giấy phép dữ liệu: [docs/ALERTS.md](docs/ALERTS.md).
- Ứng dụng **không gửi dữ liệu nào lên máy chủ của chúng tôi** (không có máy chủ). Dữ liệu
  cảnh báo nhúng sẵn trong app; OpenStreetMap chỉ tải khi bạn bấm.
- IPA phát hành **không có chữ ký Apple**; cài đặt cần TrollStore hoặc ký lại bằng Apple ID
  miễn phí. Chi tiết trong docs/INSTALL.md.

# 🗺️ Bản đồ & Chỉ đường Việt Nam (iOS) — MapKit + AI tuỳ chỉnh

[![Build unsigned IPA](https://github.com/TradingLeak/IOS/actions/workflows/build-unsigned-ipa.yml/badge.svg)](https://github.com/TradingLeak/IOS/actions/workflows/build-unsigned-ipa.yml)

App chỉ đường cho Việt Nam, giao diện kiểu **OsmAnd / Organic Maps** (card nổi, tìm kiếm
nhanh, bottom sheet), cho chọn **Apple Maps hoặc OpenStreetMap** làm bản đồ nền (hiển thị bằng MapKit),
dùng **Apple Maps** để tìm địa điểm và tính tuyến, tích hợp
**AI model tuỳ chỉnh** (mặc định **ckey.vn**, chuẩn OpenAI) để hiểu câu lệnh tiếng Việt.

Build ra **file IPA unsigned trên GitHub Actions** — không cần máy Mac, không cần tài khoản
Apple Developer.

```
┌──────────────┐   MKLocalSearch    ┌──────────────┐   MKDirections   ┌──────────────┐
│  Câu tiếng   │ ─────────────────► │  Ý định JSON │ ───────────────► │  Tuyến thật  │
│  Việt tự     │   AI (tuỳ chỉnh)   │  điểm đi/đến │   Apple Maps     │  + turn-by-  │
│  nhiên       │   ckey.vn / khác   │  + waypoint  │                  │  turn        │
└──────────────┘                    └──────────────┘                  └──────────────┘
```

## 🖥️ Demo HTML để duyệt giao diện

Mở **[demo/VietMap-demo.html](demo/VietMap-demo.html)** trực tiếp trong trình duyệt
hoặc dùng Live Preview. Có thể thử chuyển nguồn, tải gói Việt Nam giả lập, tìm điểm mẫu,
HUD/vượt tốc/mất GPS và tuỳ chọn. Không cần API key hoặc dữ liệu bản đồ thật.

**Chỉ là demo giao diện:** bản đồ/GPS/tải dữ liệu/dung lượng đều mô phỏng, không dùng để
điều hướng và không tạo IPA. Xem [hướng dẫn demo](demo/README.md).

## 🌍 Chọn nguồn bản đồ nền

- **Apple Maps (MapKit)**: tiêu chuẩn, vệ tinh lai, vệ tinh, tối giản và giao thông Apple.
- **OpenStreetMap**: đọc gói bản đồ Việt Nam offline (PNG MBTiles), giữ ghim/tuyến/HUD và attribution.
- Đổi tại **☰ → Bản đồ → Nguồn bản đồ**, trong Cài đặt, hoặc nút lớp bản đồ khi chưa có tuyến.
  Lựa chọn được lưu trên thiết bị.

Đổi nguồn nền **không đổi dịch vụ tìm kiếm/tính tuyến**: các chức năng đó vẫn dùng Apple.
OSM yêu cầu tải gói Việt Nam khi chưa có dữ liệu trên máy. Tải xong dùng bản đồ nền cục bộ,
không tải lại mỗi lần mở và không tải tile qua Internet. Có tiến trình, Wi-Fi-only mặc định,
huỷ tải, kiểm tra SHA-256, cập nhật/xoá gói. Cảnh báo Speedmap là dữ liệu cục bộ riêng.

**Đã phát hành gói VietMap Basic Việt Nam** từ dữ liệu OSM/Geofabrik: phiên bản
`20261029-1`, 854.712.320 byte (~855 MB), 58.527 tile PNG, native zoom 5–13.
App 1.0.1 đã cấu hình [nguồn manifest mặc định](https://github.com/TradingLeak/IOS/releases/download/offline-vietnam/manifest.json).
Bản đồ cơ bản có đường, sông hồ và tên nơi chốn; không tương đương OSM Carto đầy đủ,
chưa có POI/địa chỉ toàn diện hoặc tính tuyến offline. Zoom cao hơn chỉ phóng ảnh tile gốc.

[Release dữ liệu](https://github.com/TradingLeak/IOS/releases/tag/offline-vietnam) ·
[cơ chế tải/lưu](docs/MAP-PROVIDERS.md) · [pipeline tái tạo](scripts/maps/README.md).

## 🚘 Chế độ HUD lái xe (mới)

Bổ sung HUD toàn màn hình lấy cảm hứng từ [VietHUD](https://github.com/911273/VietHUD),
chạy trực tiếp trên iPhone bằng GPS, không cần thiết bị ESP32 hoặc API AI:

- Đồng hồ tốc độ lớn, giới hạn tốc độ, tên đường và thẻ camera/biển báo offline.
- Hỗ trợ dọc/ngang, phản chiếu nội dung lên kính, tuỳ chọn giữ sáng màn hình.
- Báo vượt tốc bằng màu/âm/giọng Việt, giới hạn tần suất đọc để tránh lặp liên tục.
- GPS mất tín hiệu hoặc sai số lớn sẽ xoá dữ liệu cũ, không hiển thị tốc độ giả.

**Mở:** nút đồng hồ tốc độ bên phải bản đồ hoặc ☰ → **HUD lái xe offline**.
Chỉ hoạt động khi app đang mở. Biển báo thực tế luôn được ưu tiên hơn dữ liệu ứng dụng.
Xem [hướng dẫn HUD, checklist thử máy thật và cách build](docs/HUD.md).

**Trạng thái:** HUD/OSM đã được build trên GitHub Actions. Xem kết quả của đúng run/phiên bản IPA;
chất lượng GPS/cảnh báo và bản đồ vẫn cần kiểm chứng trên máy thật.

## 📥 Tải IPA

**[https://github.com/TradingLeak/IOS/releases/download/latest-ipa/VietMap-unsigned.ipa](https://github.com/TradingLeak/IOS/releases/download/latest-ipa/VietMap-unsigned.ipa)**

Link cố định, cập nhật mỗi lần build. Hoặc vào tab **Actions** → *Build unsigned IPA* →
**Run workflow** để tự build với bundle ID / model AI riêng.

Cài lên iPhone: xem **[docs/INSTALL.md](docs/INSTALL.md)** (TrollStore nếu iOS ≤ 17.0, hoặc
Sideloadly/SideStore với Apple ID miễn phí).

## ✨ Tính năng

**Bản đồ (Apple Maps / MapKit — miễn phí, không cần API key)**
- Bản đồ toàn Việt Nam, 12 thành phố preset (Hà Nội, TP.HCM, Đà Nẵng, Đà Lạt, Phú Quốc…).
- Tìm địa điểm/địa chỉ với gợi ý trực tiếp (MKLocalSearchCompleter), thiên vị khu vực VN.
- 14 chip danh mục quanh đây: ăn uống, cà phê, xăng, khách sạn, bệnh viện, ATM, biển…
- Nhấn giữ trên bản đồ → chọn điểm đến tại chỗ (tự reverse-geocode ra địa chỉ).
- 4 kiểu bản đồ (tiêu chuẩn / vệ tinh lai / vệ tinh / tối giản), lớp giao thông, POI.

**Chỉ đường**
- Ô tô / đi bộ / xe buýt, nhiều phương án tuyến để chọn, đường vẽ 2 lớp (viền + màu).
- Danh sách chỉ dẫn từng bước có icon rẽ trái/phải/vòng xuyến/cao tốc/đến nơi.
- Điểm dừng giữa đường (ghép nhiều chặng `MKDirections` thành một tuyến duy nhất).
- Chế độ điều hướng: banner bước kế tiếp, tự chuyển bước khi bạn tới gần (GPS).
- **Giọng nói tiếng Việt**: đọc từng bước rẽ, báo "Đã đến nơi", đọc cảnh báo
  biển báo/camera (`AVSpeechSynthesizer`, bật/tắt trong Cài đặt).
- **Tự tính lại tuyến** khi đi lệch >70 m (throttle 15s) — thất bại thì giữ tuyến cũ
  và báo bằng giọng nói.
- **Tiếng báo "tink"** khi xuất hiện card camera/biển báo mới (ưu tiên camera, cấm vượt).
- Lưu lịch sử tìm kiếm và địa điểm yêu thích (UserDefaults + JSON).

**Cảnh báo biển báo & camera (offline — speedmap VietHUD)**
- Bundle sẵn 7 file `.bin` (~8MB, [911273/VietHUD/speedmap](https://github.com/911273/VietHUD/tree/main/speedmap)):
  camera phạt nguội, biển báo (khu dân cư, cấm vượt, trạm thu phí, đèn), mạng đường
  & giới hạn tốc độ toàn quốc — **100% offline, không cần mạng**.
- HUD hiện card cảnh báo **trực tiếp trên màn hình bản đồ**: khoảng cách đếm ngược
  theo tốc độ (`clamp(v×4.5, 100…400m)`, biển báo 350m), biển giới hạn tốc độ kiểu
  giao thông + đồng hồ tốc độ, tự ẩn khi qua mặt.
- Kiểm tra CRC32 lúc nạp, điểm self-test trong `metadata` để tự xác minh dữ liệu.
- Thiết kế chi tiết: [docs/NAV-PRO-DESIGN.md](docs/NAV-PRO-DESIGN.md).

**AI (model và base URL tuỳ chỉnh)**
- Gõ/speak câu tự nhiên: *“đi từ Cầu Giấy đến Hồ Tây, tránh đường đông”* → app tìm địa
  điểm thật, tính tuyến thật và tóm tắt lộ trình bằng tiếng Việt.
- Chuẩn **OpenAI `/chat/completions`**: ckey.vn, OpenAI, Groq, OpenRouter, Ollama (LAN)…
  đổi nhà cung cấp chỉ bằng base URL + model.
- **Không có key vẫn dùng được**: có bộ phân tích tiếng Việt offline cho câu cơ bản.
- Key lưu trong **Keychain**, không nằm trong repo, không ghi log.

## ⚙️ Cấu hình AI

Mặc định app trỏ tới **ckey.vn**:

| Trường | Giá trị |
|---|---|
| Base URL | `https://api.xah.io/v1` |
| Model | `gpt-4o-mini` (đổi được) |
| Endpoint | `POST https://api.xah.io/v1/chat/completions` |
| Auth | `Authorization: Bearer <API key>` |

Ba cách cấu hình:

**1. Trong app (khuyến nghị)**
Mở app → menu ☰ → **Cài đặt AI & bản đồ** → dán API key → bấm **Kiểm tra kết nối**.
Key lưu trong Keychain của máy, không ai khác đọc được.

**2. GitHub Secrets (nhúng sẵn vào bản build)**
Repo → **Settings → Secrets and variables → Actions**:

| Loại | Tên | Ý nghĩa |
|---|---|---|
| Secret | `AI_API_KEY` | API key (KHÔNG commit vào code) |
| Variable | `AI_BASE_URL` | vd `https://api.xah.io/v1` |
| Variable | `AI_MODEL` | vd `gpt-4o-mini` |

Build tự đọc và nhúng vào `Info.plist`. ⚠️ Repo public thì key nhúng sẽ nằm trong file IPA
phát hành — ai tải cũng trích ra được. Chỉ dùng cách này cho bản build cá nhân, hoặc chỉ
nhúng base URL/model rồi nhập key trong app.

**3. Khi bấm Run workflow**
Điền `ai_base_url`, `ai_model` cho từng lần build (key vẫn lấy từ secret).

Chi tiết kỹ thuật, prompt, schema JSON: **[docs/AI.md](docs/AI.md)**.

## 🧱 Cấu trúc mã nguồn

```
App/
├── Info.plist                     # quyền vị trí + placeholder cấu hình AI
├── Resources/Assets.xcassets      # AppIcon 1024×1024, màu nhấn, nền launch
├── Sources/
│   ├── App/VietMapApp.swift       # entry point
│   ├── Design/                    # Theme (màu, card, gradient) + Components (nút, chip, field)
│   ├── Models/                    # Place, RouteOption, TravelMode, MapPin, Format… 
│   ├── Services/
│   │   ├── AIClient.swift         # gọi {base_url}/chat/completions, parse phản hồi
│   │   ├── AIRoutePlanner.swift   # prompt → JSON ý định → địa điểm thật → tóm tắt
│   │   ├── RouteIntentParser.swift# parser tiếng Việt offline (dự phòng khi không có key)
│   │   ├── SearchService.swift    # MKLocalSearchCompleter + MKLocalSearch + reverse geocode
│   │   ├── DirectionsService.swift# MKDirections, ghép chặng, đổi sang model của app
│   │   ├── LocationService.swift  # CLLocationManager, quyền, cập nhật vị trí
│   │   ├── AppSettings.swift      # base URL/model/temperature + AIConfig
│   │   ├── KeychainStore.swift    # lưu API key an toàn
│   │   └── PlacesStore.swift      # lịch sử + yêu thích
│   ├── ViewModels/MapViewModel.swift  # trạng thái trung tâm (tuyến, AI, bản đồ)
│   └── Views/                     # MapScreen, MapContainer (MKMapView), RouteSheet,
│                                  # SearchSheet, AIAssistantSheet, SettingsView…
└── Tests/                         # unit test parser, AI client, format, lưu trữ
```

## 🚀 Build

**Trên GitHub (không cần Mac):** push code → workflow tự chạy 3 job: `lint` (ubuntu),
`unit-tests` (macOS Simulator), `build` (macOS → IPA + Release). Hoặc bấm **Run workflow**.

**Trên máy Mac:**

```bash
brew install xcodegen
./scripts/setup-macos.sh          # kiểm tra Xcode + sinh VietMap.xcodeproj
./scripts/make-ipa.sh             # → dist/VietMap-1.0.0-1-unsigned.ipa
AI_BASE_URL=https://api.xah.io/v1 AI_MODEL=gpt-4o-mini ./scripts/make-ipa.sh
```

**Kiểm tra không cần Xcode:**

```bash
./scripts/selfcheck.sh   # shell, plist, icon, cân bằng ngoặc Swift, YAML, tài liệu
./scripts/test-pack.sh   # tạo app giả → đóng gói IPA → verify cấu trúc
```

## ✅ Kiểm chứng tự động trên mỗi build

Workflow giải nén IPA và **fail nếu sai**: binary phải có `arm64`, platform `IOS`
(không phải Simulator), `Info.plist` đủ khoá, không còn dấu chữ ký.
Unit test chạy trên Simulator cho parser, AI client, format, lưu trữ.

## 📚 Tài liệu

| File | Nội dung |
|---|---|
| [docs/AI.md](docs/AI.md) | Tích hợp AI: schema JSON, prompt, đổi model/nhà cung cấp, xử lý lỗi |
| [docs/BUILD.md](docs/BUILD.md) | Cơ chế build IPA unsigned, tuỳ biến project, thêm package |
| [docs/INSTALL.md](docs/INSTALL.md) | Cài IPA lên iPhone: TrollStore, Sideloadly, SideStore… |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Lỗi thường gặp (build, MapKit, AI) |

## ⚖️ Lưu ý

- Bản đồ và tuyến đường do **Apple Maps** cung cấp; dữ liệu giao thông Việt Nam có thể
  chưa đầy đủ như Google Maps/Goong — app nêu rõ khi không tìm được tuyến.
- Ứng dụng gửi **câu lệnh dạng văn bản** (không phải vị trí) tới máy chủ AI bạn cấu hình,
  chỉ khi bạn dùng tính năng trợ lý. Không có key → không có dữ liệu nào rời khỏi máy.
- IPA phát hành **không có chữ ký Apple**; cài đặt cần TrollStore hoặc ký lại bằng Apple ID
  miễn phí. Chi tiết trong docs/INSTALL.md.

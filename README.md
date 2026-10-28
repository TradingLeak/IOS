# 🗺️ Bản đồ & Chỉ đường Việt Nam (iOS) — MapKit + AI tuỳ chỉnh

[![Build unsigned IPA](https://github.com/TradingLeak/IOS/actions/workflows/build-unsigned-ipa.yml/badge.svg)](https://github.com/TradingLeak/IOS/actions/workflows/build-unsigned-ipa.yml)

App chỉ đường cho Việt Nam, giao diện **kính mờ hiện đại** (card nổi, HUD tốc độ, bottom
sheet), dùng **Apple Maps (MapKit)** để vẽ bản đồ và tính tuyến, **VietMap Route v4** cho
hồ sơ xe máy, cảnh báo **tốc độ / biển báo / camera** và **AI model tuỳ chỉnh**
(mặc định **ckey.vn**, chuẩn OpenAI) để hiểu câu lệnh tiếng Việt và chọn tuyến thông minh.

Build ra **file IPA unsigned trên GitHub Actions** — không cần máy Mac, không cần tài khoản
Apple Developer.

```
┌──────────────┐   MKLocalSearch    ┌──────────────┐   MKDirections   ┌──────────────┐
│  Câu tiếng   │ ─────────────────► │  Ý định JSON │ ───────────────► │  Tuyến thật  │
│  Việt tự     │   AI (tuỳ chỉnh)   │  điểm đi/đến │   Apple Maps     │  + turn-by-  │
│  nhiên       │   ckey.vn / khác   │  + waypoint  │                  │  turn        │
└──────────────┘                    └──────────────┘                  └──────────────┘
```

## 📥 Tải IPA

**[https://github.com/TradingLeak/IOS/releases/download/latest-ipa/VietMap-unsigned.ipa](https://github.com/TradingLeak/IOS/releases/download/latest-ipa/VietMap-unsigned.ipa)**

Link cố định, cập nhật mỗi lần build. Hoặc vào tab **Actions** → *Build unsigned IPA* →
**Run workflow** để tự build với bundle ID / model AI riêng.

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
- **Tìm đường thông minh**: chấm điểm 0–100 cho từng phương án (thời gian, quãng đường, mật
  độ camera, % cao tốc, phí cầu đường), AI giải thích nên chọn tuyến nào, gợi ý điểm dừng
  (xăng/cà phê) dọc đường.

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
│   └── Views/                     # MapScreen, MapContainer (MKMapView), HUDView, AlertsSheet,
│                                  # RouteSheet, SearchSheet, AIAssistantSheet, SettingsView…
├── Resources/Data/vn_alerts.json  # 795 camera + dữ liệu cảnh báo (sinh bằng script)
└── Tests/                         # parser, AI client, cảnh báo, tốc độ, polyline, chấm điểm
```

## 🚀 Build

**Trên GitHub (không cần Mac):** push code → workflow tự chạy 3 job: `lint` (ubuntu),
`unit-tests` (macOS Simulator), `build` (macOS → IPA + Release). Hoặc bấm **Run workflow**.

**Trên máy Mac:**

```bash
brew install xcodegen
./scripts/setup-macos.sh          # kiểm tra Xcode + sinh VietMap.xcodeproj
./scripts/make-ipa.sh             # → dist/VietMap-2.0.0-2-unsigned.ipa
AI_BASE_URL=https://api.xah.io/v1 AI_MODEL=gpt-4o-mini ./scripts/make-ipa.sh
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
Unit test chạy trên Simulator cho parser, AI client, format, lưu trữ.

## 📚 Tài liệu

| File | Nội dung |
|---|---|
| [docs/AI.md](docs/AI.md) | Tích hợp AI: schema JSON, prompt, đổi model/nhà cung cấp, xử lý lỗi |
| [docs/ALERTS.md](docs/ALERTS.md) | Cảnh báo tốc độ/camera: nguồn dữ liệu, định dạng JSON, TT 38/2024, D_warn |
| [docs/BUILD.md](docs/BUILD.md) | Cơ chế build IPA unsigned, tuỳ biến project, thêm package |
| [docs/INSTALL.md](docs/INSTALL.md) | Cài IPA lên iPhone: TrollStore, Sideloadly, SideStore… |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Lỗi thường gặp (build, MapKit, AI) |

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
- Ứng dụng gửi **câu lệnh dạng văn bản** (không phải vị trí) tới máy chủ AI bạn cấu hình,
  chỉ khi bạn dùng tính năng trợ lý. Không có key → không có dữ liệu nào rời khỏi máy.
- IPA phát hành **không có chữ ký Apple**; cài đặt cần TrollStore hoặc ký lại bằng Apple ID
  miễn phí. Chi tiết trong docs/INSTALL.md.

# 🗺️ Bản đồ & Chỉ đường Việt Nam (iOS) — MapKit 3D + cảnh báo giao thông

[![Build unsigned IPA](https://github.com/TradingLeak/IOS/actions/workflows/build-unsigned-ipa.yml/badge.svg)](https://github.com/TradingLeak/IOS/actions/workflows/build-unsigned-ipa.yml)

App chỉ đường cho Việt Nam, giao diện **kính mờ hiện đại** (card nổi, thanh tốc độ trên
màn hình chính, bottom sheet), dùng **Apple Maps (MapKit)** để vẽ bản đồ và tính tuyến,
**camera dẫn đường 3D/2D xoay theo hướng đi và tốc độ thời gian thực**, cảnh báo
**tốc độ / biển báo / camera ngay trên bản đồ** với dữ liệu tự có, và **trợ lý AI** tuỳ chọn
(Ckey.vn hoặc base URL bạn tự nhập) để hiểu câu lệnh tìm đường.

**Không cần mạng để tính điểm tuyến, không cần API key nào để dùng app, không gọi API
VietMap** — tuyến đường, chấm điểm, ước lượng thời gian xe máy và toàn bộ dữ liệu cảnh báo
đều nằm trong app hoặc được tải từ OpenStreetMap (ODbL).

Build ra **file IPA unsigned trên GitHub Actions** — không cần máy Mac, không cần tài khoản
Apple Developer.

```
┌───────────────┐   MKDirections   ┌───────────────┐   so sánh + chấm điểm   ┌────────────────┐
│ Tuyến từ      │ ───────────────► │ 0–100 điểm,   │ ──────────────────────► │ Chọn tuyến →   │
│ Apple Maps    │   + cảnh báo     │ camera/cao tốc│   nhận xét offline      │ dẫn đường 3D   │
│ + chấm điểm   │   dọc tuyến      │ /phí cầu đường│                         │ bám vị trí     │
└───────────────┘                  └───────────────┘                         └────────────────┘
```

## 📥 Tải IPA

**[https://github.com/TradingLeak/IOS/releases/download/latest-ipa/VietMap-unsigned.ipa](https://github.com/TradingLeak/IOS/releases/download/latest-ipa/VietMap-unsigned.ipa)**

Phiên bản hiện tại: **2.3.0 (5)** · ~3,5 MB · `arm64` · iOS ≥ 16.0 · không cần đăng nhập.

Link cố định, cập nhật mỗi lần build. Hoặc vào tab **Actions** → *Build unsigned IPA* →
**Run workflow** để tự build với bundle ID / tên hiển thị riêng.

Cài lên iPhone: xem **[docs/INSTALL.md](docs/INSTALL.md)** (TrollStore nếu iOS ≤ 17.0, hoặc
Sideloadly/SideStore với Apple ID miễn phí).

## ✨ Tính năng

**🆕 3.1 — dữ liệu cảnh báo dày gấp 4: 108.528 điểm**

- Nhập **bộ dữ liệu SpeedMap** của VietHUD (`cameras.bin`, `signs.bin`): **82.608 điểm** biển
  giới hạn tốc độ, khu dân cư, đèn tín hiệu, camera, cấm vượt, điểm nguy hiểm — toạ độ khớp
  mạng đường OSM (trung vị 3 m).
- Loại cảnh báo mới **đèn tín hiệu** (`traffic_light`) có màu marker và câu đọc riêng.
- Nạp dữ liệu 17 MB **ở luồng nền**: app mở lên ngay, marker hiện dần sau ~1 giây.
- Công cụ chuyển đổi `scripts/import-viethud-speedmap.py` (có `--report`, `--compact`), hướng dẫn
  định dạng + **lưu ý giấy phép** trong [docs/DATA-SPEEDMAP.md](docs/DATA-SPEEDMAP.md).

**🆕 3.0 — giao diện dẫn đường kiểu VietMap, dữ liệu tự có, bỏ API VietMap**

- **Thẻ chỉ dẫn 2 dòng + thanh tiến trình tới chỗ rẽ**, dòng “Sau đó…” như app thương mại.
- **Đồng hồ tốc độ dạng vòng cung** ngay trên bản đồ, chuyển đỏ và hiện “vượt X km/h”.
- **Banner cảnh báo kiểu VietMap**: nhãn loại (CAMERA TỐC ĐỘ / BIỂN GIỚI HẠN…), tên điểm,
  đếm lùi mét và thanh chạy tới điểm cảnh báo.
- **Gợi ý làn đường** khi còn < 400 m tới chỗ rẽ (suy ra từ chỉ dẫn, không cần API).
- **Dữ liệu phủ rộng**: biển giới hạn tốc độ, camera, trường học, khu dân cư, đường ngang
  tàu hoả lấy từ **OpenStreetMap (ODbL)** bằng pipeline chạy trong GitHub Actions, giữ nguyên
  795 camera TP.HCM.
- **Bỏ hoàn toàn VietMap Route v4**: tuyến, thời gian xe máy và chấm điểm đều là logic nội bộ.

**🆕 2.3 — bộ tính năng cao cấp: báo cáo sự cố, chia sẻ tuyến, tìm không dấu**

- **Báo cáo sự cố trên đường**: CSGT, tai nạn, ngập, ổ gà, cấm đường, kẹt xe — ghi ngay tại vị
  trí đang đứng, hiện thành marker trên bản đồ, mỗi loại tự hết hạn (45 phút → 7 ngày) và được
  **đọc lên khi bạn tới gần** (350 m). Lưu trên máy, không gửi đi đâu.
- **Chia sẻ tuyến** bằng một nút: tin nhắn có quãng đường, thời gian, giờ tới nơi, điểm dừng và
  **link Apple Maps** để người nhận mở ngay lộ trình.
- **Tìm kiếm không dấu**: gõ “ho hoan kiem”, “duong nguyen trai” vẫn ra đúng; kết quả ưu tiên
  khớp đầu tên rồi tới gần nhất, kèm khoảng cách “cách 320 m”. Yêu thích/gần đây được lọc ngay
  khi gõ.
- **Giấy phép rõ ràng**: repo dùng MIT (`LICENSE`), dữ liệu bên thứ ba giữ giấy phép gốc.

**🆕 2.2 — bỏ HUD, cảnh báo trên bản đồ, trợ lý AI tìm tuyến**

- **Không còn HUD toàn màn hình.** Biển báo (QCVN 41:2019) và camera phạt nguội hiện **trực
  tiếp trên bản đồ** bằng marker/nhãn: glyph theo loại, số km/h trong biển tròn P.127, màu
  theo mức nguy hiểm, phóng to khi tới gần, bấm để xem chi tiết.
- **Thanh tốc độ trên màn hình chính**: tốc độ hiện tại (đỏ khi vượt ngưỡng), biển giới hạn
  + nguồn, và **2 cảnh báo sắp tới** kèm khoảng cách tô màu `xanh → vàng → cam → đỏ` —
  không phải mở màn hình phụ.
- **Biển báo/camera quanh bạn hiện ngay khi chưa chọn tuyến**: app tự nạp trong bán kính
  2,5 km (tải lại sau 45 giây hoặc khi đi xa 400 m), marker **đổi màu tại chỗ** khi bạn tiến
  lại gần (xa → cam → đỏ) mà bản đồ không nháy.
- **3D ↔ 2D đổi được bất cứ lúc nào**, kể cả khi chỉ xem bản đồ (nút `view.3d` / `map`).
- **Trợ lý AI tìm tuyến kiểu Google Maps**: gõ câu tự nhiên (*“xe máy từ Cầu Giấy đến Hồ
  Hoàn Kiếm, tránh cao tốc, ghé cà phê”*), AI hiểu phương tiện / điểm đi / điểm đến / điểm
  dừng / giờ đi / mức ưu tiên, rồi **can thiệp sâu**: chọn tuyến trong các phương án, thêm
  điểm dừng, viết lý do chọn. Nhà cung cấp mặc định **Ckey.vn** (`https://api.xah.io/v1`),
  **base URL tự nhập** (OpenAI, Groq, OpenRouter, Ollama/LM Studio trong LAN…).
- **Luôn có phương án không AI**: không key / mất mạng / AI lỗi → bộ phân tích tiếng Việt
  trên máy vẫn hiểu phương tiện, điểm đi–đến, “tránh cao tốc”, “ít camera”, giờ khởi hành.
- **Mức ưu tiên tuyến** chọn ngay trong sheet Chỉ đường: Nhanh / Ít camera / Tránh cao tốc / Dễ đi.

**🆕 2.0 — cảnh báo & dẫn đường xe máy**
- **Tuyến xe máy thật**: Apple Maps không có hồ sơ xe máy, nên app dùng
  **VietMap Route v4** (`vehicle=motorcycle`) khi bạn nhập API key; không có key thì lấy
  tuyến Apple Maps, **loại tuyến đi cao tốc** (xe máy không được phép) và hiệu chỉnh thời
  gian — có ghi chú rõ trong app.
- **Cảnh báo tốc độ & biển báo**: tốc độ hiện tại, biển tròn giới hạn (kiểu P.127), nguồn
  giới hạn (biển báo / vùng / OSM / bảng mặc định **TT 38/2024**) — hiện trên thanh trạng thái
  và trực tiếp trên bản đồ (bản 2.0–2.1 dùng HUD toàn màn hình, 2.2 đã bỏ).
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
- **Nhận xét tuyến soạn trên máy** (không cần API key) — từ 2.2 có thêm trợ lý AI tuỳ chọn,
  xem mục *Trợ lý AI* bên dưới.

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
│   │   ├── AIClient.swift         # OpenAI-compatible: base URL tự nhập, đọc JSON "bẩn"
│   │   ├── RouteIntentParser.swift# schema ý định + bộ phân tích tiếng Việt offline
│   │   ├── AIRoutePlanner.swift   # 4 prompt: hiểu câu lệnh, chọn tuyến, điểm dừng, nhận xét
│   │   ├── IncidentStore.swift    # lưu báo cáo sự cố trên máy (JSON trong Documents)
│   │   ├── SearchService.swift    # MKLocalSearchCompleter + MKLocalSearch + reverse geocode
│   │   ├── DirectionsService.swift# MKDirections, ghép chặng, đổi sang model của app
│   │   ├── LocationService.swift  # CLLocationManager, quyền, cập nhật vị trí
│   │   ├── AppSettings.swift      # cài đặt: cảnh báo, xe hai bánh, camera 3D/2D
│   │   ├── KeychainStore.swift    # lưu API key an toàn
│   │   └── PlacesStore.swift      # lịch sử + yêu thích
│   ├── ViewModels/MapViewModel.swift  # trạng thái trung tâm (tuyến, camera dẫn đường, cảnh báo)
│   └── Views/                     # MapScreen, MapContainer (MKMapView + camera 3D),
│                                  # AIAssistantSheet, AISettingsSection, RouteSheet,
│                                  # ReportIncidentSheet, AlertsSheet, SearchSheet, SettingsView…
├── Resources/Data/vn_alerts.json  # 795 camera + dữ liệu cảnh báo (sinh bằng script)
└── Tests/                         # cảnh báo, tốc độ, xe máy, polyline, chấm điểm, format, AI
```

## 🚀 Build

**Trên GitHub (không cần Mac):** push code → workflow tự chạy 3 job: `lint` (ubuntu),
`unit-tests` (macOS Simulator), `build` (macOS → IPA + Release). Hoặc bấm **Run workflow**.

**Trên máy Mac:**

```bash
brew install xcodegen
./scripts/setup-macos.sh          # kiểm tra Xcode + sinh VietMap.xcodeproj
./scripts/make-ipa.sh             # → dist/VietMap-2.3.0-5-unsigned.ipa
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
| [docs/NAVIGATION.md](docs/NAVIGATION.md) | Camera dẫn đường 2D/3D, bám vị trí, ETA, tiến độ, thanh tốc độ |
| [docs/AI.md](docs/AI.md) | Trợ lý AI: Ckey.vn, base URL tự nhập, prompt, fallback offline |
| [docs/ALERTS.md](docs/ALERTS.md) | Cảnh báo tốc độ/camera: nguồn dữ liệu, định dạng JSON, TT 38/2024, D_warn |
| [docs/BUILD.md](docs/BUILD.md) | Cơ chế build IPA unsigned, tuỳ biến project, thêm package |
| [docs/INSTALL.md](docs/INSTALL.md) | Cài IPA lên iPhone: TrollStore, Sideloadly, SideStore… |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Lỗi thường gặp (build, MapKit, GPS, cảnh báo) |

## 🔧 Dẫn đường xe máy (không cần API key)

1. App → ☰ → **Cài đặt** → **Dẫn đường xe máy** → chọn phương tiện mặc định = **Xe máy**.
2. Chọn **nhóm xe hai bánh** (mô tô / xe gắn máy ≤ 50 cm³) để áp đúng bảng tốc độ TT 38/2024.

Tuyến tính bằng Apple Maps rồi **chấm điểm nội bộ**: loại phương án đi cao tốc (xe máy không
được phép), ưu tiên đường lớn, trừ điểm theo mật độ camera/biển giới hạn. Thời gian xe máy là
ước lượng và luôn được ghi chú trong bảng so sánh tuyến.

## 🤖 Trợ lý AI (tuỳ chọn)

1. Lấy key tại <https://ckey.vn> (hoặc dùng OpenAI/Groq/OpenRouter…).
2. App → ☰ → **Cài đặt** → **Trợ lý AI** → chọn nhà cung cấp, dán key, bấm
   **Kiểm tra kết nối**.
3. Bấm nút `sparkles` (mép phải bản đồ) để mở trợ lý và gõ câu lệnh.

Base URL mặc định `https://api.xah.io/v1`, model `gpt-4o-mini`, temperature 0.2 — tất cả
đổi được, kể cả trỏ về Ollama/LM Studio trong LAN. Chi tiết: [docs/AI.md](docs/AI.md).

## 📄 Giấy phép

Mã nguồn theo **MIT** ([LICENSE](LICENSE)). Dữ liệu cảnh báo lấy từ nguồn công khai, giữ nguyên
giấy phép gốc — xem [data/README.md](data/README.md) và [docs/ALERTS.md](docs/ALERTS.md).

## ⚖️ Lưu ý

- Bản đồ và tuyến đường do **Apple Maps** cung cấp (hoặc VietMap khi có key); dữ liệu giao
  thông Việt Nam có thể chưa đầy đủ như Google Maps/Goong — app nêu rõ khi không tìm được tuyến.
- **Trợ lý AI là tuỳ chọn**: khi bật, câu chữ bạn gõ và số liệu tuyến được gửi tới nhà cung
  cấp bạn chọn (không gửi tới máy chủ của tác giả app, không gửi toạ độ GPS thô). Tắt AI là
  app chạy lại hoàn toàn offline.
- **Cảnh báo chỉ để tham khảo**: giới hạn tốc độ có thể lệch so với biển báo thực tế. Luôn
  tuân theo biển báo và hiệu lệnh của CSGT. Chi tiết + giấy phép dữ liệu: [docs/ALERTS.md](docs/ALERTS.md).
- Ứng dụng **không gửi dữ liệu nào lên máy chủ của chúng tôi** (không có máy chủ). Dữ liệu
  cảnh báo nhúng sẵn trong app; OpenStreetMap chỉ tải khi bạn bấm.
- IPA phát hành **không có chữ ký Apple**; cài đặt cần TrollStore hoặc ký lại bằng Apple ID
  miễn phí. Chi tiết trong docs/INSTALL.md.

# 💓 Pulse — Exness Trader API + Partnership API + Lịch kinh tế + Tin tức (iOS)

**Pulse** (target XcodeGen `PulseHub`, bundle `com.tradingleak.pulsehub`) là app iOS thứ ba trong repo,
viết bằng SwiftUI, giao diện tối kiểu "trading terminal" (gradient teal → tím), **không cần server**:
mọi yêu cầu API đều ký ngay trên thiết bị và dữ liệu công khai (lịch, tin tức) tải thẳng về máy.

| Nhóm tính năng | Nguồn | Cần API key? |
|---|---|---|
| 💹 **Giá trực tiếp** (WebSocket ticks, bid/ask/spread, sparkline, biểu đồ nến M1→D1 vẽ tay) | Exness **Trader API** | Có (scope Trading) |
| 🏦 **Tài khoản giao dịch** (equity, số dư, margin, lệnh đang mở) | Trader API | Có |
| 🔔 **Cảnh báo giá** (mức giá / biên độ %, kiểm tra theo từng tick, local notification, Background App Refresh) | Trader API + iOS | Có (để có giá) |
| 📅 **Lịch kinh tế** (Forex Factory, lọc mức ảnh hưởng & tiền tệ, nhắc trước 15 phút) | `nfs.faireconomy.media` | **Không** |
| 📰 **Tin tức nâng cao** (4 nguồn RSS/Atom gộp, lọc nhóm, tìm kiếm, đọc trong app, chia sẻ, thêm RSS riêng) | FXStreet, InvestingLive, CoinDesk, Fed | **Không** |
| 🤝 **Đối tác** (cấp bậc, hoa hồng 30 ngày, khách hàng) | Exness **Partnership API** | Có (scope Partnership) |

> Chưa có key vẫn dùng được: màn hình đầu có **"Xem trước không cần API"** — lịch kinh tế và tin tức
> hoạt động đầy đủ, giá/cảnh báo/đối tác hiện hướng dẫn kết nối.

---

## 1. Chuẩn bị API key

### 1.1 Trader API (giá, tài khoản, giao dịch)

1. Vào **Personal Area** → mục API → tạo API key với scope **Trading** (Read-only là đủ để xem).
   Key nhận cặp **API key** + **private key** (hex 128 ký tự hoặc PEM).
2. Vào **Personal Area** (my.exness.com) → Cài đặt → **Key Management / API** → tạo key scope
   **Trading** (Read-only là đủ) và **chọn tài khoản giao dịch** cho key. Trên trang đó có ô
   **DNS widget** hiện **Gateway host** (dạng `https://…`, mỗi tài khoản/môi trường một host khác nhau,
   không đoán) — dán đúng host đó vào ô Trader API.
3. **Account ID** là chuỗi số dương (uint64) của tài khoản giao dịch đã chọn cho key (xem trong Personal Area).

Khi bấm **Lưu & kiểm tra kết nối**, app gọi `GET {gateway}/v1/trading/access-point?account_id=…` để lấy
**access point** của tài khoản rồi lưu lại. **Mọi REST và WebSocket sau đó đi qua access point** (không phải
gateway); gateway chỉ dùng để discovery. Các lần sau mở app dùng lại access point đã lưu (đúng khuyến nghị
của Exness: discovery bị rate limit, chỉ gọi một lần rồi cache).

### 1.2 Partnership API (hoa hồng đối tác)

Giống app [PartnerHub](EXNESS-PARTNER.md): key tại
<https://my.exness.partners/settings/api-management>, scope **Read-only**, host trong DNS widget.
Nếu key dùng chung cho cả hai API thì bật **"Dùng API key riêng cho Trader API"** = tắt; nếu hai key
khác nhau thì bật và dán key Trader API vào.

Thông tin đăng nhập lưu trong **Keychain** (`<bundle id>.credentials`, account `pulse.credentials`),
không dùng UserDefaults, không ghi log.

---

## 2. Cách gọi Trader API (tóm tắt đặc tả)

Mọi request đều mang headers ký **Ed25519** (xem `PulseApp/Sources/Services/ExnessSigner.swift`):

```
EXN-API-KEY        <api key>
EXN-IDEMPOTENCY-KEY <rỗng với GET>
EXN-TIMESTAMP      <ms>
EXN-SIGN-VERSION   1
EXN-DATA           base64url(JSON {api_key, idempotency_key, timestamp, sign_version:1, method, path, body_hash})
EXN-SIGN           base64url(Ed25519(EXN-DATA))
```

`path` là path **+ đúng chuỗi query** đã ký — app ghép query theo thứ tự truyền vào, không sắp xếp lại.

| Mục đích | Endpoint (host) |
|---|---|
| Phát hiện access point | `GET /v1/trading/access-point?account_id=` — **gateway** (DNS widget) |
| Thông tin tài khoản | `GET /v1/configuration/accounts/{id}/account` — access point |
| Danh sách mã | `GET /v1/configuration/accounts/{id}/instruments` — access point |
| Snapshot (lệnh, vị thế, số dư) | `GET /v1/trading/accounts/{id}/snapshot` — access point |
| Nến giá | `GET /v1/market-data/accounts/{id}/candles?instrument=&timeframe=&from=&to=&price_type=bid` — access point |
| Ticks WebSocket | `wss://{access_point}/v1/server-events/accounts/{id}/ws/ticks` (handshake ký GET) |

- Nến: `from` inclusive, `to` exclusive; app cộng thêm 1 nến ở `to` để lấy nến đang tạo. Khung:
  `M1 M5 M15 M30 H1 H4 D1`. Giá là JSON number, mã hoá `price_type=bid`.
- Ticks: **handshake WebSocket phải ký như một GET** (headers `EXN-*`, `EXN-DATA.path` = đúng path
  `/v1/server-events/accounts/{id}/ws/ticks`, tạo mới mỗi lần kết nối vì có timestamp), sau đó gửi
  `{"id":"pulse-ticks","subscribe":{"event":"ticks","instruments":[…]}}` → `{instrument, bid, ask, timestamp}`;
  throttled ≤ 500 ms. **Mã không tồn tại làm server đóng kết nối (1008)** — vì vậy app chỉ đăng ký các mã
  có trong danh sách `instruments` của tài khoản.
- Không có replay: khi rớt mạng app tự kết nối lại (exponential backoff 2 s → 30 s) và đăng ký lại;
  giá sẽ cập nhật từ tick kế tiếp.
- Lỗi thường gặp: `1000` key, `1001` chữ ký, `2000` sai account, `4003` thị trường đóng,
  `REQUEST_RATE_LIMIT` (không retry).

---

## 3. Lịch kinh tế (miễn phí, không cần key)

Nguồn: **Forex Factory** qua CDN công khai của Fair Economy Media:

- `https://nfs.faireconomy.media/ff_calendar_thisweek.json`
- `https://nfs.faireconomy.media/ff_calendar_nextweek.json`

Mỗi sự kiện: `title, country, date (ISO 8601 có offset -05:00), impact (High|Medium|Low|Holiday),
forecast, previous`. App gộp 2 tuần, bỏ trùng, chuyển giờ về múi giờ thiết bị, lưu cache vào
UserDefaults để có dữ liệu khi offline. Giới hạn của nguồn: chỉ có **tuần này + tuần sau**, không có
lịch dài hạn; lịch sử đã qua vẫn nằm trong cache đến cuối tuần.

**Nhắc sự kiện**: bấm chuông → local notification trước 15 phút (`UNCalendarNotificationTrigger`),
không cần server. Huỷ bằng cách bấm lại.

---

## 4. Tin tức (RSS/Atom, miễn phí)

| Nguồn | URL | Nhóm |
|---|---|---|
| FXStreet | `https://www.fxstreet.com/rss/news` | Forex & Hàng hoá |
| InvestingLive (ForexLive) | `https://investinglive.com/feed/news` | Tin nhanh |
| CoinDesk | `https://www.coindesk.com/arc/outboundfeeds/rss/` | Tiền mã hoá |
| Federal Reserve | `https://www.federalreserve.gov/feeds/press_all.xml` | Ngân hàng trung ương |

- Parser RSS 2.0 + Atom viết bằng `XMLParser` (`PulseApp/Sources/Models/NewsModels.swift`): lấy
  title/link/pubDate/description, bỏ thẻ HTML, giải mã entity, tóm tắt ≤ 240 ký tự, parse nhiều định
  dạng ngày (ISO có/không fraction, RFC 822 `GMT`/`+0700`).
- Tải song song tất cả nguồn (`withTaskGroup`), gộp, bỏ trùng link, sắp mới nhất trước, tối đa 300 tin.
- Lọc theo nhóm, tìm kiếm trong tiêu đề + tóm tắt, đọc bản đầy đủ bằng `SFSafariViewController`,
  chia sẻ bằng `ShareLink`.
- **Thêm nguồn riêng**: Cài đặt → Nguồn tin tức → Thêm nguồn RSS/Atom (bắt buộc `https://`).
  Tắt cả nhóm nguồn bằng toggle.

---

## 5. Cảnh báo giá — cách hoạt động

1. **Tạo**: Giá → 🔔 hoặc tab Cảnh báo → chọn mã, loại (Giá chạm mức / Biên độ %), hướng
   (Vượt lên / Rơi xuống / Chạm mức 2 chiều theo giá tham chiếu), mức mục tiêu, ghi chú.
2. **Kiểm tra**: mỗi tick WebSocket đến, `AlertEvaluator.fire` so mid price với điều kiện.
   - Mức giá: **một lần** — tự tắt sau khi kích hoạt (bật lại để dùng tiếp).
   - Biên độ %: giữ bật, cách nhau tối thiểu **60 phút**.
3. **Báo**: toast trên màn hình + ghi vào **Lịch sử kích hoạt** (50 lần); nếu app không ở foreground →
   **local notification** (thread `pulsehub.alerts`), bấm vào mở tab Cảnh báo.
4. **App đóng**: Background App Refresh (id `<bundle id>.alert-refresh`, tối thiểu 15 phút) dùng
   `candles?timeframe=M1&count=5` để lấy giá rồi đánh giá lại. iOS **tự quyết định** thời điểm chạy;
   bật *Cài đặt → Chung → Background App Refresh* và *Cài đặt → Pulse → Background App Refresh*.

> ⚠️ Cảnh báo chỉ chính xác khi app đang mở (ticks thời gian thực). Khi app đóng, tần suất kiểm tra
> phụ thuộc iOS — không đảm bảo từng giây. Đây là giới hạn của nền tảng, không phải lỗi app.

---

## 6. Build & cài

```bash
# GitHub Actions tự build khi push vào PulseApp/**, project.yml, scripts/**
./scripts/make-ipa.sh --scheme PulseHub     # → dist/PulseHub-1.0.0-1-unsigned.ipa
./scripts/selfcheck.sh                      # kiểm tra không cần Xcode
```

Tải bản mới nhất: **[PulseHub-unsigned.ipa](https://github.com/TradingLeak/IOS/releases/download/latest-pulsehub-ipa/PulseHub-unsigned.ipa)**
(tag `latest-pulsehub-ipa`, build số `sha256` kèm theo). Cài qua **ESign** xem
[INSTALL.md → Cách 4](INSTALL.md#cách-4--esign--feather--scarlet-ký-ngay-trên-máy) — thay link tải
bằng link Pulse ở trên. Sau khi cài, cho phép **Notifications** và **Background App Refresh** trong
Cài đặt → Pulse.

---

## 7. Cấu trúc mã nguồn

```
PulseApp/
├── Info.plist                         # BGTaskSchedulerPermittedIdentifiers = <bundle>.alert-refresh
├── Resources/Assets.xcassets          # AppIcon 1024×1024, AccentColor, LaunchBackground
├── Sources/
│   ├── App/PulseHubApp.swift          # @main, delegate (thông báo + BG), giao diện nav/tab
│   ├── Design/                        # PulseTheme (màu, gradient, card, glass) + PulseComponents
│   ├── Models/
│   │   ├── TradingModels.swift        # Account, Candle, Tick, Quote, Timeframe, PulseSymbol, PulseFormat
│   │   ├── EconomicEvent.swift        # EventImpact, ImpactFilter, EconomicCalendarService (Forex Factory)
│   │   ├── NewsModels.swift           # NewsCategory, NewsFeed, NewsItem, RSSParser, FeedDate, HTMLText
│   │   ├── PriceAlert.swift           # PriceAlert, AlertEvaluator, AlertHistoryStore, CalendarReminderStore
│   │   ├── PartnerSummary.swift       # mô hình tối giản cho tab Đối tác
│   │   └── Formatting.swift           # Fmt (số/tiền/ngày vi_VN)
│   ├── Services/
│   │   ├── ExnessSigner.swift         # Ed25519 + EXN-* headers (dùng chung với PartnerHub)
│   │   ├── ExnessClient.swift         # GET ký số, path+query, parse lỗi Partnership & Trader
│   │   ├── TradingClient.swift        # access-point, account, instruments, snapshot, candles
│   │   ├── TickStream.swift           # WebSocket ticks: subscribe, ping, reconnect
│   │   ├── PulseCredentials.swift     # PulseCredentials + Keychain
│   │   ├── NewsService.swift          # tải song song nhiều RSS, merge, search, cache
│   │   └── AlertNotifier.swift        # local notification + AlertBackgroundRefresh
│   ├── ViewModels/PulseStore.swift    # trạng thái trung tâm (giá, nến, cảnh báo, lịch, tin, đối tác)
│   └── Views/                         # Onboarding, Dashboard, Market, Calendar, News, Alerts,
│                                      # Partner, Settings, AlertEditor + Components (Charts, Rows)
└── Tests/                             # signer, client, model (symbol, format, calendar, RSS, alert)
```

## 8. Kiểm thử

`PulseHubTests` (chạy trên Simulator trong CI) phủ: ký số (vector spec Ed25519), path/query,
parse lỗi; phân loại mã & số chữ số; định dạng giá/thời gian; parse JSON lịch (offset -05:00),
gom theo ngày; parse RSS 2.0 (CDATA, entity) và Atom (href, updated); nhiều định dạng ngày feed;
HTML → text; merge/tìm kiếm tin; cảnh báo (hướng, một lần, cooldown %, nội dung thông báo);
parse instruments nhiều schema; chuẩn hoá access point & URL WebSocket; parse tick (number/chuỗi/epoch ms).

## 9. Giới hạn đã biết

- Giá chỉ có khi tài khoản Exness của bạn có **Trader API** và mã đó có trên tài khoản. Cuối tuần
  thị trường đóng → không có tick/nến mới (app hiện trạng thái, không báo lỗi).
- Lịch chỉ gồm tuần này + tuần sau (giới hạn của nguồn miễn phí).
- RSS một số nguồn (Fed) chỉ có tiêu đề, không có tóm tắt — app mở trang gốc để đọc.
- Background App Refresh do iOS quyết định; không thay thế được push từ server (IPA unsigned không có APNs).
- Dữ liệu chỉ mang tính tham khảo, không phải khuyến nghị đầu tư. Pulse không phải ứng dụng chính thức của Exness.

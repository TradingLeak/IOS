# 📱 PartnerHub — Theo dõi hoa hồng Exness Partner (iOS)

**PartnerHub** là ứng dụng iOS nằm trong repo này, dùng **Exness Partnership API**
(đúng API quản lý tại <https://my.exness.partners/settings/api-management>) để xem
hoa hồng đối tác: tổng quan, lịch sử thưởng, khách hàng, lệnh đã chốt, lệnh chờ tính
thưởng và rebate. Khi có **khoản thanh toán hoa hồng mới**, app **pop-up thông báo** trong
app và gửi **thông báo hệ thống** (local notification) khi đang chạy nền. App chỉ **đọc**
dữ liệu, không đặt lệnh hay thay đổi cấu hình.

```
┌──────────────┐   Ed25519 + EXN-* headers   ┌─────────────────────┐
│  PartnerHub  │ ──────────────────────────► │  Exness Partner API │
│  (iOS)       │   GET /v1/partnership/...   │  (host trong DNS    │
│              │                             │   widget)            │
└──────────────┘                             └─────────────────────┘
```

## 1. Tính năng

| Màn | Nội dung |
|---|---|
| **Tổng quan** | Cấp bậc đối tác, số khách hàng, volume, hoa hồng trong kỳ, biểu đồ cột theo ngày/tuần/tháng, rebate đã trả/từ chối/lỗi, 5 hoạt động gần nhất |
| **Hoa hồng** | Lọc theo 7 ngày / 30 ngày / tháng này / tháng trước / năm nay / tất cả; gộp theo ngày/tuần/tháng; tổng reward, volume, số lệnh; chi tiết từng dòng thưởng |
| **Khách hàng** | Tìm theo UID/quốc gia/trạng thái, sắp xếp theo hoa hồng/volume/mới nhất; badge KYC/FTD/FTT |
| **Giao dịch** | Lệnh đã chốt trong 7/14/30 ngày (API giới hạn 32 ngày/lần), lệnh chờ tính hoa hồng, tổng reward |
| **Cài đặt** | Nhập/sửa API host + API key + private key, kiểm tra kết nối, bật/tắt thông báo, kiểm tra thanh toán ngay, làm mới, xoá dữ liệu |
| **Thông báo** | Pop-up đầu màn hình khi phát hiện khoản mới: hoa hồng ghi có theo ngày, hoàn phí đã trả / bị từ chối / lỗi. Chạm vào pop-up → mở tab Hoa hồng |

Dữ liệu tiền tệ được parse bằng `Decimal` (API trả chuỗi thập phân) để tránh sai số
dấu phẩy động. Mọi yêu cầu đều ký cục bộ bằng Ed25519 rồi mới gửi đi.

### Thông báo khi có thanh toán

Exness không có webhook/push cho đối tác, nên app tự **so sánh với lần kiểm tra trước**
(`PaymentWatcher`): ghi lại các ngày hoa hồng và id các lần trả hoàn phí đã biết; lần sau
thấy ngày/id mới → tạo `PaymentEvent` → pop-up + thông báo hệ thống. Lần đầu chạy chỉ ghi
nhận baseline (không báo toàn bộ lịch sử là "mới").

App kiểm tra ở các thời điểm:

| Khi nào | Cách báo |
|---|---|
| Mở app, kéo để làm mới, quay lại app sau > 5 phút | Pop-up trong app (7 giây, có rung nhẹ) |
| App chạy nền / đã đóng | iOS đánh thức định kỳ qua **Background App Refresh** (≈30–60 phút/lần, do iOS quyết định) → thông báo hệ thống |

Bật/tắt và cấp quyền thông báo ở **Cài đặt → Thông báo thanh toán**. Bấm vào thông báo hệ
thống mở thẳng tab Hoa hồng. Không có server trung gian nên **không thể** báo tức thời —
thông báo đến ở lần kiểm tra gần nhất.

> Giới hạn: Background App Refresh cần người dùng bật trong *Cài đặt → Chung → Background
> App Refresh*; iOS chỉ chạy khi app được dùng thường xuyên và máy đủ điều kiện. Trên IPA
> unsigned cài qua TrollStore/Sideloadly vẫn hoạt động (không cần entitlement).

## 2. Tạo API key trên Exness

1. Đăng nhập <https://my.exness.partners> bằng tài khoản **Partner Personal Area**.
2. Vào **Settings → API Management** (<https://my.exness.partners/settings/api-management>).
3. Bấm **Create API key**, đặt tên và ngày hết hạn (nếu có).
4. Chọn scope **Partnership → Read-only** (`partnership.all:read`).
   App không cần quyền ghi; **đừng dùng Full access** nếu không có lý do đặc biệt.
5. Chọn cách tạo key:
   - **Exness tạo key pair**: lưu lại `private_key` — chuỗi **128 ký tự hex**
     (32 byte seed + 32 byte public key).
   - **Tự tạo key pair (Ed25519)**: đăng ký public key, giữ file PEM PKCS#8
     (`-----BEGIN PRIVATE KEY-----`).
6. Sao chép **API key** (`exnsk-...`) và **API host** hiển thị trong **DNS widget**.
   Host chỉ gồm `https://<host>`, **không** có `/v1/...` — app tự thêm đường dẫn.
7. Dán 3 thông tin trên vào app → **Kết nối tài khoản**. App sẽ gọi
   `GET /v1/partnership/partner/default-link` để kiểm tra trước khi lưu.

> Host không cố định — nó phụ thuộc tài khoản/khu vực và được Exness cung cấp trong
> DNS widget. Không đoán host; hãy sao chép đúng giá trị ở đó.

## 3. Bảo mật

- API key + private key lưu trong **Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`),
  không dùng `UserDefaults`, không ghi log, không kèm theo IPA.
- Chữ ký **Ed25519** được tạo ngay trên thiết bị cho từng yêu cầu (timestamp mới mỗi lần).
- App chỉ dùng scope **Read-only**; không có thao tác ghi nào.
- **Lưu ý:** tài liệu Exness khuyến nghị giữ private key ở backend, không đặt trong
  app di động. Nếu bạn dùng cho đội nhóm/production, nên dựng một proxy backend giữ
  key và cho app gọi proxy. PartnerHub phù hợp cho đối tác cá nhân tự dùng.

## 4. API đã dùng

Tất cả là `GET`, trả JSON; phân trang bằng `limit`/`offset`, giữ nguyên bộ lọc khi
sang trang. Tên field trong app dùng camelCase nhờ `keyDecodingStrategy = .convertFromSnakeCase`.

| Endpoint | Dùng cho |
|---|---|
| `GET /v1/partnership/partner/default-link` | Kiểm tra kết nối, hiện link giới thiệu |
| `GET /v1/partnership/partner-tier/partner-state` | Cấp bậc, số khách, volume, subpartner |
| `GET /v1/partnership/reports/rewards?aggregate_by=...&reward_date_from=...&reward_date_to=...` | Lịch sử hoa hồng + tổng |
| `GET /v1/partnership/reports/clients?ordering=-reward_usd` | Danh sách khách hàng |
| `GET /v1/partnership/reports/orders?date_from=...&date_to=...` | Lệnh đã chốt (≤ 32 ngày/lần) |
| `GET /v1/partnership/reports/orders/pending` | Lệnh chờ tính thưởng |
| `GET /v1/partnership/autorebates/history` | Lịch sử rebate |
| `GET /v1/partnership/autorebates/payments` | Thanh toán rebate |

### Ký yêu cầu

```json
// EXN-DATA (giải mã base64url)
{
  "api_key": "exnsk-...",
  "idempotency_key": "",
  "timestamp": 1773656070123,
  "sign_version": 1,
  "method": "GET",
  "path": "/v1/partnership/reports/rewards?limit=1000&aggregate_by=day",
  "body_hash": "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU"
}
```

- `EXN-DATA`/`EXN-SIGN`: base64url **không pad**.
- `EXN-SIGN` = Ed25519 signature của **bytes payload đã giải mã**.
- `path` phải ký **đúng nguyên văn** path + query đã gửi (không sắp xếp lại).
- `body_hash` = SHA-256 của body; với GET là SHA-256 của chuỗi rỗng.
- `EXN-IDEMPOTENCY-KEY` gửi rỗng cho GET.
- Timestamp tính bằng **miligây** và phải gần giờ máy chủ.

Code: `PartnerApp/Sources/Services/ExnessSigner.swift`.

## 5. Lỗi thường gặp

| Mã | Nghĩa | Cách xử lý |
|---|---|---|
| `1000` / `AUTH_INVALID_API_KEY` | Key sai, hết hạn, bị thu hồi hoặc IP không được phép | Tạo lại key, kiểm tra hạn dùng và IP allowlist |
| `1001` / `AUTH_INVALID_SIGNATURE` | Sai chữ ký | Kiểm tra private key, giờ thiết bị, đúng định dạng hex/PEM |
| `1002` / `AUTH_FORBIDDEN` | Key không có scope Partnership | Tạo key với Partnership → Read-only |
| `1003` / `AUTH_RATE_LIMIT` | Quá 600 request/60s/partner | Giảm tần suất, honour `Retry-After` |
| `3001` / `REQUEST_INVALID_PARAMETERS` | Header/payload ký không khớp | Kiểm tra `EXN-*`, timestamp, path |
| `ValidationError` (400) | Sai tham số | Xem `details`, sửa filter ngày |
| `429 Throttled` | Rate limit | Chờ rồi thử lại |
| `5xx` | Lỗi tạm thời của Exness | Retry với backoff |

App hiển thị thông điệp tiếng Việt cho các mã phổ biến ở `ExnessAPIError.localizedMessage`.

## 6. Build & test

```bash
# macOS
brew install xcodegen
xcodegen generate
open VietMap.xcodeproj        # chọn scheme PartnerHub

xcodebuild test -project VietMap.xcodeproj -scheme PartnerHub \
  -destination 'platform=iOS Simulator,name=iPhone 16'

./scripts/make-ipa.sh --scheme PartnerHub   # → dist/PartnerHub-1.0.0-1-unsigned.ipa
```

Trên GitHub: workflow **Build PartnerHub IPA** (file
`.github/workflows/build-partnerhub-ipa.yml`) chạy unit test trên Simulator, build
IPA unsigned và phát hành tag `latest-partnerhub-ipa`:

```
https://github.com/TradingLeak/IOS/releases/download/latest-partnerhub-ipa/PartnerHub-unsigned.ipa
```

Cài IPA: xem [INSTALL.md](INSTALL.md).

Kiểm tra không cần Xcode:

```bash
./scripts/selfcheck.sh    # gồm kiểm tra PartnerApp: @main, ngoặc, plist, icon
./scripts/test-pack.sh
```

## 7. Cấu trúc mã nguồn

```
PartnerApp/
├── Info.plist
├── Resources/Assets.xcassets      # AppIcon 1024×1024, AccentColor, LaunchBackground
├── Sources/
│   ├── App/PartnerHubApp.swift    # entry point + appearance
│   ├── Design/                    # PartnerTheme, Components
│   ├── Models/                    # PartnerModels, Formatting, PaymentEvent
│   ├── Services/
│   │   ├── ExnessSigner.swift     # Ed25519 + EXN-* headers, parse private key
│   │   ├── ExnessClient.swift     # GET, query string, lỗi API
│   │   ├── CredentialKeychain.swift
│   │   ├── PaymentWatcher.swift   # so sánh với snapshot → khoản thanh toán mới
│   │   └── PaymentNotifier.swift  # local notification + Background App Refresh
│   ├── ViewModels/PartnerStore.swift
│   └── Views/                     # Root, Onboarding, MainTab, Overview, Rewards,
│                                  # Clients, Transactions, Settings, Components
│                                  # (+ PaymentToast: pop-up thanh toán)
└── Tests/                         # Signer, Client, Model, Formatting, PaymentWatcher
```

## 8. Giới hạn

- Chỉ đọc; không tạo/sửa campaign, rebate rule, referral agent.
- Không có push tức thời (Exness không có webhook, IPA unsigned không có APNs): chỉ có
  local notification + Background App Refresh theo lịch của iOS (xem mục *Thông báo khi có thanh toán*).
- Báo cáo của Exness cập nhật không đồng bộ; lần tải sau có thể lệch chút so với lần trước.
- Không phải ứng dụng chính thức của Exness. Dữ liệu chỉ đọc từ API của chính tài khoản đối tác.

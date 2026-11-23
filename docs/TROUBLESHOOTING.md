# 🧯 Lỗi thường gặp

## Build / CI

### `Signing for "HelloIPA" requires a development team`
Bạn đang build mà không truyền đủ cờ tắt ký.

```bash
./scripts/make-ipa.sh --verbose   # script đã truyền sẵn, nếu vẫn lỗi xem log
```

Nếu build bằng Xcode GUI: mở **Build Settings** → *Signing* → đặt
`CODE_SIGNING_ALLOWED = NO` cho cả Debug và Release (đã có trong `project.yml`,
chạy `xcodegen generate` lại để áp dụng).

### `xcodegen: command not found` (trên CI hoặc Mac)
```bash
brew install xcodegen
```

### `Spec validation error: ... scheme ... not found`
Scheme trong workflow/lệnh không khớp. Kiểm tra:

```bash
xcodebuild -list -project HelloIPA.xcodeproj
```

Sửa `SCHEME` trong workflow hoặc truyền `--scheme`.

### `Unable to find a destination matching the provided destination specifier`
Thiếu iOS SDK hoặc đang chọn Command Line Tools. Trên Mac:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -showsdks | grep iphoneos
```

### `The iOS deployment target is set to 15.0, but the range of supported deployment targets is ...`
Xcode mới đã bỏ hỗ trợ iOS cũ. Sửa `project.yml`:

```yaml
deploymentTarget:
  iOS: "16.0"     # hoặc cao hơn
```

rồi `xcodegen generate` và build lại.

### `error: An error occurred during the archive: Missing app icon`
- Icon phải là `AppIcon-1024.png` đúng 1024×1024, **không alpha**:
  ```bash
  identify App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
  # nếu có alpha: -background white -alpha remove -alpha off
  ```
- Đảm bảo `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` và file
  `Contents.json` khai báo `"idiom": "universal", "platform": "ios", "size": "1024x1024"`.

### `Command PhaseScriptExecution failed with a nonzero exit code`
Một build phase (vd. SwiftLint, R.swift, Crashlytics script) lỗi. Xem log quanh chữ
`error:`; tạm thời có thể xoá phase đó trong `project.yml`/Xcode. Nếu là lỗi sandbox
script: đặt `ENABLE_USER_SCRIPT_SANDBOXING = NO` (đã có trong repo).

### `Could not resolve package dependencies` (CI)
Runner cần mạng tới GitHub. Nếu repo dùng private package, thêm token:
```yaml
- run: xcodebuild -project ... -resolvePackageDependencies
  env:
    GITHUB_TOKEN: ${{ secrets.PACKAGE_TOKEN }}
```
Hoặc đặt `-skipPackagePluginValidation -skipMacroValidation` (script đã thêm sẵn
cho Xcode ≥ 15).

### Workflow chạy mãi không xong / hết phút
- macOS runner nhân hệ số **10×** phút. Repo public = miễn phí.
- Dùng `concurrency` (đã cấu hình) để huỷ run cũ.
- Cache `build/` không nên cache; chỉ cache SPM bằng `actions/cache` trên
  `~/Library/Developer/Xcode/DerivedData/**/SourcePackages`.

### `Xcode 26 / iOS 26 SDK` và deployment target
Repo đặt iOS 15.0. Nếu runner mới nhất chỉ còn hỗ trợ từ 16.0+, nâng như mục trên.
Bạn cũng có thể ghim Xcode: `with: xcode-version: "16.4"`.

## IPA

### `ApplicationVerificationFailed` khi cài
Bình thường với IPA unsigned. Cần ký lại — xem [INSTALL.md](INSTALL.md).

### Cài xong nhưng app trắng màn hình / crash ngay
- Xem log: Xcode → Devices → *View Device Logs*.
- Kiểm tra `UIApplicationSceneManifest` / `@main` trong code.
- App dùng entitlement (push notification, HealthKit, Sign in with Apple, IAP) sẽ
  crash hoặc không hoạt động khi unsigned → cần tài khoản Developer trả phí.

### `The app's Info.plist is missing ...` / `CFBundleIconName`
Chạy lại build; nếu lỗi vẫn còn, đảm bảo bạn **không** xoá bước
`ASSETCATALOG_COMPILER_APPICON_NAME` khi tuỳ biến `project.yml`.

### Cài đè lên bản cũ bị lỗi
Bundle ID khác nhau, hoặc chữ ký khác (bản Sideloadly vs bản Apple Developer).
Gỡ app cũ rồi cài lại — dữ liệu trong app sẽ mất.

### Muốn biết IPA này có chữ ký chưa
```bash
unzip -l App-unsigned.ipa | grep -E '_CodeSignature|embedded.mobileprovision'
# không có kết quả = unsigned

codesign -dv --verbose=2 Payload/App.app 2>&1 | head   # cách kiểm tra trực tiếp
```

## Sideload tool

### Sideloadly: `Guru Meditation` / `Failed to start Anisette`
Đóng iTunes, khởi động lại dịch vụ Apple Mobile Device:
```powershell
# Windows
sc stop "Apple Mobile Device Service" && sc start "Apple Mobile Device Service"
```

### Sideloadly: `Please sign in with an app-specific password`
Apple ID có 2FA → tạo *App-specific password* tại <https://appleid.apple.com> và
dùng mật khẩu đó.

### `This app is not available in your region` / `maximum number of apps`
Apple ID miễn phí giới hạn 3 app + 10 App ID/tuần. Gỡ bớt app hoặc chờ tuần sau.

### SideStore/AltStore không refresh được
- Điện thoại và máy chạy AltServer cùng Wi-Fi.
- Bật *Background Refresh* + *Refresh on this device*.
- iOS 17+ cần SideStore ≥ 0.6 và cặp `jitterbugpair` mới.

## Gỡ rối chung

```bash
make distclean          # xoá build/, dist/, project đã sinh
xcodegen generate       # sinh lại project
rm -rf ~/Library/Developer/Xcode/DerivedData/HelloIPA-*
./scripts/make-ipa.sh --verbose
```

Nếu vẫn lỗi, mở issue kèm: phiên bản Xcode, phiên bản iOS, đoạn log lỗi
(`dist/../build/xcodebuild.log`, 50 dòng cuối là đủ).

---

## Về việc ghim phiên bản Xcode trong CI

Workflow đang ghim `xcode-version: "16.4"` để build tất định với deployment
target iOS 15.0. Khi GitHub bỏ image `macos-15` hoặc bỏ Xcode 16.4:

1. Đổi `xcode-version` thành `latest-stable` (hoặc `"26.0"`…).
2. Nâng `deploymentTarget: iOS: "16.0"` trong `project.yml` nếu Xcode báo
   deployment target không còn được hỗ trợ.
3. Chạy `xcodegen generate` rồi build lại.

Muốn biết Xcode mới yêu cầu iOS tối thiểu bao nhiêu:

```bash
xcodebuild -showsdks
xcrun --sdk iphoneos --show-sdk-version
```

---

# Phần 2 — Lỗi riêng của app bản đồ (MapKit + AI)

## Bản đồ

### App không hiện vị trí của tôi
- Lần đầu mở app, iOS sẽ hỏi quyền vị trí → chọn **Cho phép khi dùng ứng dụng**.
- Nếu đã lỡ từ chối: Cài đặt → **Bản đồ Việt Nam** → Vị trí → *Khi dùng ứng dụng*.
- `Info.plist` phải có `NSLocationWhenInUseUsageDescription`, nếu thiếu app sẽ không xin
  được quyền (selfcheck đã kiểm tra khoá này).

### Nhấn vào nút định vị mà bản đồ không di chuyển
`CLLocationManager` cần vài giây để có GPS đầu tiên (nhất là trong nhà). App hiện toast
“Đang xác định vị trí…”, đợi rồi bấm lại.

### Không tìm thấy tuyến / "Apple Maps chưa có dữ liệu xe buýt"
- Dữ liệu Apple Maps ở Việt Nam chưa phủ đủ như Google Maps. Xe buýt/đi bộ ngoài đô thị
  lớn thường không có tuyến.
- Thử đổi phương tiện (Ô tô ↔ Đi bộ), hoặc chọn điểm gần hơn.
- Tuyến qua biển/sông/đảo (Phú Quốc, Côn Đảo) thường không có tuyến đường bộ.

### Tuyến đường vẽ lệch hoặc không hiện
- Kiểm tra bạn đang zoom quá xa; bấm nút ⤢ (bên phải) để fit toàn tuyến.
- Nếu bản đồ ở chế độ Vệ tinh, đường vẫn hiển thị nhưng khó nhìn — chuyển về Tiêu chuẩn.

### Nhấn giữ trên bản đồ không đặt được điểm đến
Cử chỉ cần giữ ~0.4 giây. Nếu đang di chuyển bản đồ, nhả tay rồi thử lại (app cho phép
nhận diện đồng thời với cử chỉ pan).

## AI

### "Chưa cấu hình AI" / nút gửi câu lệnh báo lỗi
Đây là trạng thái bình thường khi chưa có API key: app vẫn hiểu các câu cơ bản bằng bộ
phân tích offline (“từ A đến B”, “đi bộ”, “xe buýt”, “tránh đường đông”, “ghé X”).
Muốn AI hiểu câu tự nhiên hơn: Cài đặt → dán API key → **Kiểm tra kết nối**.

### HTTP 401 / 403 — API key bị từ chối
- Key sai, hết hạn, hoặc thuộc tài khoản khác với base URL.
- Với ckey.vn: key tạo ở trang cá nhân; base URL phải là `https://api.xah.io/v1`.
- Kiểm tra không có khoảng trắng/dấu xuống dòng khi dán key.

### HTTP 404 — Không tìm thấy endpoint
- Base URL thường phải có `/v1` (app tự thêm `/chat/completions`).
- Nếu bạn dán cả URL `.../v1/chat/completions` app cũng chấp nhận.
- Kiểm tra tên model có đúng trong danh sách của nhà cung cấp không.

### HTTP 429 — Hết hạn mức / gọi quá nhanh
Đợi ít phút, hoặc kiểm tra số dư tài khoản AI. App tự chuyển sang parser offline để bạn
vẫn tìm được tuyến.

### AI trả lời lan man, không phải JSON
App tự gửi lại một lần với yêu cầu “chỉ trả JSON”; nếu vẫn lỗi sẽ dùng parser offline.
Giảm `temperature` về 0–0.2 trong Cài đặt để model ổn định hơn. Model nhỏ (< 7B) đôi khi
không theo nổi schema — dùng model lớn hơn.

### AI tìm ra địa danh nhưng sai chỗ
AI chỉ trả **tên**, còn toạ độ do Apple Maps tra. Nếu tên trùng (ví dụ “Hồ Tây” ở tỉnh
khác), hãy nói rõ hơn: “Hồ Tây, Hà Nội”.

### Muốn dùng model chạy trên máy (Ollama) trong LAN
Base URL `http://<ip-máy>:11434/v1`, model `qwen2.5`, API key nhập chuỗi bất kỳ (Ollama
không kiểm tra). iPhone và máy tính phải cùng Wi-Fi.

## CI / build

### "error: value of optional type 'String?' must be unwrapped"
Đã gặp với `MKRoute.Step.instructions`/`.notice`: các thuộc tính này là optional trong một
số phiên bản SDK. Code hiện tại gán qua `String?` để tương thích cả hai.

### Job `unit-tests` đỏ nhưng job `build` xanh
App vẫn có IPA dùng được; lỗi nằm ở test logic (parser/format/AI client). Xem
*Annotations* của job để biết test nào fail.

### Muốn bỏ test cho nhanh
`Run workflow` → tắt `run_tests`, hoặc push với commit chỉ sửa docs (workflow vẫn chạy
nhưng bạn có thể cancel job test).

---

# Phần 3 — Lỗi riêng của PartnerHub (Exness Partner API)

Mọi lỗi API đều hiện ngay trong app dưới dạng `[mã] mô tả` (banner đỏ ở đầu màn hình). Các mã hay gặp:

### `[1000]` API key không hợp lệ / hết hạn / sai IP
Vào <https://my.exness.partners/settings/api-management> kiểm tra key còn **Active** không, có bị
giới hạn IP không. Dán lại đúng **API key** (không phải partner code) trong *Cài đặt* → *Kiểm tra kết nối*.

### `[1001]` Chữ ký số không hợp lệ
- **Private key** phải là chuỗi **hex 128 ký tự** (64 byte: seed 32 byte + public key 32 byte) hoặc
  **PEM PKCS#8** (`-----BEGIN PRIVATE KEY-----`). Thiếu/thừa ký tự là lỗi ngay.
- Giờ trên iPhone bị lệch > vài phút so với giờ thật → chỉnh **Settings → General → Date & Time → Set Automatically**.
- Nếu bạn tạo lại key trên trang Exness thì private key cũ sẽ không còn dùng được.

### `[1002]` API key không có quyền Partnership
Khi tạo key phải chọn scope **Read-only** (`partnership.all:read`) hoặc **Full access** (`partnership.all`).

### `[1003]` / `[429]` Truy vấn quá nhanh (Throttled)
Exness giới hạn **600 request / 60 giây / đối tác** (tính trên mọi key). Kéo để làm mới liên tục
trên nhiều màn hình có thể chạm giới hạn — đợi ~1 phút rồi thử lại.

### `[3001]` / `ValidationError` — Tham số không hợp lệ
Thường gặp khi khoảng ngày **quá 32 ngày** với báo cáo lệnh, hoặc `date_to < date_from`. App chỉ gửi
kỳ 7/14/30 ngày nên nếu vẫn gặp, kiểm tra múi giờ/ngày trên máy.

### "Máy chủ không trả phản hồi HTTP" / không kết nối được
- **API host** phải là origin HTTPS, đúng giá trị trong **DNS widget** của trang API management,
  ví dụ `https://<api-host>` — **không** có path (`/v1`), query hay `/` cuối. Host không cố định, không đoán.
- Mạng đang chặn (DNS, tường lửa, VPN). Thử chuyển Wi-Fi ↔ 4G/5G.
- Hết thời gian chờ (30 giây) khi mạng chậm — app báo lỗi, kéo để thử lại.

### Dữ liệu trống dù kết nối thành công (màn "Chưa có dữ liệu")
Bình thường với tài khoản **mới**: chưa có khách hàng / chưa có lệnh chốt. Khách KYC nhưng chưa nạp
hoặc chưa giao dịch vẫn chưa phát sinh hoa hồng.

### `Không lưu được thông tin đăng nhập vào Keychain (mã -34018)`
Chỉ xảy ra trên Simulator cũ/không có entitlement keychain. Trên máy thật không gặp; nếu gặp, xoá app
và cài lại, hoặc build với Keychain Sharing capability.

### Không thấy pop-up / thông báo khi có khoản thanh toán mới
- **Lần đầu** sau khi cài/đăng nhập chỉ ghi nhận baseline (không báo lịch sử cũ là "mới"). Khoản
  phát sinh *sau* đó mới được báo.
- App đang mở: pop-up chỉ xuất hiện ở lần kiểm tra — mở app, kéo để làm mới, quay lại sau > 5 phút,
  hoặc **Cài đặt → Kiểm tra thanh toán ngay**.
- App đang đóng: phụ thuộc **Background App Refresh** — bật trong *Cài đặt → Chung → Background App
  Refresh*, và *Cài đặt → PartnerHub → Thông báo* phải cho phép. iOS tự chọn lúc chạy, có thể không
  chạy nếu app ít dùng/máy đang tiết kiệm pin.
- Đã đổi tài khoản/host khác trong Cài đặt? Dấu vết cũ được xoá, lần kiểm tra đầu chỉ ghi baseline.
- Muốn thử ngay: Cài đặt → Thông báo thanh toán → **Kiểm tra thanh toán ngay**. Nếu hiện "Chưa có
  khoản thanh toán mới" nghĩa là không có ngày hoa hồng / id hoàn phí mới so với lần trước.

### Thông báo hệ thống không hiện dù đã cấp quyền
Kiểm tra *Cài đặt → PartnerHub → Notifications* (Allow Notifications + banner). Focus mode /
Đừng làm phiền chặn cả local notification.

### Lỗi biên dịch `cannot find 'PartnerStore' in scope` / scheme PartnerHub thiếu
Chưa chạy `xcodegen generate` sau khi thêm target, hoặc mở `VietMap.xcodeproj` cũ. Chạy lại
`xcodegen generate` rồi chọn scheme **PartnerHub**.

### Muốn bỏ test cho nhanh
`Run workflow` → tắt `run_tests` (job `unit-tests` sẽ bị skip), job `build` vẫn chạy.

# Phần 4 — Lỗi riêng của Pulse (Trader API, lịch, tin tức, cảnh báo)

### Tab Giá hiện "Cần Trader API" / giá "—"
Chưa nhập đủ **host gateway** + **Account ID** (+ API key có scope **Trading**). Vào *Cài đặt* → mục
Trader API → **Lưu & kiểm tra kết nối**. Kết quả phải có dòng `✓ Trader API · access point …`.
Nếu `✗ Trader API · [1002] …` → key không có scope Trading; `[2000]` → sai Account ID.

### Giá đứng yên / "Kết nối lại…" / "Mất kết nối"
- Cuối tuần hoặc ngoài phiên thị trường đóng cửa → không có tick, bình thường.
- Access point sai (đổi tài khoản/host mà không kiểm tra lại) → bấm **Lưu & kiểm tra kết nối** để phát hiện lại.
- Mạng chặn WebSocket (Wi-Fi công ty, VPN) → thử 4G/5G. App tự kết nối lại mỗi 2→30 giây.
- Danh sách theo dõi có mã không tồn tại trên tài khoản: app tự lọc theo `instruments`; nếu danh sách
  mã chưa tải được (lỗi API), mở tab Giá kéo để tải lại.

### Biểu đồ trống nhưng giá vẫn chạy
Nến lấy từ REST (`candles`), có thể lỗi riêng (rate limit, mã không có nến ở khung đó). Kéo để tải lại,
đổi khung thời gian. Thông báo lỗi hiện ngay trong card biểu đồ.

### Tab Giá hiện "Không tải được dữ liệu — Yêu cầu thất bại (HTTP 404)"
Yêu cầu dữ liệu (candles/account) đã đi tới **gateway** — gateway chỉ có route discovery
`/v1/trading/access-point`, không có `/v1/market-data/...` nên trả 404. Nguyên nhân: chưa phát hiện được
access point (discovery thất bại) hoặc đang dùng bản build cũ (bản < 55a9bda gửi mọi REST lên gateway). Xử lý:
1. Cài bản build mới: app luôn discovery trước khi gọi REST và hiện **lý do discovery thất bại** thay vì 404.
2. *Cài đặt* → **Lưu & kiểm tra kết nối** → dòng phải là `✓ Trader API · access point …`. Nếu `✗`:
   `[1002]` key thiếu scope Trading · `[2000]` sai Account ID · `[1001]` private key không đúng cặp với Trading
   API key (bật "API key riêng" mà bỏ trống private key → app dùng private key Partnership → sai) · `HTTP 404`
   ngay ở bước discovery → URL gateway không lấy từ DNS widget.

### Tài khoản không có mã `XAUUSD` (biểu đồ trống, giá "—")
Tài khoản Standard dùng mã có đuôi (`XAUUSDm`, `EURUSDm`). App tự map mã trong danh sách theo dõi sang mã có
đuôi khi gọi candles/ticks và gán giá về mã gốc. Nếu vẫn báo "Tài khoản không có mã…" → mã đó thật sự không có
trong `instruments` của tài khoản (ví dụ tài khoản không giao dịch crypto) → đổi mã.

### `Chưa cấu hình Trader API (host + account ID + API key + private key)` trong tab Giá
Đúng như chữ: vào Cài đặt nhập đủ. Chỉ có Partnership key thì giá/cảnh báo không hoạt động.

### Không nhận được thông báo cảnh báo giá
- Tạo cảnh báo xong phải **bật** (toggle) và có giá thực (tick hoặc nến) — chưa có giá thì chưa thể kích hoạt.
- Cảnh báo theo **mức giá tự tắt** sau khi kích hoạt (bật lại để dùng lại); cảnh báo **%** cách nhau 60 phút.
- Kiểm tra *Cài đặt → Pulse → Notifications* (Allow + banner) và *Cài đặt → Chung → Background App Refresh*.
- App đóng: iOS định kỳ đánh thức (15–60 phút tuỳ usage) — không tức thời. Focus/Đừng làm phiền chặn cả local notification.
- Muốn thử ngay: tạo cảnh báo **Biên độ % 0.01%** cho mã đang có tick → kích hoạt trong vài giây.

### Lịch kinh tế trống / "Không tải được lịch kinh tế"
Nguồn `nfs.faireconomy.media` cần Internet; thử kéo để tải lại, đổi mạng. Nếu bộ lọc "Chỉ Cao" + tiền tệ
hiếm → không có sự kiện: bấm **Bỏ lọc tiền tệ** / chọn "Tất cả". Cuối tuần nguồn có thể đổi tuần sớm
(tuần mới bắt đầu Chủ nhật) — kéo để tải lại.

### "Nhắc trước 15 phút" không báo
Phải cấp quyền thông báo (Cài đặt → Thông báo → Cấp quyền). Mốc nhắc đã qua (sự kiện < 15 phút nữa)
thì không xếp lịch được — bấm khi sự kiện còn xa hơn. Nhắc chỉ dùng local notification, không cần server.

### Tin tức trống / thiếu nguồn
- Một số nguồn chặn theo region/User-Agent (thường là CoinDesk hoặc Fed) — app bỏ qua nguồn lỗi và vẫn
  hiện nguồn khác; bật/tắt nhóm nguồn trong *Cài đặt → Nguồn tin tức*.
- Thêm RSS riêng phải là `https://` và là RSS/Atom hợp lệ (XML). Trang HTML thường sẽ không parse được.
- Kéo để tải lại; tin đã có vẫn đọc được khi offline (cache 300 tin).

### `[1001] Chữ ký số không hợp lệ` (cả hai API)
Giờ thiết bị lệch > vài phút, private key dán thiếu/thừa, hoặc keyTrader khác key Partnership mà đang
bật "Dùng API key riêng" sai. Chỉnh giờ tự động và dán lại key.

### `REQUEST_RATE_LIMIT` / `[429]`
Gọi quá nhanh: đừng kéo liên tục nhiều màn hình; app đã cache 10 phút cho lịch và không gọi lại khi
đang tải. Đợi ~1 phút.

### Lỗi biên dịch `cannot find 'PulseStore' in scope` / scheme PulseHub thiếu
Chưa chạy `xcodegen generate` sau khi thêm target. Chạy lại rồi chọn scheme **PulseHub**.


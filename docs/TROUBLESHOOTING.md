# 🧯 Lỗi thường gặp

## Build / CI

### `Signing for "VietMap" requires a development team`
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
xcodebuild -list -project VietMap.xcodeproj
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

### Cài bằng ESign / Feather / Scarlet nhưng vẫn ra bản cũ

Triệu chứng: đã tải IPA mới, ESign báo cài xong, nhưng mở app vẫn là giao diện cũ
(ví dụ 1.0.0 (1), hoặc bản 3.1 chưa có biển báo kiểu mới).

Nguyên nhân theo thứ tự hay gặp:

1. **ESign dùng lại tệp đã tải trong bộ nhớ của nó.** Trong ESign vào
   *Tải xuống / Downloads*, xoá tệp IPA cũ (kể cả tệp trùng tên), rồi tải lại.
2. **Trình duyệt trả về bản cache.** Link cố định
   `releases/download/latest-ipa/VietMap-unsigned.ipa` bị ghi đè mỗi lần build và
   có thể bị cache. Hãy tải theo **link bất biến của từng phiên bản**:
   `https://github.com/TradingLeak/IOS/releases/download/v3.2.0-12/VietMap-3.2.0-12-unsigned.ipa`
   (mỗi phiên bản một thẻ release riêng, không bao giờ bị ghi đè).
   Nếu vẫn nghi cache: mở tab ẩn danh, hoặc thêm `?v=12` vào cuối link.
3. **App cũ chưa bị gỡ.** Bundle ID không đổi (`com.tradingleak.vietmap`), iOS có thể giữ
   bản cũ khi cài đè bằng chứng chỉ khác. Gỡ app cũ (nhấn giữ icon → Xoá), khởi động lại máy,
   rồi cài lại.
4. **Cách chắc chắn nhất: cài bản song song.** Trong cùng thẻ release có tệp
   `VietMap-3.2.0-12-alt-unsigned.ipa` — bundle ID riêng (`com.tradingleak.vietmap32`), tên
   hiển thị “Bản đồ VN 3.2”. Bản này **cài cạnh** app cũ (không ghi đè), nên chắc chắn là code
   mới. Cài xong thấy app mới trên màn hình chính là đúng; sau đó có thể xoá app cũ.

Kiểm tra đã đúng bản chưa:

- Mở **☰** (menu “…” góc phải) — dòng cuối menu ghi `VietMap 3.2.0 (12) · <commit>`.
- Hoặc **☰ → Cài đặt → Về ứng dụng**: *Phiên bản* và *Commit*.
- Đối chiếu SHA-256 của tệp đã tải với mô tả release:
  `shasum -a 256 VietMap-3.2.0-12-unsigned.ipa` (macOS/Linux).

## Cài xong nhưng app trắng màn hình / crash ngay
- **Kiểm tra đúng phiên bản trước tiên**: ☰ → **Cài đặt** → *Về ứng dụng* → dòng
  **Phiên bản**. Bản mới nhất của nhánh này là **3.1.1 (8)**.
  Release `latest-ipa` là **một** release dùng chung: nếu một nhánh khác (hoặc `main`)
  build sau, tệp `VietMap-unsigned.ipa` bị ghi đè bởi app của nhánh đó. Gặp bản lạ
  (ví dụ 1.0.0 (1)) thì tải lại tệp có tên phiên bản:
  `VietMap-3.1.1-8-unsigned.ipa` trong cùng release.
- Xem log: Xcode → Devices → *View Device Logs*.
- Kiểm tra `UIApplicationSceneManifest` / `@main` trong code.
- App dùng entitlement (push notification, HealthKit, Sign in with Apple, IAP) sẽ
  crash hoặc không hoạt động khi unsigned → cần tài khoản Developer trả phí.
- **Dữ liệu cảnh báo không hiện** (bản đồ trống, không có biển/camera): mở
  ☰ → **Cảnh báo**; nếu có dòng *“Không đọc được vn_alerts.json …”* thì bản build
  thiếu/hỏng tệp dữ liệu — tải lại IPA mới nhất.

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
rm -rf ~/Library/Developer/Xcode/DerivedData/VietMap-*
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

# Phần 2 — Lỗi riêng của app bản đồ (MapKit)

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

## Dẫn đường & bản đồ 3D

### Bản đồ không xoay theo hướng đi
- Thiết bị chưa báo hướng (`CLLocation.course` = -1), thường gặp khi đứng yên hoặc trong nhà.
- Đi thêm vài chục mét. Kiểm tra la bàn bằng app **La bàn** của iOS.
- Đang ở chế độ **2D**? Bấm nút `view.3d` bên phải hoặc bật trong **Cài đặt → Bản đồ**.

### Kéo bản đồ xong không bám lại
Đây là chủ ý (giống Apple Maps): kéo tay sẽ tạm dừng bám theo. Bấm nút **mũi tên**
(`location.north.fill`) hiện ở cột nút bên phải để về lại vị trí.

### Camera nhảy / giật
- GPS trong hầm, trong nhà hoặc giữa nhà cao tầng → sai số lớn. App đã bỏ qua điểm có
  `horizontalAccuracy > 80 m` và làm mượt hướng đi.
- Bật Wi-Fi (định vị phụ), hoặc chuyển 2D cho dễ nhìn.

### Không thấy giờ tới nơi
Chỉ hiện khi tuyến có thời lượng hợp lệ (Apple Maps trả về). Tuyến bị lỗi/hết quota VietMap
vẫn có ETA ước lượng; nếu không có, banner sẽ bỏ trống phần giờ.

### Tốn pin khi dẫn đường
GPS độ chính xác cao + màn hình sáng + dựng 3D đều tốn pin. Giảm bằng cách: dùng 2D, tắt
chế độ 2D khi không cần, khoá màn hình khi không nhìn (app không chạy nền liên tục).

## Dữ liệu & quyền riêng tư

### App có gửi dữ liệu đi đâu không?
Không. Không có máy chủ của app, không telemetry, không tài khoản.
- Dữ liệu cảnh báo nhúng sẵn trong app.
- OpenStreetMap chỉ tải khi bạn bấm "Tải từ OpenStreetMap".
- Ảnh camera TP.HCM tải trực tiếp từ cổng thông tin của thành phố.

### Nhập JSON cảnh báo bị báo lỗi
Xem [docs/ALERTS.md](ALERTS.md) mục 5 — mỗi cảnh báo cần `kind`, `lat`, `lng`; `speed_zone`
và `speed_sign` bắt buộc có `speedLimit`.

## CI / build

### "error: value of optional type 'String?' must be unwrapped"
Đã gặp với `MKRoute.Step.instructions`/`.notice`: các thuộc tính này là optional trong một
số phiên bản SDK. Code hiện tại gán qua `String?` để tương thích cả hai.

### Job `unit-tests` đỏ nhưng job `build` xanh
App vẫn có IPA dùng được; lỗi nằm ở test logic (cảnh báo/tuyến/format). Xem
*Annotations* của job để biết test nào fail.

### Muốn bỏ test cho nhanh
`Run workflow` → tắt `run_tests`, hoặc push với commit chỉ sửa docs (workflow vẫn chạy
nhưng bạn có thể cancel job test).

---

## Phần 3 — Lỗi riêng của cảnh báo tốc độ / camera / xe máy

### Không thấy giới hạn tốc độ (thanh tốc độ hiện "chưa xác định")

- Đây là hành vi đúng khi: đường chưa có biển/vùng trong dữ liệu **và** tên đường trong chỉ
  dẫn không nhận diện được loại đường (xem `SpeedLimitRules.classify`).
- Cách xử lý: nhập JSON vùng tốc độ cho địa phương bạn (`docs/ALERTS.md` mục 5–6), hoặc tải
  thêm từ OpenStreetMap khi đang có tuyến.
- Kiểm tra nhanh dữ liệu: `python3 scripts/build-alert-data.py --check`.

### Bấm "Tải biển tốc độ từ OpenStreetMap" bị lỗi/timeout

- Overpass API là dịch vụ công cộng, hay quá tải. App chỉ tải quanh tuyến trong hộp
  0,6° × 0,6° (~65 km) và timeout 30 giây.
- Đứng ở Việt Nam tải có thể chậm hơn; thử lại sau vài phút hoặc dùng VPN.
- Lỗi `HTTP 429` = bị giới hạn tần suất, chờ 5–10 phút.

### Tuyến xe máy vẫn đi vào cao tốc

- Chưa nhập API key VietMap → app đang ước lượng từ Apple Maps. Tên đường trong chỉ dẫn
  không chứa chữ "cao tốc" thì không lọc được.
- Nhập key VietMap trong Cài đặt → **Dẫn đường xe máy** để dùng hồ sơ `vehicle=motorcycle`
  thật. Nếu VietMap trả lỗi, app tự quay về Apple Maps và ghi chú lý do trên thẻ tuyến.

### VietMap trả về `HTTP 401/403`

- Key sai/hết hạn hoặc chưa bật dịch vụ Route v4 trong console VietMap.
- Kiểm tra key trong Cài đặt (nút con mắt để xem lại), rồi thử trên
  <https://tools.vietmap.vn/playground/route>.

### Giọng đọc cảnh báo không kêu

- iOS → Cài đặt → **Âm thanh & Cảm ứng** → kiểm tra âm lượng; tắt chế độ im lặng thì
  AVSpeechSynthesizer vẫn đọc (audio session `.ambient`).
- Trong app: Cài đặt → **Cảnh báo trên bản đồ** → *Đọc cảnh báo bằng giọng tiếng Việt*.
- Nếu đang mở nhạc, app dùng `.duckOthers` nên nhạc sẽ nhỏ lại khi đọc cảnh báo.

## 🤖 Trợ lý AI (2.2)

### Bấm nút `sparkles` mà AI không trả lời

- Kiểm tra **Cài đặt → Trợ lý AI → Kiểm tra kết nối**; thông báo lỗi hiện ngay dưới nút.
- `HTTP 401/403` → key sai hoặc đã hết hạn. Dán lại key, chú ý không dính dấu cách.
- `HTTP 404` → base URL thiếu `/v1` (ví dụ `https://api.xah.io` thay vì `https://api.xah.io/v1`).
- `HTTP 429` → hết hạn mức miễn phí, chờ vài phút hoặc đổi nhà cung cấp.
- Không có mạng → app tự dùng bộ phân tích tiếng Việt trên máy; câu trả lời sẽ ghi rõ
  *“Đang dùng bộ phân tích trên máy”*.

### AI trả lời nhưng không ra tuyến

- Câu cần có **điểm đến** rõ ràng: “đi xe máy từ Cầu Giấy **đến Hồ Hoàn Kiếm**”.
- Tên quá chung (“quán cà phê”) → ghi thêm quận/thành phố.
- Xem bong bóng chat: nếu AI hỏi lại, trả lời ngay trong ô nhập.

### Dùng Ollama / LM Studio trong LAN không kết nối được

- Base URL phải là `http://<IP-máy-tính>:11434/v1` (Ollama) hoặc `:1234/v1` (LM Studio)
  và **cùng Wi-Fi** với iPhone.
- Lần đầu iOS sẽ hỏi quyền **Mạng nội bộ** → bấm *Cho phép*. Nếu đã lỡ từ chối:
  iOS → Cài đặt → **Bản đồ Việt Nam** → bật *Mạng nội bộ*.
- Kiểm tra trên máy tính: `curl http://<IP>:11434/v1/models`.

### Tốn pin / nóng máy khi bật AI

- AI chỉ gọi khi bạn gửi câu lệnh hoặc khi có ≥ 2 phương án tuyến cần chọn.
- Tắt **Cho AI can thiệp sâu** nếu chỉ muốn AI đọc câu lệnh.
- Không có nhu cầu AI: tắt **Bật trợ lý AI** — mọi tính năng khác vẫn chạy offline.

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

## Phần 3 — Lỗi riêng của cảnh báo tốc độ / camera / xe máy

### Không thấy giới hạn tốc độ (HUD hiện "chưa rõ biển báo")

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
- Trong app: HUD có nút **Giọng nói / Im lặng**; Cài đặt → Cảnh báo & HUD có toggle riêng.
- Nếu đang mở nhạc, app dùng `.duckOthers` nên nhạc sẽ nhỏ lại khi đọc cảnh báo.

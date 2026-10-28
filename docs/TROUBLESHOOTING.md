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

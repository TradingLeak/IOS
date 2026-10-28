# 🛠 Cơ chế build & tuỳ biến

## 1. Vì sao không cần tài khoản Apple vẫn build được?

`xcodebuild` chỉ **ký** app khi bạn yêu cầu. Với các cờ:

```bash
CODE_SIGNING_ALLOWED=NO
CODE_SIGNING_REQUIRED=NO
CODE_SIGN_IDENTITY=""
DEVELOPMENT_TEAM=""
PROVISIONING_PROFILE_SPECIFIER=""
```

thì Xcode biên dịch, liên kết và đóng gói `.app` mà **không** hỏi Apple ID, không cần
team, không cần provisioning profile. Kết quả là file `.app`/`.ipa` chạy được trên
máy ảo (Simulator) và **có thể cài lên máy thật nếu được ký lại sau đó**.

Điều duy nhất bạn mất so với bản có ký:

- Không có `_CodeSignature/`, không có `embedded.mobileprovision`.
- iOS từ chối chạy trực tiếp → cần TrollStore, sideload tool, hoặc jailbreak.

Các cờ trên đã được đặt ở 2 nơi để bạn không phải nhớ:

- `project.yml` → `settings.base` (áp dụng cả khi mở Xcode bằng GUI).
- `scripts/make-ipa.sh` → truyền thẳng vào `xcodebuild archive`.

## 1b. Hai giai đoạn: build (macOS) và đóng gói (mọi hệ điều hành)

| Giai đoạn | Script | Cần gì |
|---|---|---|
| Build `.app` không ký | `scripts/make-ipa.sh` | macOS + Xcode |
| Đóng gói `.app` → `.ipa` | `scripts/pack-ipa.sh` | chỉ cần `zip` + `python3`/PlistBuddy |

Nhờ tách như vậy, bạn có thể:

- Đóng gói một `.app` có sẵn (do người khác build, tải từ CI, hoặc giải nén từ
  `.xcarchive`) ngay trên Linux:

  ```bash
  ./scripts/pack-ipa.sh /đường/dẫn/Payload/MyApp.app --output dist
  ```

- Sửa nhanh metadata mà không build lại:

  ```bash
  ./scripts/pack-ipa.sh MyApp.app --bundle-id com.moi.app --display-name "Tên mới"
  ```
- Test logic đóng gói bằng `./scripts/test-pack.sh` — không cần Mac, chạy được trong CI.

## 2. XcodeGen: `project.yml` là nguồn sự thật

File `.xcodeproj` là JSON-ish PBXProj rất dễ conflict khi làm việc nhóm, nên repo
**không commit** nó (xem `.gitignore`). Thay vào đó `project.yml` mô tả target, và
`xcodegen generate` sinh ra project.

```bash
brew install xcodegen
xcodegen generate      # tạo HelloIPA.xcodeproj
```

Thêm file mới: chỉ cần tạo trong `App/Sources/` rồi chạy `xcodegen generate` lại —
XcodeGen quét cả thư mục nên không phải thêm thủ công.

Nếu bạn **muốn** commit `.xcodeproj` (ví dụ đồng nghiệp không cài xcodegen), hãy xoá
dòng `*.xcodeproj/` trong `.gitignore` và commit thư mục đó.

## 3. Đổi tên app, bundle ID, phiên bản

Ba cách, chọn một:

**a) Trong `project.yml`** (khuyến nghị, áp dụng cho mọi lần build)

```yaml
targets:
  HelloIPA:
    settings:
      base:
        PRODUCT_NAME: MyApp
        PRODUCT_BUNDLE_IDENTIFIER: com.congty.myapp
```

Tên hiển thị trên màn hình chính nằm ở `App/Info.plist` → `CFBundleDisplayName`.
Phiên bản nằm ở `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.

**b) Qua dòng lệnh** — ghi đè sau khi build, tiện cho CI:

```bash
./scripts/make-ipa.sh --bundle-id com.congty.myapp --display-name "My App" \
                      --short-version 1.2.0 --build-number 87
```

**c) Trong GitHub Actions** — `Run workflow` có sẵn ô nhập *scheme*, *bundle_id*,
*display_name*, hoặc set biến môi trường `BUNDLE_ID` trong workflow.

> Lưu ý: bundle ID khác nhau = app khác nhau trên máy. Nếu bạn cài đè lên bản cũ,
> giữ nguyên bundle ID.

## 4. Icon & splash

- Icon: `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
  — **bắt buộc 1024×1024, không alpha, không góc bo** (iOS tự bo). Thiếu icon thì
  archive sẽ fail hoặc bị App Store/TestFlight từ chối.
- Màu nhấn: `AccentColor.colorset`.
- Màn hình chờ: `UILaunchScreen` trong `App/Info.plist` dùng
  `LaunchBackground.colorset`.

Thay icon bằng ảnh của bạn:

```bash
convert my-icon.png -resize 1024x1024^ -gravity center -extent 1024x1024 \
        -background white -alpha remove -alpha off \
        App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

## 5. Quyền truy cập (camera, ảnh, vị trí, thông báo…)

Thêm key tương ứng trong `App/Info.plist`:

| Tính năng | Key bắt buộc |
|---|---|
| Camera | `NSCameraUsageDescription` |
| Thư viện ảnh (đọc) | `NSPhotoLibraryUsageDescription` |
| Lưu ảnh | `NSPhotoLibraryAddUsageDescription` |
| Vị trí | `NSLocationWhenInUseUsageDescription` |
| Micro | `NSMicrophoneUsageDescription` |
| Bluetooth | `NSBluetoothAlwaysUsageDescription` |
| Local network | `NSLocalNetworkUsageDescription` |

Thông báo đẩy / Sign in with Apple / HealthKit / IAP cần **entitlements + chữ ký**,
nên chúng **không hoạt động** với IPA unsigned — cần Apple Developer Program.

## 6. Thêm Swift Package

```yaml
targets:
  HelloIPA:
    packages:
      Alamofire:
        url: https://github.com/Alamofire/Alamofire
        from: 5.9.0
    dependencies:
      - package: Alamofire
```

Sau đó `xcodegen generate` lại. Lần build đầu sẽ resolve package (cần mạng).

## 7. Thêm CocoaPods

```bash
# thêm Podfile như bình thường, rồi:
pod install
./scripts/make-ipa.sh -p HelloIPA.xcworkspace -s HelloIPA
```

Trong CI, thêm bước `pod install` trước bước build và đổi scheme/`-p` tương ứng.
Nhớ bỏ `*.xcworkspace/` khỏi `.gitignore` nếu muốn commit workspace (không khuyến khích —
hãy để CI chạy `pod install`).

## 8. Ký app sau khi có IPA (tuỳ chọn, cần Mac + Apple ID)

```bash
# cách chuẩn của Apple (dùng chứng chỉ + profile đã có trong máy)
codesign -f -s "Apple Development: ban@email.com (XXXXXXXXXX)" \
         --entitlements App/entitlements.plist Payload/HelloIPA.app
```

Hoặc dùng các app có GUI: Sideloadly, ESign, Feather, AltStore — chúng nhận file
`.ipa` unsigned và ký lại bằng Apple ID.

## 9. Build trên CI khác

- **Self-hosted Mac runner**: giữ nguyên workflow, đổi `runs-on: self-hosted`, bỏ
  bước `setup-xcode`.
- **Bitrise/Codemagic**: chạy `scripts/make-ipa.sh` là đủ — script không phụ thuộc
  dịch vụ CI nào.
- **Máy Windows/Linux**: không build iOS native được. Cách hợp lý nhất là CI
  (workflow này), hoặc dùng Flutter/React Native cloud build — vẫn cần runner macOS
  phía sau.

## 10. Chạy thử app mà không cần ký

Bạn không cần iPhone để xem app: build cho Simulator.

```bash
xcodebuild -project HelloIPA.xcodeproj -scheme HelloIPA \
           -sdk iphonesimulator -configuration Debug build
open HelloIPA.xcodeproj    # rồi Cmd+R, chọn Simulator
```

Simulator không kiểm tra chữ ký, nên đây là cách nhanh nhất để phát triển UI.

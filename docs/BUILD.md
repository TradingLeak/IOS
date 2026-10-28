# 🛠 Build & tuỳ biến

## 1. Vì sao không cần tài khoản Apple vẫn build được?

`xcodebuild` chỉ **ký** app khi bạn yêu cầu. Với các cờ:

```bash
CODE_SIGNING_ALLOWED=NO
CODE_SIGNING_REQUIRED=NO
CODE_SIGN_IDENTITY=""
DEVELOPMENT_TEAM=""
PROVISIONING_PROFILE_SPECIFIER=""
```

Xcode biên dịch, liên kết và đóng gói `.app` mà **không** hỏi Apple ID, không cần team,
không cần provisioning profile. Kết quả là `.ipa` chạy được trên Simulator và
**cài được lên máy thật nếu được ký lại** (TrollStore / Sideloadly / SideStore).

Các cờ trên đã đặt ở 2 nơi: `project.yml` (áp dụng cả khi mở Xcode GUI) và
`scripts/make-ipa.sh` (truyền thẳng vào `xcodebuild archive`).

## 2. Hai giai đoạn: build (macOS) và đóng gói (mọi hệ điều hành)

| Giai đoạn | Script | Cần gì |
|---|---|---|
| Build `.app` không ký | `scripts/make-ipa.sh` | macOS + Xcode |
| Đóng gói `.app` → `.ipa` | `scripts/pack-ipa.sh` | chỉ cần `zip` + `python3`/PlistBuddy |

Nhờ tách như vậy, bạn có thể đóng gói một `.app` có sẵn ngay trên Linux:

```bash
./scripts/pack-ipa.sh /đường/dẫn/Payload/VietMap.app --output dist
```

## 3. XcodeGen: `project.yml` là nguồn sự thật

`.xcodeproj` không được commit (dễ conflict). `project.yml` mô tả target, và:

```bash
brew install xcodegen
xcodegen generate      # tạo VietMap.xcodeproj
```

Hai target:

| Target | Loại | Ghi chú |
|---|---|---|
| `VietMap` | application | app chính, `PRODUCT_BUNDLE_IDENTIFIER = com.tradingleak.vietmap` |
| `VietMapTests` | bundle.unit-test | test với `TEST_HOST` trỏ vào app |

Thêm file Swift mới vào `App/Sources/` rồi chạy lại `xcodegen generate` là xong.
Bài test đặt trong `App/Tests/`.

## 4. Đổi tên app / bundle ID / phiên bản

**a) Trong `project.yml`** (áp dụng mọi lần build)

```yaml
settings:
  base:
    PRODUCT_NAME: VietMap
    PRODUCT_BUNDLE_IDENTIFIER: com.congty.myapp
```

Tên hiển thị: `App/Info.plist` → `CFBundleDisplayName`. Phiên bản: `MARKETING_VERSION`,
`CURRENT_PROJECT_VERSION`.

**b) Qua dòng lệnh**

```bash
./scripts/make-ipa.sh --bundle-id com.congty.myapp --display-name "Bản đồ của tôi" \
                      --short-version 1.2.0 --build-number 87
```

**c) Trong GitHub Actions** — `Run workflow` có ô nhập `scheme`, `bundle_id`, `display_name`.

## 5. Tuỳ biến bản build

Không còn cấu hình AI: mọi phần nhận xét/đề xuất tuyến chạy offline trên máy. Bản build
chỉ khác nhau ở scheme, bundle ID, tên hiển thị và phiên bản.

```bash
./scripts/make-ipa.sh -b com.congty.myapp -n "Bản đồ của tôi" \
                      --short-version 2.2.0 --build-number 4
```

Trong CI: `Run workflow` → `scheme`, `bundle_id`, `display_name`, `run_tests`.

## 6. Icon & splash

- Icon: `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` — **1024×1024,
  không alpha, không góc bo** (iOS tự bo). Thiếu icon → archive fail.
- Màu nhấn: `AccentColor.colorset`; nền launch: `LaunchBackground.colorset`.

```bash
convert my-icon.png -resize 1024x1024^ -gravity center -extent 1024x1024 \
        -background white -alpha remove -alpha off \
        App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

## 7. Quyền truy cập

App đã khai báo `NSLocationWhenInUseUsageDescription` (bắt buộc cho bản đồ). Nếu thêm
tính năng khác, thêm key tương ứng trong `App/Info.plist`:

| Tính năng | Key |
|---|---|
| Camera | `NSCameraUsageDescription` |
| Thư viện ảnh | `NSPhotoLibraryUsageDescription` |
| Micro | `NSMicrophoneUsageDescription` |
| Thông báo đẩy | Cần entitlements → **không dùng được** với IPA unsigned |

## 8. Thêm Swift Package

```yaml
targets:
  VietMap:
    packages:
      Alamofire:
        url: https://github.com/Alamofire/Alamofire
        from: 5.9.0
    dependencies:
      - package: Alamofire
```

Build đầu tiên sẽ resolve package (cần mạng). CI đã bật `-skipPackagePluginValidation`.

## 9. Chạy test

```bash
# trên Mac
xcodebuild test -project VietMap.xcodeproj -scheme VietMap \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# không cần Mac
./scripts/selfcheck.sh    # kiểm tra shell/plist/icon/cân bằng ngoặc Swift
./scripts/test-pack.sh    # đóng gói IPA giả + verify
```

CI chạy test trên Simulator ở job `unit-tests` (bỏ qua khi chọn `run_tests: false`).

Bộ test hiện có:

| File | Nội dung |
|---|---|
| `ModelTests` | định dạng km/phút/giờ tới nơi, model tuyến, lưu lịch sử/yêu thích |
| `AlertTests` | giải mã dữ liệu cảnh báo, chỉ mục lưới, `D_warn`, TT 38/2024, chấm điểm tuyến |
| `RoutingTests` | hồ sơ xe máy, lọc tuyến cao tốc, giải mã polyline VietMap Route v4 |

## 10. Dữ liệu cảnh báo (camera / biển tốc độ)

Dữ liệu nhúng nằm ở `App/Resources/Data/vn_alerts.json` (sinh tự động, **commit vào repo**):

```bash
python3 scripts/build-alert-data.py           # gộp data/sources + data/curated
python3 scripts/build-alert-data.py --check   # chỉ kiểm tra (CI + selfcheck dùng lệnh này)
```

`project.yml` đã khai báo `App/Resources` là nguồn, nên tệp JSON tự vào app bundle — không
cần sửa gì thêm. Nếu thêm thư mục dữ liệu mới, giữ nó trong `App/Resources/` để XcodeGen
đóng gói.

Chi tiết schema, nguồn và giấy phép: [ALERTS.md](ALERTS.md).

## 11. Deploy lên máy thật

Simulator không cần ký, nên phát triển UI nhanh nhất là chạy Simulator. Với máy thật:

```bash
xcodebuild -project VietMap.xcodeproj -scheme VietMap \
  -destination 'generic/platform=iOS' build
```

rồi cài qua Xcode (cần Apple ID miễn phí trong Xcode → Settings → Accounts), hoặc dùng
IPA + Sideloadly như hướng dẫn trong [INSTALL.md](INSTALL.md).

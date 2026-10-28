# 📦 iOS → IPA không cần tài khoản Apple

[![Build unsigned IPA](https://github.com/TradingLeak/IOS/actions/workflows/build-unsigned-ipa.yml/badge.svg)](https://github.com/TradingLeak/IOS/actions/workflows/build-unsigned-ipa.yml)

Template dựng sẵn để **build file `.ipa` mà không cần Apple Developer Program (99$/năm)**,
thậm chí **không cần Apple ID** — bằng cách tạo **IPA unsigned** (không ký) trên
**GitHub Actions** (không cần máy Mac) hoặc trên **Mac local**.

Repo có sẵn một app SwiftUI mẫu (`HelloIPA`) hiển thị thông tin build, kèm script
đóng gói IPA, workflow CI và hướng dẫn cài lên iPhone.

```
App/ (SwiftUI) ──xcodebuild archive──▶ Payload/HelloIPA.app ──zip──▶ HelloIPA-1.0.0-1-unsigned.ipa
  project.yml      CODE_SIGNING_ALLOWED=NO                          dist/ + <file>.sha256
```

---

## ⚡ Tải IPA ngay (không cần Mac, không cần đăng nhập)

**Link tải cố định — luôn là bản build mới nhất:**

```
https://github.com/TradingLeak/IOS/releases/download/latest-ipa/HelloIPA-unsigned.ipa
```

Mở trang **[Releases](https://github.com/TradingLeak/IOS/releases/tag/latest-ipa)** để tải
bằng trình duyệt (kèm file `.sha256`). Mỗi lần code thay đổi, GitHub Actions build lại và
cập nhật đúng link này — bạn không phải làm gì cả.

Muốn build theo ý mình (đổi bundle ID, tên app, số build):

1. Vào tab **Actions** → workflow **Build unsigned IPA** → **Run workflow**.
2. Điền `bundle_id`, `display_name` nếu cần → **Run**.
3. ~5–10 phút sau, tải ở **Artifacts** (`unsigned-ipa-<số>`) hoặc ở **Releases**.

Workflow tự chạy khi push lên bất kỳ branch nào và khi có pull request.
Push tag `v1.0.0` sẽ tạo thêm Release riêng cho phiên bản đó.

> ✅ Repo này đang **public** → Actions không tốn phí, không giới hạn số phút.

### Cài file IPA lên iPhone

IPA này **chưa ký** (unsigned) nên cần một bước ký khi cài — xem
**[docs/INSTALL.md](docs/INSTALL.md)**. Tóm tắt:

| iOS của bạn | Cách cài |
|---|---|
| 14.0 → 16.6.1, 16.7 RC, 17.0 | **TrollStore** — cài vĩnh viễn, không cần Apple ID |
| 17.0.1 trở lên | **Sideloadly / SideStore** — Apple ID miễn phí, chứng chỉ 7 ngày |

## 💻 Build trên máy Mac (không cần đăng nhập Apple ID)

```bash
brew install xcodegen           # chỉ cần 1 lần
./scripts/setup-macos.sh        # kiểm tra Xcode + sinh HelloIPA.xcodeproj
./scripts/make-ipa.sh           # → dist/HelloIPA-1.0.0-1-unsigned.ipa
```

Hoặc dùng `make`:

```bash
make setup     # kiểm tra môi trường
make ipa       # build IPA
make open      # mở Xcode (không cần Apple ID để build simulator/archive)
make test      # test khâu đóng gói IPA (không cần Xcode)
```

Tuỳ chọn hữu ích của `make-ipa.sh`:

```bash
./scripts/make-ipa.sh --bundle-id com.congty.myapp --build-number 42
./scripts/make-ipa.sh -p MyApp.xcworkspace -s MyApp -o ~/Desktop
./scripts/make-ipa.sh --verbose      # in full log xcodebuild
```

---

## 🧪 Kiểm thử

Toàn bộ khâu đóng gói được test tự động, **không cần Mac**:

```bash
./scripts/selfcheck.sh    # shell, Info.plist, icon 1024x1024 không alpha, YAML, tài liệu
./scripts/test-pack.sh    # tạo app bundle giả → đóng gói → kiểm tra lại IPA bằng python3
```

CI cũng chạy hai bước này ở job `lint` trên `ubuntu-latest` trước khi build.

## 📁 Cấu trúc repo

| Đường dẫn | Mô tả |
|---|---|
| `project.yml` | Định nghĩa project cho [XcodeGen](https://github.com/yonaskolb/XcodeGen) — **nguồn sự thật duy nhất**, không commit `.xcodeproj` để tránh conflict |
| `App/Info.plist` | Info.plist (có `CFBundleDisplayName`, ngày build, git commit) |
| `App/Sources/` | Code SwiftUI mẫu: `HelloIPAApp.swift`, `ContentView.swift`, `BuildInfo.swift` |
| `App/Resources/Assets.xcassets` | AppIcon 1024×1024 (bắt buộc để archive thành công), AccentColor, LaunchBackground |
| `scripts/make-ipa.sh` | Script chính (macOS): `xcodebuild archive` không ký → gọi `pack-ipa.sh` |
| `scripts/pack-ipa.sh` | Đóng gói `.app` → `.ipa` (chạy được cả trên **Linux**, không cần Xcode) |
| `scripts/test-pack.sh` | Test tự động khâu đóng gói bằng một app bundle giả — chạy trong CI |
| `scripts/setup-macos.sh` | Cài đặt môi trường macOS (Xcode, xcodegen) |
| `scripts/selfcheck.sh` | Kiểm tra repo không cần macOS (shell, plist, icon, YAML) — chạy ở job `lint` trên CI |
| `Makefile` | Lệnh tắt: `make setup`, `make ipa`, `make test`, `make lint` |
| `.github/workflows/build-unsigned-ipa.yml` | CI build IPA trên `macos-15`: artifact + Release `latest-ipa` (link tải cố định) + Release theo tag `v*` |
| `docs/BUILD.md` | Giải thích cơ chế, đổi bundle ID / tên app / icon, thêm Swift Package |
| `docs/INSTALL.md` | Cài IPA lên iPhone: TrollStore, Sideloadly, AltStore, SideStore, ESign… |
| `docs/TROUBLESHOOTING.md` | Lỗi thường gặp và cách sửa |

---

## 🔑 Điều quan trọng cần hiểu

**Build** IPA không cần tài khoản Apple — điều này đúng và hợp pháp, hoàn toàn dùng
toolchain miễn phí của Apple.

**Cài** lên iPhone thì khác: iOS chỉ chạy app có chữ ký hợp lệ. Vì vậy IPA unsigned
cần được **ký lại** ở một trong các dạng:

| Cách | Cần Apple ID? | Cần trả phí? | Ghi chú |
|---|---|---|---|
| **TrollStore** | ❌ Không | Không | Chỉ iOS 14.0 beta 2 → 16.6.1, 16.7 RC, **17.0**. Cài vĩnh viễn |
| **Sideloadly / AltStore / SideStore / ESign** | ✅ Apple ID **miễn phí** | Không | Chứng chỉ 7 ngày, tối đa 3 app, phải refresh định kỳ |
| **Apple Developer Program** | ✅ | 99$/năm | Chứng chỉ 1 năm, TestFlight, App Store |
| **Jailbreak + AppSync Unified** | ❌ | Không | Chạy app không ký trực tiếp |

→ Chi tiết từng bước trong [docs/INSTALL.md](docs/INSTALL.md).

Nói ngắn: **repo này lo phần build (0 đồng, 0 tài khoản)**. Phần ký để cài lên máy
bạn dùng Apple ID miễn phí (nếu iOS ≥ 17.0.1) hoặc TrollStore (nếu iOS đủ cũ).

---

## 🧩 Dùng cho app của bạn

1. Thay `App/Sources/*.swift` bằng code app của bạn (giữ `@main` App entry).
2. Sửa `project.yml`: `PRODUCT_BUNDLE_IDENTIFIER`, `bundleIdPrefix`, tên target.
3. Nếu app cần quyền: thêm key vào `App/Info.plist` (Camera, Photo, Location…).
4. Nếu app có CocoaPods: chạy `pod install` rồi build bằng `-p App.xcworkspace`
   và thêm bước `pod install` vào workflow. Nếu dùng SPM: khai báo trong `project.yml`.
5. Build lại: `make ipa` hoặc chạy workflow trên GitHub.

Xem [docs/BUILD.md](docs/BUILD.md) để biết chi tiết từng mục.

## 🧾 Ghi chú pháp lý

- Không có phần mềm Apple bị chỉnh sửa hay vá lậu nào trong repo này; chỉ dùng
  `xcodebuild` chính thức với cờ tắt ký.
- App cài bằng chứng chỉ miễn phí **chỉ dùng cho máy của bạn / mục đích thử nghiệm**.
  Phân phối cho người khác cần Apple Developer Program hoặc hình thức phù hợp.
- TrollStore dựa trên lỗ hổng CoreTrust đã bị Apple vá từ iOS 17.0.1; đừng tin các
  video "TrollStore cho iOS 18/26".

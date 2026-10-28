#!/usr/bin/env bash
#
# setup-macos.sh — Chuẩn bị máy Mac để build IPA không cần Apple ID.
#
#   ./scripts/setup-macos.sh
#
set -Eeuo pipefail
[[ "$(uname -s)" == "Darwin" ]] || { echo "Chỉ chạy trên macOS." >&2; exit 1; }

bold() { printf '\033[1m%s\033[0m\n' "$*"; }

bold "1/4 · Kiểm tra Xcode"
if ! xcode-select -p 2>/dev/null | grep -q 'Xcode.app'; then
  echo "  ! Chưa chọn Xcode full. Đang thử chọn /Applications/Xcode.app ..." >&2
  if [[ -d /Applications/Xcode.app ]]; then
    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  else
    echo "  ✖ Chưa cài Xcode. Tải trên App Store (miễn phí, ~10GB) rồi chạy lại script." >&2
    exit 1
  fi
fi
xcodebuild -version | sed 's/^/  /'
xcrun --sdk iphoneos --show-sdk-version | sed 's/^/  iOS SDK: /'
sudo xcodebuild -license accept >/dev/null 2>&1 || true
xcodebuild -runFirstLaunch >/dev/null 2>&1 || true
echo "  ✔ Xcode OK"

bold "2/4 · Kiểm tra Homebrew"
if ! command -v brew >/dev/null; then
  echo "  ! Chưa có Homebrew. Cài bằng lệnh sau rồi chạy lại:"
  echo '    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  exit 1
fi
echo "  ✔ $(brew --version | head -n1)"

bold "3/4 · Cài xcodegen"
if command -v xcodegen >/dev/null; then
  echo "  ✔ Đã có $(xcodegen --version)"
else
  brew install xcodegen
fi

bold "4/4 · Sinh project Xcode"
cd "$(dirname "${BASH_SOURCE[0]}")/.."
xcodegen generate
echo
echo "Xong. Build IPA bằng:  ./scripts/make-ipa.sh"
echo "Hoặc mở Xcode (không cần đăng nhập Apple ID):  open VietMap.xcodeproj"

#!/usr/bin/env bash
#
# make-ipa.sh — Build một file .ipa KHÔNG CẦN TÀI KHOẢN APPLE DEVELOPER
#                (unsigned IPA) từ một project Xcode.
#
# Yêu cầu: macOS + Xcode (full, không chỉ Command Line Tools).
#
#   ./scripts/make-ipa.sh                              # tự dò project trong repo
#   ./scripts/make-ipa.sh --bundle-id com.abc.app      # đổi bundle id
#   ./scripts/make-ipa.sh -p MyApp.xcworkspace -s MyApp
#
# Kết quả: dist/<Scheme>-<version>-unsigned.ipa (+ file .sha256)
#
set -Eeuo pipefail

# ---------------------------------------------------------------- style
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
  BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; RESET=''
fi

step()  { printf '\n%s==> %s%s\n' "$BOLD$BLUE" "$*" "$RESET"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s✔%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()  { printf '    %s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()   { printf '\n%s✖ %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

trap 'die "Build thất bại ở dòng $LINENO (lệnh: $BASH_COMMAND)"' ERR

# ---------------------------------------------------------------- defaults
SCHEME="VietMap"
PROJECT=""
CONFIGURATION="Release"
OUTPUT_DIR="dist"
BUNDLE_ID=""
DISPLAY_NAME=""
SHORT_VERSION=""
BUILD_NUMBER=""
KEEP_ARCHIVE=0
VERBOSE=0

usage() {
  cat <<EOF
${BOLD}make-ipa.sh${RESET} — build IPA không cần tài khoản Apple (unsigned)

${BOLD}Cách dùng${RESET}
  ./scripts/make-ipa.sh [tuỳ chọn]

${BOLD}Tuỳ chọn${RESET}
  -s, --scheme NAME         Scheme cần build (mặc định: VietMap)
  -p, --project PATH        .xcodeproj hoặc .xcworkspace (mặc định: tự dò)
  -c, --configuration NAME  Debug|Release (mặc định: Release)
  -o, --output DIR          Thư mục chứa IPA (mặc định: dist)
  -b, --bundle-id ID        Ghi đè CFBundleIdentifier sau khi build
  -n, --display-name NAME   Ghi đè tên hiển thị trên màn hình chính
      --short-version V     Ghi đè CFBundleShortVersionString
      --build-number N      Ghi đè CFBundleVersion
  -k, --keep-archive        Giữ lại file .xcarchive
  -v, --verbose             In đầy đủ log của xcodebuild
  -h, --help                Hiện trợ giúp

${BOLD}Ví dụ${RESET}
  ./scripts/make-ipa.sh
  AI_BASE_URL=https://api.xah.io/v1 AI_MODEL=gpt-4o-mini ./scripts/make-ipa.sh
  ./scripts/make-ipa.sh -b com.tradingleak.demo --build-number 42
  ./scripts/make-ipa.sh -p MyApp.xcworkspace -s MyApp -o ~/Desktop

${BOLD}Ghi chú${RESET}
  • IPA tạo ra KHÔNG có chữ ký (unsigned). Cách cài đặt: xem docs/INSTALL.md
  • Build lại project từ project.yml: xcodegen generate
EOF
}

# ---------------------------------------------------------------- args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--scheme)         SCHEME="${2:?}"; shift 2 ;;
    -p|--project)        PROJECT="${2:?}"; shift 2 ;;
    -c|--configuration)  CONFIGURATION="${2:?}"; shift 2 ;;
    -o|--output)         OUTPUT_DIR="${2:?}"; shift 2 ;;
    -b|--bundle-id)      BUNDLE_ID="${2:?}"; shift 2 ;;
    -n|--display-name)   DISPLAY_NAME="${2:?}"; shift 2 ;;
    --short-version)     SHORT_VERSION="${2:?}"; shift 2 ;;
    --build-number)      BUILD_NUMBER="${2:?}"; shift 2 ;;
    -k|--keep-archive)   KEEP_ARCHIVE=1; shift ;;
    -v|--verbose)        VERBOSE=1; shift ;;
    -h|--help)           usage; exit 0 ;;
    *) die "Tham số không hợp lệ: $1 (dùng --help để xem trợ giúp)" ;;
  esac
done

# ---------------------------------------------------------------- kiểm tra môi trường
step "Kiểm tra môi trường"
[[ "$(uname -s)" == "Darwin" ]] || die "Script này cần chạy trên macOS (hoặc runner macOS của GitHub Actions).
Trên Linux/Windows hãy dùng GitHub Actions: .github/workflows/build-unsigned-ipa.yml"
command -v xcodebuild >/dev/null || die "Không tìm thấy xcodebuild. Cài Xcode từ App Store rồi chạy: sudo xcode-select -s /Applications/Xcode.app"
command -v xcrun      >/dev/null || die "Không tìm thấy xcrun. Hãy cài Xcode full."
xcodebuild -version | sed 's/^/    /'
ok "Xcode sẵn sàng"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Tự sinh project nếu chỉ có project.yml và máy có xcodegen
if [[ -z "$PROJECT" && ! -e "VietMap.xcodeproj" && -f "project.yml" ]]; then
  if command -v xcodegen >/dev/null; then
    step "Sinh project từ project.yml (xcodegen)"
    xcodegen generate --quiet
    ok "Đã tạo VietMap.xcodeproj"
  fi
fi

# ---------------------------------------------------------------- dò project
if [[ -z "$PROJECT" ]]; then
  # Ưu tiên .xcworkspace (CocoaPods/SPM), sau đó tới .xcodeproj.
  # (Không dùng `mapfile` để tương thích bash 3.2 mặc định trên macOS.)
  CANDIDATES=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && CANDIDATES+=("$line")
  done < <(
    find . -maxdepth 3 \( -name '*.xcworkspace' -o -name '*.xcodeproj' \) \
      -not -path '*/.*' -not -path '*/Pods/*' -not -path '*/build/*' -print 2>/dev/null | sort
  )
  for c in "${CANDIDATES[@]:-}"; do
    [[ "$c" == *.xcworkspace ]] && { PROJECT="$c"; break; }
  done
  if [[ -z "$PROJECT" ]]; then
    for c in "${CANDIDATES[@]:-}"; do
      [[ "$c" == *.xcodeproj ]] && { PROJECT="$c"; break; }
    done
  fi
  [[ -n "$PROJECT" ]] || die "Không tìm thấy .xcodeproj/.xcworkspace. Truyền vào bằng: -p đường/dẫn/App.xcodeproj"
fi

[[ -e "$PROJECT" ]] || die "Không tồn tại: $PROJECT"
step "Cấu hình build"
info "Project        : $PROJECT"
info "Scheme         : $SCHEME"
info "Configuration  : $CONFIGURATION"
info "Code signing   : OFF (unsigned IPA)"

BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
DERIVED_DATA="$BUILD_DIR/DerivedData"
STAGE="$BUILD_DIR/ipa-stage"
rm -rf "$ARCHIVE_PATH" "$STAGE"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# ---------------------------------------------------------------- archive
step "Archive app (không ký)"
PROJECT_FLAG="-project"
[[ "$PROJECT" == *.xcworkspace ]] && PROJECT_FLAG="-workspace"

# Cờ toàn cục phải đứng TRƯỚC action `archive` trên dòng lệnh
XCODE_MAJOR="$(xcodebuild -version | awk 'NR==1{print $2}' | cut -d. -f1)"

# Các build setting đặt sau action
BUILD_SETTINGS=(
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=""
  CODE_SIGN_ENTITLEMENTS=""
  EXPANDED_CODE_SIGN_IDENTITY=""
  PROVISIONING_PROFILE_SPECIFIER=""
  DEVELOPMENT_TEAM=""
  ONLY_ACTIVE_ARCH=NO
  BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  "GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo local)"
)
[[ -n "$BUNDLE_ID"     ]] && BUILD_SETTINGS+=("PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID")
[[ -n "$SHORT_VERSION" ]] && BUILD_SETTINGS+=("MARKETING_VERSION=$SHORT_VERSION")
[[ -n "$BUILD_NUMBER"  ]] && BUILD_SETTINGS+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")

# Cấu hình AI (tuỳ chọn): nhúng vào Info.plist để app có sẵn khi cài.
# Ưu tiên người dùng nhập trong app; đừng commit API key vào repo.
AI_BASE_URL="${AI_BASE_URL:-}"
AI_MODEL="${AI_MODEL:-}"
AI_API_KEY="${AI_API_KEY:-}"
[[ -n "$AI_BASE_URL" ]] && BUILD_SETTINGS+=("AI_BASE_URL=$AI_BASE_URL")
[[ -n "$AI_MODEL"    ]] && BUILD_SETTINGS+=("AI_MODEL=$AI_MODEL")
[[ -n "$AI_API_KEY"  ]] && BUILD_SETTINGS+=("AI_API_KEY=$AI_API_KEY")

XCODEBUILD_ARGS=(
  "$PROJECT_FLAG" "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=iOS"
  -archivePath "$ARCHIVE_PATH"
  -derivedDataPath "$DERIVED_DATA"
)
if [[ "${XCODE_MAJOR:-0}" -ge 15 ]]; then
  XCODEBUILD_ARGS+=( -skipMacroValidation -skipPackagePluginValidation )
fi
XCODEBUILD_ARGS+=( archive )
XCODEBUILD_ARGS+=( "${BUILD_SETTINGS[@]}" )

LOG="$BUILD_DIR/xcodebuild.log"
mkdir -p "$BUILD_DIR"
set +e
if [[ "$VERBOSE" -eq 1 ]]; then
  xcodebuild "${XCODEBUILD_ARGS[@]}" 2>&1 | tee "$LOG"
  BUILD_RC="${PIPESTATUS[0]}"
else
  xcodebuild "${XCODEBUILD_ARGS[@]}" >"$LOG" 2>&1
  BUILD_RC=$?
fi
set -e
if [[ "$BUILD_RC" -ne 0 ]]; then
  echo
  warn "xcodebuild thất bại (exit $BUILD_RC). 40 dòng cuối của log:"
  tail -n 40 "$LOG" | sed 's/^/      /' >&2
  die "Xem toàn bộ log tại: $LOG"
fi
[[ -d "$ARCHIVE_PATH" ]] || die "Không tạo được archive tại $ARCHIVE_PATH"
ok "Archive xong: $ARCHIVE_PATH"

# ---------------------------------------------------------------- đóng gói IPA
APP_SRC="$(/usr/bin/find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' -type d 2>/dev/null | head -n 1)"
[[ -n "$APP_SRC" ]] || die "Không tìm thấy .app trong $ARCHIVE_PATH/Products/Applications"

PACK_ARGS=( "$APP_SRC" --output "$OUTPUT_DIR" )
[[ -n "$BUNDLE_ID"     ]] && PACK_ARGS+=( --bundle-id "$BUNDLE_ID" )
[[ -n "$DISPLAY_NAME"  ]] && PACK_ARGS+=( --display-name "$DISPLAY_NAME" )
[[ -n "$SHORT_VERSION" ]] && PACK_ARGS+=( --short-version "$SHORT_VERSION" )
[[ -n "$BUILD_NUMBER"  ]] && PACK_ARGS+=( --build-number "$BUILD_NUMBER" )

"$ROOT/scripts/pack-ipa.sh" "${PACK_ARGS[@]}"

# ---------------------------------------------------------------- dọn dẹp
if [[ "$KEEP_ARCHIVE" -eq 0 ]]; then
  rm -rf "$ARCHIVE_PATH"
else
  info "Giữ archive: $ARCHIVE_PATH"
fi

printf '\n%sBước tiếp theo%s: cài IPA lên iPhone — xem %sdocs/INSTALL.md%s\n\n' \
  "$BOLD" "$RESET" "$BOLD" "$RESET"

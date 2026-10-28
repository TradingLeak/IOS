#!/usr/bin/env bash
#
# pack-ipa.sh — Đóng gói một .app đã build thành file .ipa (unsigned).
# KHÔNG cần macOS: chạy được trên Linux/macOS/WSL, vì chỉ dùng zip + đọc plist.
#
#   ./scripts/pack-ipa.sh /đường/dẫn/VietMap.app
#   ./scripts/pack-ipa.sh build/VietMap.app --output dist --build-number 7
#
# Kết quả: <output>/<App>-<version>-<build>-unsigned.ipa và file .sha256
#
set -Eeuo pipefail

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  BLUE=$'\033[34m'; RESET=$'\033[0m'
else
  BOLD=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; RESET=''
fi
step() { printf '\n%s==> %s%s\n' "$BOLD$BLUE" "$*" "$RESET"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✔%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '    %s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf '\n%s✖ %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }
trap 'die "Đóng gói thất bại ở dòng $LINENO (lệnh: $BASH_COMMAND)"' ERR

usage() {
  cat <<EOF
${BOLD}pack-ipa.sh${RESET} — đóng gói .app → .ipa unsigned (chạy được trên Linux/macOS)

${BOLD}Cách dùng${RESET}
  ./scripts/pack-ipa.sh <đường/dẫn/App.app> [tuỳ chọn]

${BOLD}Tuỳ chọn${RESET}
  -o, --output DIR        Thư mục chứa IPA (mặc định: dist)
  -b, --bundle-id ID      Ghi đè CFBundleIdentifier
  -n, --display-name NAME Ghi đè tên hiển thị
      --short-version V   Ghi đè CFBundleShortVersionString
      --build-number N    Ghi đè CFBundleVersion
  -k, --keep-stage        Giữ thư mục tạm chứa Payload/
  -h, --help              Hiện trợ giúp

${BOLD}Ghi chú${RESET}
  • File .app phải là bản build cho thiết bị (arm64), không phải Simulator.
  • IPA tạo ra KHÔNG có chữ ký — cần ký lại để cài lên iPhone (xem docs/INSTALL.md).
EOF
}

APP_PATH=""
OUTPUT_DIR="dist"
BUNDLE_ID=""
DISPLAY_NAME=""
SHORT_VERSION=""
BUILD_NUMBER=""
KEEP_STAGE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)        OUTPUT_DIR="${2:?}"; shift 2 ;;
    -b|--bundle-id)     BUNDLE_ID="${2:?}"; shift 2 ;;
    -n|--display-name)  DISPLAY_NAME="${2:?}"; shift 2 ;;
    --short-version)    SHORT_VERSION="${2:?}"; shift 2 ;;
    --build-number)     BUILD_NUMBER="${2:?}"; shift 2 ;;
    -k|--keep-stage)    KEEP_STAGE=1; shift ;;
    -h|--help)          usage; exit 0 ;;
    -*)                 die "Tham số không hợp lệ: $1 (dùng --help)" ;;
    *)                  APP_PATH="$1"; shift ;;
  esac
done

[[ -n "$APP_PATH" ]] || { usage; exit 1; }
[[ -d "$APP_PATH" ]] || die "Không tìm thấy app bundle: $APP_PATH"
[[ "$APP_PATH" == *.app ]] || die "Đường dẫn phải trỏ tới thư mục .app (hiện tại: $APP_PATH)"

APP_NAME="$(basename "$APP_PATH")"
APP_PLIST="$APP_PATH/Info.plist"
[[ -f "$APP_PLIST" ]] || die "Thiếu Info.plist trong $APP_PATH"

command -v zip >/dev/null || die "Thiếu lệnh 'zip' (macOS có sẵn; Ubuntu: apt-get install zip)"

# ---------------------------------------------------------------- plist helper
# Ưu tiên PlistBuddy (macOS), fallback sang python3 (Linux/CI)
if [[ -x /usr/libexec/PlistBuddy ]]; then
  PLIST_TOOL="plistbuddy"
elif command -v python3 >/dev/null; then
  PLIST_TOOL="python"
else
  die "Cần PlistBuddy (macOS) hoặc python3 để sửa Info.plist"
fi

plist_get() {
  if [[ "$PLIST_TOOL" == "plistbuddy" ]]; then
    /usr/libexec/PlistBuddy -c "Print :$1" "$APP_PLIST" 2>/dev/null || true
  else
    python3 - "$APP_PLIST" "$1" <<'PY'
import plistlib, sys
path, key = sys.argv[1], sys.argv[2]
with open(path, "rb") as fh:
    data = plistlib.load(fh)
value = data.get(key, "")
print(value if isinstance(value, (str, int, float)) else "")
PY
  fi
}

plist_set() {
  local key="$1" value="$2"
  if [[ "$PLIST_TOOL" == "plistbuddy" ]]; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$APP_PLIST" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :$key string $value" "$APP_PLIST"
  else
    python3 - "$APP_PLIST" "$key" "$value" <<'PY'
import plistlib, sys
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "rb") as fh:
    data = plistlib.load(fh)
data[key] = value
with open(path, "wb") as fh:
    plistlib.dump(data, fh, fmt=plistlib.FMT_BINARY)
PY
  fi
}

step "Đóng gói IPA"
info "App bundle : $APP_PATH"
info "Sửa plist  : $PLIST_TOOL"

[[ -n "$BUNDLE_ID"     ]] && { plist_set CFBundleIdentifier "$BUNDLE_ID";            info "Bundle ID  : $BUNDLE_ID"; }
[[ -n "$DISPLAY_NAME"  ]] && { plist_set CFBundleDisplayName "$DISPLAY_NAME";       info "Tên hiển thị: $DISPLAY_NAME"; }
[[ -n "$SHORT_VERSION" ]] && { plist_set CFBundleShortVersionString "$SHORT_VERSION"; info "Phiên bản  : $SHORT_VERSION"; }
[[ -n "$BUILD_NUMBER"  ]] && { plist_set CFBundleVersion "$BUILD_NUMBER";           info "Build      : $BUILD_NUMBER"; }

# ---------------------------------------------------------------- làm sạch chữ ký
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/ipa-stage.XXXXXX")"
PAYLOAD="$STAGE/Payload"
mkdir -p "$PAYLOAD"

# ditto giữ nguyên symlink/xattr của framework (macOS); cp -a cho Linux
if command -v ditto >/dev/null; then
  ditto "$APP_PATH" "$PAYLOAD/$APP_NAME"
else
  cp -a "$APP_PATH" "$PAYLOAD/$APP_NAME"
fi

rm -rf \
  "$PAYLOAD/$APP_NAME/_CodeSignature" \
  "$PAYLOAD/$APP_NAME/SC_Info" \
  "$PAYLOAD/$APP_NAME/embedded.mobileprovision" \
  "$PAYLOAD/$APP_NAME/CodeResources"
find "$PAYLOAD" -name '._*' -delete 2>/dev/null || true
find "$PAYLOAD" -name '.DS_Store' -delete 2>/dev/null || true

# ---------------------------------------------------------------- metadata
IDENTIFIER="$(plist_get CFBundleIdentifier)"
[[ -n "$IDENTIFIER" ]] || die "Info.plist không có CFBundleIdentifier"
VERSION="$(plist_get CFBundleShortVersionString)"; VERSION="${VERSION:-1.0.0}"
BUILD_NUM="$(plist_get CFBundleVersion)";          BUILD_NUM="${BUILD_NUM:-1}"
MIN_OS="$(plist_get MinimumOSVersion)"

# Tên file an toàn, không dấu cách
SAFE_NAME="$(printf '%s' "${APP_NAME%.app}" | tr -c 'A-Za-z0-9._-' '-' | sed 's/--*/-/g; s/-$//')"
[[ -n "$SAFE_NAME" ]] || SAFE_NAME="App"
IPA_NAME="${SAFE_NAME}-${VERSION}-${BUILD_NUM}-unsigned.ipa"
mkdir -p "$OUTPUT_DIR"
# Chuyển sang đường dẫn tuyệt đối: lệnh zip chạy trong thư mục tạm ($STAGE),
# nếu để đường dẫn tương đối thì file IPA sẽ rơi vào $STAGE và bị xoá.
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
IPA_PATH="$OUTPUT_DIR/$IPA_NAME"
rm -f "$IPA_PATH"

# zip: -y giữ symlink, -r đệ quy, -q im lặng; chạy trong $STAGE để có Payload/ ở gốc
if ! ( cd "$STAGE" && COPYFILE_DISABLE=1 zip -qry "$IPA_PATH" Payload ); then
  [[ "$KEEP_STAGE" -eq 0 ]] && rm -rf "$STAGE"
  die "zip thất bại"
fi
[[ -s "$IPA_PATH" ]] || die "File IPA rỗng"

# ---------------------------------------------------------------- kiểm tra
step "Kiểm tra kết quả"
ENTRIES="$(unzip -l "$IPA_PATH" 2>/dev/null | grep -c "Payload/$APP_NAME/Info.plist" || true)"
if [[ "${ENTRIES:-0}" -ge 1 ]]; then
  ok "Có Payload/$APP_NAME/Info.plist"
else
  warn "Không thấy Info.plist trong zip — kiểm tra lại cấu trúc"
fi
EXEC_NAME="$(plist_get CFBundleExecutable)"
if [[ -n "$EXEC_NAME" && -f "$PAYLOAD/$APP_NAME/$EXEC_NAME" ]]; then
  ok "Có binary thực thi: $EXEC_NAME"
else
  warn "Không thấy binary thực thi '${EXEC_NAME:-?}' — app có thể không chạy được"
fi
if unzip -l "$IPA_PATH" 2>/dev/null | grep -qE '_CodeSignature|embedded\.mobileprovision'; then
  warn "Vẫn còn dấu chữ ký trong IPA"
else
  ok "Đã xoá toàn bộ chữ ký (_CodeSignature, mobileprovision)"
fi

SIZE="$(du -h "$IPA_PATH" | awk '{print $1}')"
SHA=""
if command -v shasum >/dev/null; then
  SHA="$(shasum -a 256 "$IPA_PATH" | awk '{print $1}')"
elif command -v sha256sum >/dev/null; then
  SHA="$(sha256sum "$IPA_PATH" | awk '{print $1}')"
fi
[[ -n "$SHA" ]] && printf '%s  %s\n' "$SHA" "$(basename "$IPA_PATH")" > "$IPA_PATH.sha256"

[[ "$KEEP_STAGE" -eq 0 ]] && rm -rf "$STAGE"

cat <<EOF

${BOLD}${GREEN}✔ Đóng gói xong${RESET}

  IPA          : ${BOLD}$IPA_PATH${RESET}
  Kích thước   : $SIZE
  Bundle ID    : $IDENTIFIER
  Phiên bản    : $VERSION ($BUILD_NUM)
  iOS tối thiểu: ${MIN_OS:-không rõ}
  Chữ ký       : ${YELLOW}không có (unsigned)${RESET}
  SHA-256      : ${SHA:-không tính được}

${BOLD}Cài lên iPhone${RESET}: xem docs/INSTALL.md
EOF

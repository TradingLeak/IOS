#!/usr/bin/env bash
#
# test-pack.sh — Tự kiểm thử khâu đóng gói IPA mà KHÔNG cần macOS/Xcode.
#
# Tạo một app bundle giả (Info.plist + binary + framework + symlink + chữ ký cũ),
# chạy scripts/pack-ipa.sh rồi kiểm tra lại file IPA bằng python3.
#
#   ./scripts/test-pack.sh
#
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ipakittest.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

pass() { printf '  \033[32m✔\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✖\033[0m %s\n' "$*" >&2; exit 1; }

printf '\n\033[1mTest: build một app bundle giả\033[0m\n'
APP="$WORK/Fake.app"
mkdir -p "$APP/Frameworks/Foo.framework" "$APP/_CodeSignature" "$APP/Base.lproj"

python3 - "$APP/Info.plist" <<'PY'
import plistlib, sys
info = {
    "CFBundleIdentifier": "com.example.fake",
    "CFBundleDisplayName": "Fake App",
    "CFBundleExecutable": "Fake",
    "CFBundleName": "Fake",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "2.3.4",
    "CFBundleVersion": "99",
    "MinimumOSVersion": "15.0",
}
with open(sys.argv[1], "wb") as fh:
    plistlib.dump(info, fh, fmt=plistlib.FMT_BINARY)
PY
printf '#!/bin/sh\necho fake\n' > "$APP/Fake"
chmod +x "$APP/Fake"
printf 'stale signature' > "$APP/_CodeSignature/CodeResources"
printf 'stale profile' > "$APP/embedded.mobileprovision"
printf 'x' > "$APP/Frameworks/Foo.framework/Foo"
ln -sf Foo "$APP/Frameworks/Foo.framework/Current"
ln -sf ../Fake "$APP/Frameworks/libfake.dylib"
printf 'hi' > "$APP/Base.lproj/Main.strings"
pass "app bundle giả đã tạo"

printf '\n\033[1mTest: chạy pack-ipa.sh\033[0m\n'
OUT="$WORK/dist"
"$ROOT/scripts/pack-ipa.sh" "$APP" --output "$OUT" \
  --bundle-id com.tradingleak.demo \
  --display-name "Demo App" \
  --build-number 7 >"$WORK/pack.log" 2>&1 || { cat "$WORK/pack.log"; fail "pack-ipa.sh lỗi"; }
pass "pack-ipa.sh chạy thành công"

IPA="$(find "$OUT" -maxdepth 1 -name '*.ipa' | head -n 1)"
[[ -n "$IPA" ]] || fail "Không có file .ipa được tạo"
pass "tạo được $(basename "$IPA")"
[[ -f "$IPA.sha256" ]] || fail "Thiếu file .sha256"
pass "có file .sha256"

printf '\n\033[1mTest: kiểm tra nội dung IPA\033[0m\n'
python3 - "$IPA" <<'PY' || exit 1
import plistlib, sys, zipfile

path = sys.argv[1]
zf = zipfile.ZipFile(path)
names = zf.namelist()
bad = zf.testzip()

def ok(msg):
    print("  \033[32m✔\033[0m " + msg)

def no(msg):
    print("  \033[31m✖\033[0m " + msg, file=sys.stderr)
    sys.exit(1)

if bad:
    no("zip hỏng ở entry: %s" % bad)
ok("zip không lỗi CRC")

for required in ["Payload/Fake.app/Info.plist", "Payload/Fake.app/Fake"]:
    if required not in names:
        no("Thiếu entry bắt buộc: " + required)
ok("có Payload/Fake.app/Info.plist và binary chính")

for unwanted in ["_CodeSignature", "embedded.mobileprovision", "CodeResources"]:
    if any(unwanted in n for n in names):
        no("Vẫn còn dấu chữ ký: " + unwanted)
ok("đã xoá _CodeSignature / mobileprovision")

info = plistlib.loads(zf.read("Payload/Fake.app/Info.plist"))
expected = {
    "CFBundleIdentifier": "com.tradingleak.demo",
    "CFBundleDisplayName": "Demo App",
    "CFBundleVersion": "7",
    "CFBundleShortVersionString": "2.3.4",
}
for key, value in expected.items():
    if str(info.get(key)) != value:
        no("%s = %r, mong đợi %r" % (key, info.get(key), value))
ok("ghi đè bundle id / tên / build number đúng")

dylib = [i for i in zf.infolist() if i.filename.endswith("libfake.dylib")]
if not dylib:
    no("Mất symlink Frameworks/libfake.dylib")
if ((dylib[0].external_attr >> 16) & 0o170000) != 0o120000:
    no("libfake.dylib không còn là symlink")
ok("giữ nguyên symlink trong Framework")

if not any(n.startswith("Payload/Fake.app/Frameworks/Foo.framework/") for n in names):
    no("Mất nội dung framework")
ok("giữ nguyên nội dung .framework")
PY

printf '\n\033[1mTest: --output là đường dẫn tương đối\033[0m\n'
mkdir -p "$WORK/relout" && cd "$WORK"
"$ROOT/scripts/pack-ipa.sh" "$APP" --output relout >"$WORK/pack-rel.log" 2>&1 \
  || { cat "$WORK/pack-rel.log"; fail "pack-ipa.sh lỗi với --output tương đối"; }
REL_IPA="$(find "$WORK/relout" -maxdepth 1 -name '*.ipa' | head -n 1)"
[[ -n "$REL_IPA" ]] || fail "IPA không nằm trong thư mục --output khi dùng đường dẫn tương đối"
pass "IPA nằm đúng thư mục với --output tương đối"

printf '\n\033[1mTest: trường hợp lỗi\033[0m\n'
if "$ROOT/scripts/pack-ipa.sh" "$WORK/khong-ton-tai.app" >/dev/null 2>&1; then
  fail "phải báo lỗi khi app không tồn tại"
fi
pass "báo lỗi đúng khi đường dẫn sai"

if "$ROOT/scripts/pack-ipa.sh" "$APP/Info.plist" >/dev/null 2>&1; then
  fail "phải báo lỗi khi không phải thư mục .app"
fi
pass "báo lỗi đúng khi không phải .app"

printf '\n\033[1;32m✔ Toàn bộ test đóng gói đều đạt\033[0m\n\n'

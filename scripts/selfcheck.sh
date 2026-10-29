#!/usr/bin/env bash
#
# selfcheck.sh — Kiểm tra nhanh repo mà KHÔNG cần macOS/Xcode.
# Chạy được trên Linux (dùng trong CI ở job "lint" trên ubuntu-latest).
#
#   ./scripts/selfcheck.sh
#
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAIL=0
pass() { printf '  \033[32m✔\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✖\033[0m %s\n' "$*" >&2; FAIL=1; }

printf '\n\033[1m1. Shell script\033[0m\n'
for f in scripts/*.sh; do
  if bash -n "$f" 2>/dev/null; then pass "$f cú pháp OK"; else fail "$f lỗi cú pháp"; fi
done
for f in scripts/*.sh; do
  [[ -x "$f" ]] && pass "$f có quyền thực thi" || fail "$f thiếu +x (chmod +x $f)"
done

printf '\n\033[1m2. File cấu hình\033[0m\n'
python3 - "$ROOT" <<'PY'
import json, plistlib, sys, os, glob

root = sys.argv[1]
bad = 0

def ok(msg):
    print("  \033[32m✔\033[0m " + msg)

def no(msg):
    global bad
    bad = 1
    print("  \033[31m✖\033[0m " + msg)

# Info.plist
try:
    with open(os.path.join(root, "App/Info.plist"), "rb") as fh:
        info = plistlib.load(fh)
    required = ["CFBundleIdentifier", "CFBundleExecutable", "CFBundleShortVersionString",
                "CFBundleVersion", "CFBundlePackageType", "MinimumOSVersion",
                "UIApplicationSceneManifest"]
    missing = [k for k in required if k not in info]
    if missing:
        no("Info.plist thiếu khoá: " + ", ".join(missing))
    else:
        ok("Info.plist hợp lệ, đủ %d khoá bắt buộc" % len(required))
except Exception as exc:  # noqa: BLE001
    no("Info.plist không đọc được: %s" % exc)

# Assets
assets = glob.glob(os.path.join(root, "App/Resources/Assets.xcassets/**/Contents.json"), recursive=True)
if not assets:
    no("Không tìm thấy Contents.json trong Assets.xcassets")
else:
    for path in assets:
        try:
            json.load(open(path))
        except Exception as exc:  # noqa: BLE001
            no("%s: JSON lỗi (%s)" % (os.path.relpath(path, root), exc))
            break
    else:
        ok("%d file Contents.json hợp lệ" % len(assets))

icon = os.path.join(root, "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
if not os.path.isfile(icon):
    no("Thiếu AppIcon-1024.png (bắt buộc để archive)")
else:
    with open(icon, "rb") as fh:
        head = fh.read(33)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        no("AppIcon-1024.png không phải PNG")
    else:
        w = int.from_bytes(head[16:20], "big")
        h = int.from_bytes(head[20:24], "big")
        bit_depth, color_type = head[24], head[25]
        if (w, h) != (1024, 1024):
            no("Icon phải 1024x1024, đang là %dx%d" % (w, h))
        elif color_type not in (0, 2):
            no("Icon còn kênh alpha (color type %d) — iOS sẽ từ chối. "
               "Chạy: convert icon.png -background white -alpha remove -alpha off out.png" % color_type)
        else:
            ok("AppIcon 1024x1024, không alpha (bit depth %d)" % bit_depth)

# Swift sources (quét đệ quy)
swift_files = sorted(glob.glob(os.path.join(root, "App/Sources/**/*.swift"), recursive=True))
if not swift_files:
    no("Không có file .swift nào trong App/Sources")
else:
    mains = [f for f in swift_files if "@main" in open(f, encoding="utf-8").read()]
    if len(mains) != 1:
        no("Phải có đúng 1 entry point @main, đang có %d" % len(mains))
    else:
        ok("%d file Swift, 1 entry point @main" % len(swift_files))

    def strip_literals(text):
        """Bỏ chuỗi và comment để đếm ngoặc chính xác."""
        out = []
        i, n = 0, len(text)
        while i < n:
            if text.startswith('"""', i):
                end = text.find('"""', i + 3)
                i = n if end < 0 else end + 3
                continue
            if text.startswith('#"', i):
                end = text.find('"#', i + 2)
                i = n if end < 0 else end + 2
                continue
            c = text[i]
            nxt = text[i + 1] if i + 1 < n else ""
            if c == "/" and nxt == "/":
                end = text.find("\n", i)
                i = n if end < 0 else end
                continue
            if c == "/" and nxt == "*":
                end = text.find("*/", i + 2)
                i = n if end < 0 else end + 2
                continue
            if c == '"':
                i += 1
                while i < n:
                    if text[i] == "\\":
                        i += 2
                        continue
                    if text[i] == '"':
                        i += 1
                        break
                    i += 1
                continue
            out.append(c)
            i += 1
        return "".join(out)

    unbalanced = []
    for path in swift_files:
        code = strip_literals(open(path, encoding="utf-8").read())
        for open_ch, close_ch in (("{", "}"), ("(", ")"), ("[", "]")):
            if code.count(open_ch) != code.count(close_ch):
                unbalanced.append(os.path.relpath(path, root))
                break
    if unbalanced:
        no("Ngoặc không cân bằng: " + ", ".join(unbalanced))
    else:
        ok("Ngoặc cân bằng ở tất cả file Swift")

# project.yml / Info.plist khớp nhau
yml = open(os.path.join(root, "project.yml"), encoding="utf-8").read()
for needle in ["INFOPLIST_FILE: App/Info.plist", "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon",
               "CODE_SIGNING_ALLOWED: NO", "PRODUCT_BUNDLE_IDENTIFIER:"]:
    if needle in yml:
        ok("project.yml có: " + needle)
    else:
        no("project.yml thiếu: " + needle)

# workflow
try:
    with open(os.path.join(root, "App/Info.plist"), "rb") as fh:
        info2 = plistlib.load(fh)
    for key in ["NSLocationWhenInUseUsageDescription", "AIBaseURL", "AIModel", "AIApiKey"]:
        if key not in info2:
            no("Info.plist thiếu khoá: " + key)
        else:
            ok("Info.plist có " + key)
except Exception as exc:  # noqa: BLE001
    no("Không đọc được Info.plist: %s" % exc)

wf = os.path.join(root, ".github/workflows/build-unsigned-ipa.yml")
if os.path.isfile(wf):
    text = open(wf, encoding="utf-8").read()
    for needle in ["runs-on: macos-", "upload-artifact", "make-ipa.sh"]:
        if needle in text:
            ok("workflow có: " + needle)
        else:
            no("workflow thiếu: " + needle)
else:
    no("Thiếu .github/workflows/build-unsigned-ipa.yml")

sys.exit(bad)
PY
if [[ $? -ne 0 ]]; then FAIL=1; fi

printf '\n\033[1m3. Tài liệu\033[0m\n'
for f in README.md docs/BUILD.md docs/INSTALL.md docs/TROUBLESHOOTING.md; do
  if [[ -s "$f" ]]; then pass "$f"; else fail "thiếu $f"; fi
done

printf '\n\033[1m4. Test đóng gói IPA (không cần Xcode)\033[0m\n'
if ./scripts/test-pack.sh > /tmp/selfcheck-pack.log 2>&1; then
  pass "pack-ipa.sh tạo đúng cấu trúc IPA (xem scripts/test-pack.sh)"
else
  fail "test-pack.sh thất bại — log:"
  sed 's/^/      /' /tmp/selfcheck-pack.log >&2
fi

printf '\n'
printf '\n\033[1m5. Test gói bản đồ Việt Nam offline\033[0m\n'
if python3 scripts/test_offline_map.py; then
  pass "Manifest, SHA-256 và SQLite mẫu offline hợp lệ"
else
  fail "Test gói bản đồ offline thất bại"
fi

printf '\n\033[1m6. Test kiểm tra cấu trúc IPA\033[0m\n'
if python3 scripts/test_verify_ipa.py; then
  pass "IPA audit nhận diện ZIP, plist, quyền executable và Mach-O sai"
else
  fail "Test kiểm tra IPA thất bại"
fi

if [[ "$FAIL" -eq 0 ]]; then
  printf '\033[1;32m✔ Tất cả kiểm tra đều đạt\033[0m\n\n'
else
  printf '\033[1;31m✖ Có kiểm tra thất bại\033[0m\n\n' >&2
  exit 1
fi

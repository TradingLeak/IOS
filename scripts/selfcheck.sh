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
import json, plistlib, sys, os, glob, re

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

# PartnerApp (app theo dõi hoa hồng Exness)
partner_swift = sorted(glob.glob(os.path.join(root, "PartnerApp/Sources/**/*.swift"), recursive=True))
if not partner_swift:
    no("Không có file .swift nào trong PartnerApp/Sources")
else:
    partner_mains = [f for f in partner_swift if "@main" in open(f, encoding="utf-8").read()]
    if len(partner_mains) != 1:
        no("PartnerApp phải có đúng 1 entry point @main, đang có %d" % len(partner_mains))
    else:
        ok("PartnerApp: %d file Swift, 1 entry point @main" % len(partner_swift))

    partner_unbalanced = []
    for path in partner_swift:
        pcode = strip_literals(open(path, encoding="utf-8").read())
        for open_ch, close_ch in (("{", "}"), ("(", ")"), ("[", "]")):
            if pcode.count(open_ch) != pcode.count(close_ch):
                partner_unbalanced.append(os.path.relpath(path, root))
                break
    if partner_unbalanced:
        no("PartnerApp ngoặc không cân bằng: " + ", ".join(partner_unbalanced))
    else:
        ok("PartnerApp: ngoặc cân bằng ở tất cả file Swift")

# PartnerApp Info.plist + icon
pinfo = None
try:
    with open(os.path.join(root, "PartnerApp/Info.plist"), "rb") as fh:
        pinfo = plistlib.load(fh)
    prequired = ["CFBundleIdentifier", "CFBundleExecutable", "CFBundleShortVersionString",
                 "CFBundleVersion", "CFBundlePackageType", "MinimumOSVersion"]
    pmissing = [k for k in prequired if k not in pinfo]
    if pmissing:
        no("PartnerApp/Info.plist thiếu khoá: " + ", ".join(pmissing))
    else:
        ok("PartnerApp/Info.plist hợp lệ, đủ %d khoá bắt buộc" % len(prequired))
except Exception as exc:  # noqa: BLE001
    no("PartnerApp/Info.plist không đọc được: %s" % exc)

# PartnerApp Background App Refresh: id trong Info.plist phải khớp id trong mã nguồn
pbg_ids = (pinfo.get("BGTaskSchedulerPermittedIdentifiers") or []) if isinstance(pinfo, dict) else []
pbg_modes = (pinfo.get("UIBackgroundModes") or []) if isinstance(pinfo, dict) else []
pnotifier = os.path.join(root, "PartnerApp/Sources/Services/PaymentNotifier.swift")
if not os.path.isfile(pnotifier):
    no("Thiếu PartnerApp/Sources/Services/PaymentNotifier.swift")
else:
    psrc = open(pnotifier, encoding="utf-8").read()
    pcode_id = re.search(r'taskIdentifier\s*=.*payment-refresh"', psrc)
    pbg_ok = bool(pbg_ids) and all(str(x).endswith(".payment-refresh") for x in pbg_ids)
    if not pcode_id:
        no("PaymentNotifier.swift không khai taskIdentifier cho Background App Refresh")
    elif not pbg_ok:
        no("Info.plist BGTaskSchedulerPermittedIdentifiers phải là <bundle id>.payment-refresh")
    elif "fetch" not in pbg_modes:
        no("Info.plist UIBackgroundModes thiếu 'fetch' (cần cho BGAppRefreshTask)")
    else:
        ok("PartnerApp: Background App Refresh id khớp Info.plist, UIBackgroundModes có fetch")

picon = os.path.join(root, "PartnerApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
if not os.path.isfile(picon):
    no("Thiếu icon PartnerApp (AppIcon-1024.png)")
else:
    with open(picon, "rb") as fh:
        phead = fh.read(33)
    if phead[:8] != b"\x89PNG\r\n\x1a\n":
        no("Icon PartnerApp không phải PNG")
    else:
        pw = int.from_bytes(phead[16:20], "big")
        ph = int.from_bytes(phead[20:24], "big")
        if (pw, ph) != (1024, 1024):
            no("Icon PartnerApp phải 1024x1024, đang là %dx%d" % (pw, ph))
        elif phead[25] not in (0, 2):
            no("Icon PartnerApp còn kênh alpha (color type %d)" % phead[25])
        else:
            ok("Icon PartnerApp 1024x1024, không alpha")

# PulseApp (app giá + lịch kinh tế + tin tức + cảnh báo)
pulse_swift = sorted(glob.glob(os.path.join(root, "PulseApp/Sources/**/*.swift"), recursive=True))
if not pulse_swift:
    no("Không có file .swift nào trong PulseApp/Sources")
else:
    pulse_mains = [f for f in pulse_swift if "@main" in open(f, encoding="utf-8").read()]
    if len(pulse_mains) != 1:
        no("PulseApp phải có đúng 1 entry point @main, đang có %d" % len(pulse_mains))
    else:
        ok("PulseApp: %d file Swift, 1 entry point @main" % len(pulse_swift))

    pulse_unbalanced = []
    for path in pulse_swift:
        pcode = strip_literals(open(path, encoding="utf-8").read())
        for open_ch, close_ch in (("{", "}"), ("(", ")"), ("[", "]")):
            if pcode.count(open_ch) != pcode.count(close_ch):
                pulse_unbalanced.append(os.path.relpath(path, root))
                break
    if pulse_unbalanced:
        no("PulseApp ngoặc không cân bằng: " + ", ".join(pulse_unbalanced))
    else:
        ok("PulseApp: ngoặc cân bằng ở tất cả file Swift")

    # Không được dùng API chỉ có iOS 17 (project deploy iOS 16)
    ios17 = []
    for path in pulse_swift:
        text = open(path, encoding="utf-8").read()
        if "onChange(of:" in text and "{ old, new in" in text:
            ios17.append(os.path.relpath(path, root))
    if ios17:
        no("PulseApp dùng Scene.onChange(of:) { old, new } (iOS 17): " + ", ".join(ios17))
    else:
        ok("PulseApp: không dùng API iOS 17-only")

    # Mỗi nguồn dữ liệu miễn phí phải có URL đúng trong mã nguồn
    pnews = open(os.path.join(root, "PulseApp/Sources/Models/NewsModels.swift"), encoding="utf-8").read()
    pcal = open(os.path.join(root, "PulseApp/Sources/Models/EconomicEvent.swift"), encoding="utf-8").read()
    for needle in ["https://www.fxstreet.com/rss/news", "https://investinglive.com/feed/news",
                   "https://www.coindesk.com/arc/outboundfeeds/rss/",
                   "https://www.federalreserve.gov/feeds/press_all.xml"]:
        if needle in pnews:
            ok("PulseApp nguồn tin: " + needle)
        else:
            no("PulseApp thiếu nguồn tin: " + needle)
    for needle in ["ff_calendar_thisweek.json", "ff_calendar_nextweek.json"]:
        if needle in pcal:
            ok("PulseApp lịch kinh tế: " + needle)
        else:
            no("PulseApp thiếu nguồn lịch: " + needle)

pulse_info = None
try:
    with open(os.path.join(root, "PulseApp/Info.plist"), "rb") as fh:
        pulse_info = plistlib.load(fh)
    pulse_required = ["CFBundleIdentifier", "CFBundleExecutable", "CFBundleShortVersionString",
                      "CFBundleVersion", "CFBundlePackageType", "MinimumOSVersion", "UIBackgroundModes"]
    pulse_missing = [k for k in pulse_required if k not in pulse_info]
    if pulse_missing:
        no("PulseApp/Info.plist thiếu khoá: " + ", ".join(pulse_missing))
    else:
        ok("PulseApp/Info.plist hợp lệ, đủ %d khoá bắt buộc" % len(pulse_required))
except Exception as exc:  # noqa: BLE001
    no("PulseApp/Info.plist không đọc được: %s" % exc)

pulse_bg_ids = (pulse_info.get("BGTaskSchedulerPermittedIdentifiers") or []) if isinstance(pulse_info, dict) else []
pulse_bg_modes = (pulse_info.get("UIBackgroundModes") or []) if isinstance(pulse_info, dict) else []
pulse_notifier = os.path.join(root, "PulseApp/Sources/Services/AlertNotifier.swift")
if not os.path.isfile(pulse_notifier):
    no("Thiếu PulseApp/Sources/Services/AlertNotifier.swift")
else:
    pulse_src = open(pulse_notifier, encoding="utf-8").read()
    pulse_code_id = re.search(r'taskIdentifier\s*=.*alert-refresh"', pulse_src)
    pulse_bg_ok = len(pulse_bg_ids) == 1 and str(pulse_bg_ids[0]).endswith(".alert-refresh")
    if not pulse_code_id:
        no("AlertNotifier.swift không khai taskIdentifier cho Background App Refresh")
    elif not pulse_bg_ok:
        no("PulseApp Info.plist BGTaskSchedulerPermittedIdentifiers phải là <bundle id>.alert-refresh")
    elif "fetch" not in pulse_bg_modes:
        no("PulseApp Info.plist UIBackgroundModes thiếu 'fetch'")
    else:
        ok("PulseApp: Background App Refresh id khớp Info.plist, UIBackgroundModes có fetch")

pulse_icon = os.path.join(root, "PulseApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
if not os.path.isfile(pulse_icon):
    no("Thiếu icon PulseApp (AppIcon-1024.png)")
else:
    with open(pulse_icon, "rb") as fh:
        puhead = fh.read(33)
    if puhead[:8] != b"\x89PNG\r\n\x1a\n":
        no("Icon PulseApp không phải PNG")
    else:
        puw = int.from_bytes(puhead[16:20], "big")
        puh = int.from_bytes(puhead[20:24], "big")
        if (puw, puh) != (1024, 1024):
            no("Icon PulseApp phải 1024x1024, đang là %dx%d" % (puw, puh))
        elif puhead[25] not in (0, 2):
            no("Icon PulseApp còn kênh alpha (color type %d)" % puhead[25])
        else:
            ok("Icon PulseApp 1024x1024, không alpha")

# project.yml / Info.plist khớp nhau
yml = open(os.path.join(root, "project.yml"), encoding="utf-8").read()
for needle in ["INFOPLIST_FILE: App/Info.plist", "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon",
               "CODE_SIGNING_ALLOWED: NO", "PRODUCT_BUNDLE_IDENTIFIER:"]:
    if needle in yml:
        ok("project.yml có: " + needle)
    else:
        no("project.yml thiếu: " + needle)

for needle in ["PartnerApp/Info.plist", "com.tradingleak.partnerhub",
               "PartnerHubTests"]:
    if needle in yml:
        ok("project.yml có PartnerHub: " + needle)
    else:
        no("project.yml thiếu PartnerHub: " + needle)

for needle in ["PulseApp/Info.plist", "com.tradingleak.pulsehub",
               "PulseHubTests", "PulseApp/Sources"]:
    if needle in yml:
        ok("project.yml có PulseHub: " + needle)
    else:
        no("project.yml thiếu PulseHub: " + needle)

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

wf2 = os.path.join(root, ".github/workflows/build-partnerhub-ipa.yml")
if os.path.isfile(wf2):
    text2 = open(wf2, encoding="utf-8").read()
    for needle in ["runs-on: macos-", "PartnerHub", "make-ipa.sh", "upload-artifact"]:
        if needle in text2:
            ok("workflow PartnerHub có: " + needle)
        else:
            no("workflow PartnerHub thiếu: " + needle)
else:
    no("Thiếu .github/workflows/build-partnerhub-ipa.yml")

wf3 = os.path.join(root, ".github/workflows/build-pulsehub-ipa.yml")
if os.path.isfile(wf3):
    text3 = open(wf3, encoding="utf-8").read()
    for needle in ["runs-on: macos-", "PulseHub", "make-ipa.sh", "upload-artifact",
                   "latest-pulsehub-ipa", "PulseApp/**"]:
        if needle in text3:
            ok("workflow PulseHub có: " + needle)
        else:
            no("workflow PulseHub thiếu: " + needle)
else:
    no("Thiếu .github/workflows/build-pulsehub-ipa.yml")

# Id BG của hai app phải khác nhau (cài cùng máy không được trùng)
partner_ids = set((pinfo.get("BGTaskSchedulerPermittedIdentifiers") or [])) if isinstance(pinfo, dict) else set()
pulse_ids = set(pulse_bg_ids)
if partner_ids & pulse_ids:
    no("BGTaskSchedulerPermittedIdentifiers trùng giữa PartnerApp và PulseApp: " + ", ".join(partner_ids & pulse_ids))
else:
    ok("BGTaskSchedulerPermittedIdentifiers khác nhau giữa PartnerApp và PulseApp")

sys.exit(bad)
PY
if [[ $? -ne 0 ]]; then FAIL=1; fi

printf '\n\033[1m3. Tài liệu\033[0m\n'
for f in README.md docs/BUILD.md docs/INSTALL.md docs/TROUBLESHOOTING.md docs/EXNESS-PARTNER.md docs/PULSE.md; do
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
if [[ "$FAIL" -eq 0 ]]; then
  printf '\033[1;32m✔ Tất cả kiểm tra đều đạt\033[0m\n\n'
else
  printf '\033[1;31m✖ Có kiểm tra thất bại\033[0m\n\n' >&2
  exit 1
fi

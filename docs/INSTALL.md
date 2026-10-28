# 📲 Cài file IPA unsigned lên iPhone

Bạn đã có `VietMap-unsigned.ipa` (bản 2.0.0 trở lên, có cảnh báo tốc độ/camera và tuyến
xe máy). File này **chưa có chữ ký Apple**, nên cần một trong các cách dưới đây.

Tải bản mới nhất:
<https://github.com/TradingLeak/IOS/releases/download/latest-ipa/VietMap-unsigned.ipa>

Chọn theo phiên bản iOS của bạn (Cài đặt → Cài đặt chung → Giới thiệu):

| iOS của bạn | Cách tốt nhất | Cần Apple ID? | Cần máy tính? |
|---|---|---|---|
| 14.0 → 16.6.1, 16.7 RC, 17.0 | **TrollStore** | Không | Lúc cài TrollStore: có |
| 17.0.1 trở lên (17.x, 18.x, 26.x) | **SideStore / AltStore / Sideloadly / ESign** | Apple ID miễn phí | Có (lần đầu) |
| Bất kỳ + đã jailbreak | AppSync Unified / TrollStore | Không | Không |

---

## Cách 1 — TrollStore (vĩnh viễn, không cần ký)

Chỉ dùng được khi iOS nằm trong dải hỗ trợ của lỗ hổng CoreTrust
(14.0 beta 2 → 16.6.1, 16.7 RC build `20H18`, và 17.0 trên thiết bị A12+).
Dải này **không thể mở rộng**: Apple vá lỗi từ 17.0.1, nên mọi video "TrollStore cho
iOS 18/26" đều là lừa đảo.

1. Cài TrollStore theo hướng dẫn chính thức: <https://ios.cfw.guide/installing-trollstore/>
   (dùng TrollInstallerX / TrollRestore, cần máy tính ở bước đầu).
2. Gửi file `.ipa` sang iPhone (AirDrop, iCloud Drive, Google Drive, Telegram…).
3. Mở app **TrollStore** → dấu **+** → chọn file IPA → **Install**.
4. Xong. App chạy vĩnh viễn, không hết hạn, không cần ký lại.

Nếu TrollStore không mở được file từ Files: bấm giữ file IPA → **Chia sẻ** →
**TrollStore**.

---

## Cách 2 — Sideloadly (Windows / macOS, đơn giản nhất)

Dùng **Apple ID miễn phí** (không cần trả 99$). Chứng chỉ sống **7 ngày**, tối đa
**3 app** cùng lúc, tối đa **10 App ID mới mỗi tuần**.

1. Tải Sideloadly: <https://sideloadly.io>
2. Cài **iTunes** (bản từ apple.com, không phải Microsoft Store) để có driver + Apple
   Application Support.
3. Cắm iPhone → **Tin cậy máy tính**.
4. Mở Sideloadly → kéo file IPA vào ô *IPA*.
5. Nhập **Apple ID** (nên dùng một Apple ID phụ, không bật 2FA hoặc dùng
   [app-specific password](https://appleid.apple.com) nếu có 2FA).
6. Bấm **Start** → nhập mật khẩu → chờ. Nếu được hỏi, bật **iOS signing** với
   *Anisette* mặc định.
7. Trên iPhone: Cài đặt → Cài đặt chung → **VPN & Quản lý thiết bị** → tin cậy
   developer của bạn.
8. Mở app. Sau 7 ngày, chạy lại Sideloadly (dữ liệu app được giữ nguyên).

> Bundle ID: nếu Sideloadly báo trùng App ID, bật tuỳ chọn *Change bundle ID* và
> thêm hậu tố bất kỳ.

---

## Cách 3 — AltStore / SideStore (ký lại tự động qua Wi-Fi)

**SideStore** là lựa chọn tốt hơn AltStore hiện nay: không cần máy tính thường trực,
tự refresh chứng chỉ qua Wi-Fi bằng chính Apple ID của bạn.

1. Cài SideStore: <https://sidestore.io> (theo hướng dẫn *AltServer/Jitterbugpair*
   ở lần đầu).
2. Mở SideStore → tab **My Apps** → dấu **+** → chọn file `.ipa`.
3. SideStore ký bằng Apple ID và cài. Bật **Background Refresh** để app tự ký lại
   trước khi hết 7 ngày.

AltStore (bản cổ điển) cần **AltServer** chạy trên Mac/PC cùng mạng Wi-Fi mỗi lần
refresh: <https://altstore.io>

---

## Cách 4 — ESign / Feather / Scarlet (ký ngay trên máy)

Các app này cài qua cấu hình MDM/enterprise hoặc sideload, cho phép **ký file IPA
ngay trên iPhone** bằng Apple ID hoặc bằng chứng chỉ có sẵn.

- Feather: <https://github.com/khcrysalis/Feather> (mã nguồn mở)
- ESign / Scarlet: nguồn không chính thức, cần cẩn trọng khi nhập Apple ID.

⚠️ Chỉ nhập Apple ID vào công cụ **mã nguồn mở, uy tín** hoặc dùng Apple ID phụ.
Không nhập Apple ID chính của bạn vào app crack/nguồn lạ.

---

## Cách 5 — Apple Developer Program (chính thức, 99$/năm)

Khi bạn cần: chứng chỉ 1 năm, không giới hạn thiết bị, TestFlight, App Store.

1. Đăng ký tại <https://developer.apple.com/programs/>
2. Trong Xcode: **Signing & Capabilities** → chọn Team → Xcode tự tạo profile.
3. `Product → Archive` → **Distribute App → Development/Ad Hoc/App Store**.
4. Cài qua Xcode (cắm máy) hoặc TestFlight.

Nếu chỉ cần chạy trên máy mình, **Apple ID miễn phí** trong Xcode là đủ:
Xcode → Settings → Accounts → thêm Apple ID → chọn target → Team = *Your Name
(Personal Team)* → Run. (Cách này build trực tiếp, không qua file IPA.)

---

## Cài đặt bằng Apple Configurator / Xcode Devices

Nếu bạn có IPA **đã ký** (ví dụ do người khác gửi), có thể cài bằng:

- **Apple Configurator 2** (macOS): kéo file `.ipa` vào cửa sổ thiết bị.
- **Xcode → Window → Devices and Simulators** → dấu **+** dưới *Installed Apps*.

IPA unsigned sẽ báo lỗi `ApplicationVerificationFailed` ở cả hai cách — đó là hành vi
đúng, hãy dùng cách 1–4.

---

## Câu hỏi thường gặp nhanh

**App hết hạn sau 7 ngày?**
Đúng, với chứng chỉ Apple ID miễn phí. Dùng SideStore/AltStore để tự refresh, hoặc
TrollStore để khỏi lo.

**Có bị thu hồi (revoke) chứng chỉ không?**
Apple có thể thu hồi chứng chỉ miễn phí nếu lạm dụng. Dùng Apple ID phụ, đừng chia sẻ
chứng chỉ cho nhiều người.

**Cài được lên iPad không?**
Có — cùng file IPA (target đã bật `TARGETED_DEVICE_FAMILY = "1,2"`).

**Có cần jailbreak không?**
Không, trừ cách 5 (AppSync) và một số thiết bị cài TrollStore.

**Máy không có máy tính thì sao?**
Dùng ESign/Feather (cách 4) hoặc TrollStore nếu iOS phù hợp.

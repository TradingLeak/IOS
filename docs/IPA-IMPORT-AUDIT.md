# Kiểm tra IPA khi không nhập được vào ESign

## Kết quả với đúng IPA đã phát hành ngày 29/10/2026

- Build nguồn: <https://github.com/TradingLeak/IOS/actions/runs/40814336890>
- Lần kiểm tra lại: <https://github.com/TradingLeak/IOS/actions/runs/40815009666>
- File: `VietMap-1.0.0-1-unsigned.ipa`
- Kích thước: **7.081.246 byte**.
- SHA-256: `b2d5b76241d160bbc34566359873c7b22b927f961a96db066aa8d89f0115dd2d`.

Runner GitHub tải lại đúng artifact của build nguồn, kiểm tra hash khớp rồi đọc trực tiếp
ZIP/plist/Mach-O; không dựa riêng vào trạng thái build thành công.

| Kiểm tra | Kết quả |
| --- | --- |
| ZIP CRC | PASS |
| Compression | ZIP chuẩn, không có mã hoá mật khẩu |
| App gốc | `Payload/VietMap.app` |
| Info.plist | Đọc được, binary plist |
| Bundle ID | `com.tradingleak.vietmap` |
| CFBundleExecutable | `VietMap`, file tồn tại |
| Quyền executable trong ZIP | `0755` |
| Kiến trúc / platform | arm64 / iOS thiết bị, không phải Simulator |
| MinimumOSVersion | iOS 16.0, khớp Mach-O |
| FairPlay encryption | Không |
| Provisioning profile / tài nguyên chữ ký | Không, đúng với bản unsigned |
| LC_CODE_SIGNATURE | Không có trong executable hiện tại |

**Chưa thử trên ESign hoặc iPhone thật.** Không được diễn giải kết quả PASS là đã chứng minh
nhập/ký/cài ESign thành công. Thiếu `LC_CODE_SIGNATURE` là một chi tiết tương thích cần đối chiếu
với lỗi của công cụ ký; không tự động kết luận đó là nguyên nhân lỗi nhập.
Không đổi chữ ký/đóng gói hoặc phát hành lại IPA khi chạy audit này.

## Thông tin cần khi báo lỗi

1. Ảnh hoặc nguyên văn thông báo ESign; lỗi ở bước **nhập file**, **ký**, hay **cài đặt**?
2. Phiên bản iOS và ESign, tên file/kích thước đang được nhập.
3. Không gửi mật khẩu Apple ID, khoá riêng, mật khẩu `.p12` hoặc chứng chỉ nhạy cảm lên chat.

Nếu lỗi ngay lúc nhập:

- Tải trực tiếp file `.ipa` từ Release, lưu vào ứng dụng Tệp và chờ tải hoàn tất.
- Không nhập file `.sha256`, trang HTML tải lỗi, hoặc ZIP của mục Artifacts chứa IPA bên trong.
  Nếu lấy từ Artifacts, giải nén ZIP ngoài rồi chọn file `.ipa` bên trong.
- Thao tác trong phần quản lý tệp của ESign, chọn `.ipa` rồi chọn mục nhập ứng dụng/thư viện
  (tên mục tuỳ phiên bản). Không nhầm nhập IPA với nhập chứng chỉ.
- So sánh kích thước/hash ở trên để loại trừ tải dở hoặc tải nhầm.

Nếu nhập được nhưng ký/cài lỗi, cần kiểm tra chứng chỉ và provisioning profile phù hợp,
hiệu lực, thiết bị được cấp phép và iOS >=16.0. Việc chỉ đổi đuôi tệp hoặc nhúng một chữ ký ad-hoc
không thay thế chứng chỉ/provisioning hợp lệ để cài.

## Công cụ kiểm tra lại

```bash
python3 scripts/verify-ipa.py /path/to/VietMap.ipa \
  --expected-sha256 b2d5b76241d160bbc34566359873c7b22b927f961a96db066aa8d89f0115dd2d \
  --report /path/to/ipa-audit.json
python3 scripts/test_verify_ipa.py
```

Script không cần Xcode, không giải nén IPA và không xuất toàn bộ Info.plist/cấu hình AI.
8 test tổng hợp: thiết bị hợp lệ, Simulator/x86_64, binary mã hoá, quyền thực thi, file thiếu,
Payload sai tầng, HTML giả IPA và checksum.

Workflow có chế độ `inspect_run_id` để tải artifact từ lần build đã có mà không build/phát hành lại.
`inspect_sha256` là tuỳ chọn để đối chiếu hash. GitHub connection hiện tại không cấp quyền
`workflow_dispatch`; audit ở trên đã chạy bằng push trên nhánh phiên làm việc với marker
`[audit-ipa]`. Marker này chỉ chạy audit, bỏ qua build/release; mục tiêu push-audit đang được
pin tới run/hash đã nêu. Không dùng marker này cho commit cần build IPA mới.

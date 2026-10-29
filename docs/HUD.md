# HUD lái xe iOS — lấy cảm hứng từ VietHUD

## Phạm vi

VietHUD gốc là firmware ESP32 + GNSS + màn hình riêng. Bản triển khai trong repository
này dùng **SwiftUI + CoreLocation trên iPhone/iPad (iOS 16 trở lên)**, tận dụng bộ đọc
Speedmap đã có. Không cần kết nối thiết bị ESP32 hoặc API AI để dùng HUD.

Đây là chức năng mới của VietMap, không phải ứng dụng chính thức của tác giả VietHUD.
Không bao gồm OTA dữ liệu, đồng bộ thiết bị ESP32, CarPlay hoặc GPS chạy nền.

## Cách mở

1. Mở VietMap, bấm nút **đồng hồ tốc độ** bên phải bản đồ, hoặc menu ☰ →
   **HUD lái xe offline**.
2. Cấp quyền **Khi dùng ứng dụng** và bật **Vị trí chính xác**.
3. Đặt máy ở nơi thu GPS tốt; không cần chọn tuyến để HUD cập nhật liên tục.
4. Xoay ngang hoặc dọc tùy giá đỡ. **Tùy chọn** cho phép bật phản chiếu nội dung HUD,
   giữ sáng màn hình, giọng nói và âm báo. Thanh điều khiển không phản chiếu để vẫn thao tác được.
5. Bấm **Bản đồ** để thoát. GPS liên tục dừng nếu không còn phiên chỉ đường.

Giới hạn tốc độ và camera/biển báo tra cứu từ dữ liệu `.bin` được bundle sẵn.
Bản đồ nền, tìm kiếm và tính tuyến Apple Maps là chức năng khác, có thể cần Internet.
Muốn nghe giọng Việt offline, hãy tải giọng Tiếng Việt trong Cài đặt iOS trước chuyến đi.

## Quy tắc an toàn

- Chỉ dùng GPS có tuổi tối đa **10 giây**, độ chính xác ngang **0–50 m**;
  bỏ mẫu ở tương lai quá 2 giây và bỏ mẫu cũ hơn mẫu đã nhận.
- Khi GPS không còn tin cậy, xoá tốc độ/đường/giới hạn/cảnh báo cũ. Tốc độ GPS không hợp lệ
  hiển thị `—`, **không đổi thành 0 km/h**.
- Cảnh báo vượt tốc bắt đầu khi tốc độ vượt giới hạn hơn **2 km/h**, kết thúc khi về
  bằng hoặc dưới giới hạn. Âm/giọng nhắc tối đa một lần mỗi **30 giây**.
  Màu số tốc độ thể hiện ngưỡng vượt hơn 2 km/h tức thời.
- Không suy đoán giới hạn khi không khớp đường hoặc dữ liệu không có giới hạn.
- HUD chỉ có một thẻ cảnh báo chính để dễ đọc khi xoay ngang; engine vẫn xử lý tối đa 3 thẻ.
- Khi ứng dụng ra nền: dừng GPS liên tục, xoá dữ liệu HUD và dừng giọng đang đọc.
  Khi quay lại: lấy GPS mới nếu HUD/điều hướng còn mở.
- Giữ sáng chỉ áp dụng trong HUD khi ứng dụng hoạt động; khôi phục thiết lập trước đó khi thoát.
- Dữ liệu có thể cũ hoặc khớp nhầm đường song song. Không có cảnh báo không có nghĩa là
  không có camera. Luôn tuân thủ biển báo thực tế; chỉ thao tác khi xe đã dừng.

## Mã nguồn

| File | Vai trò |
| --- | --- |
| `App/Sources/Views/DrivingHUDScreen.swift` | HUD toàn màn hình, bố cục dọc/ngang, phản chiếu, tuỳ chọn |
| `App/Sources/Services/HUDSafety.swift` | Kiểm tra GPS, hysteresis và cooldown vượt tốc |
| `App/Sources/Services/LocationService.swift` | GPS liên tục kể cả sau khi vừa cấp quyền |
| `App/Sources/Speedmap/SpeedmapController.swift` | Loại GPS lỗi, xoá dữ liệu cũ, cập nhật khoảng cách thẻ giữ lại |
| `App/Sources/Views/MapScreen.swift` | Mở HUD và quản lý vòng đời GPS/giọng nói |
| `App/Tests/HUDSafetyTests.swift` | Kiểm thử GPS, cooldown, reset và nạp dữ liệu |

## Build IPA và kiểm chứng

Trên Linux chỉ chạy được kiểm tra tĩnh/cấu trúc đóng gói:

```bash
./scripts/selfcheck.sh
./scripts/test-pack.sh
```

**Các kiểm tra này không biên dịch Swift/iOS và không tạo IPA cài được.**

Trên máy Mac có Xcode 16.4 và XcodeGen:

```bash
./scripts/setup-macos.sh
xcodebuild test -project VietMap.xcodeproj -scheme VietMap \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
./scripts/make-ipa.sh
```

Thay tên Simulator nếu máy có thiết bị khác. Build xuất vào `dist/`.
Có thể dùng workflow **Build unsigned IPA** trên GitHub sau khi mã nguồn đã được push;
chọn đúng branch chứa thay đổi, giữ `run_tests = true`, kiểm tra cả job unit test và build.
Tải IPA trong **Artifacts** của đúng lần chạy, không nhầm bản release cũ.
IPA unsigned cần ký lại bằng công cụ sideload phù hợp; xem [INSTALL.md](INSTALL.md).

### Checklist trên iPhone thật (chưa được xác minh trong môi trường Linux)

- Cấp quyền lần đầu khi HUD đang mở → GPS tiếp tục cập nhật mà không phải mở lại màn hình.
- Từ chối quyền → hiện nút mở Cài đặt, không còn tốc độ/giới hạn cũ.
- GPS yếu hoặc mất mẫu trên 10 giây → hiện `—`, các cảnh báo cũ biến mất.
- Khoá máy/ra nền/quay lại → không tiếp tục dùng số tốc độ cũ.
- Xoay ngang trên iPhone nhỏ; thử cỡ chữ trợ năng và VoiceOver.
- Tắt mạng sau khi giọng Việt đã tải → xác minh cảnh báo dữ liệu cục bộ và âm thanh.
- Kiểm tra vượt tốc/camera bằng mô phỏng vị trí hoặc người ngồi ghế phụ, không thao tác khi lái.
- Thoát HUD → máy trở lại chế độ tự khoá trước đó; điều hướng đang chạy không bị dừng GPS.

## Dữ liệu và quyền phân phối

Nguồn tham chiếu: <https://github.com/911273/VietHUD>. Thay đổi này không tải thêm dữ liệu
hoặc sao chép firmware; sử dụng bộ dữ liệu Speedmap đã có trong repository.
Trước khi phát hành thương mại hoặc phân phối lại IPA chứa dữ liệu, cần xác minh quyền sử dụng
với chủ sở hữu VietHUD và các nguồn dữ liệu gốc, đồng thời giữ thông tin attribution thích hợp.
Không mặc định rằng repository công khai đồng nghĩa với quyền phân phối lại.

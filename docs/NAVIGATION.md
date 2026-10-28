# Dẫn đường 2D / 3D theo thời gian thực

Tài liệu này mô tả cách bản đồ hoạt động khi bạn bấm **Bắt đầu** — camera, hướng xoay,
mức phóng to, thanh tiến độ và các nút điều khiển.

---

## 1. Camera bám vị trí

Khi bật dẫn đường, app chuyển sang **camera bám theo xe**:

| Chế độ | Mô tả | Khi nào dùng |
|---|---|---|
| **3D** (mặc định) | Nghiêng 55°, xoay theo hướng đi, nhìn về phía trước | Đi xe máy / ô tô |
| **2D** | Nhìn từ trên xuống, hướng bắc luôn ở trên | Đi bộ, hoặc khi muốn nhìn rõ ngã rẽ |

Đổi nhanh bằng nút `view.3d` / `map` ở cột nút bên phải khi đang dẫn đường, hoặc tắt hẳn
trong **Cài đặt → Bản đồ → Bản đồ 3D khi dẫn đường**.

### Công thức khoảng cách camera

```
d = clamp(150 + v_kmh × 4,2 ; 180 m ; 900 m)
```

- Đứng yên / đi chậm (0–10 km/h): ~180 m — thấy rõ ngõ nhỏ.
- 30 km/h: ~276 m.
- 60 km/h: ~402 m.
- ≥ 180 km/h: 900 m (trần).

Hướng đi lấy từ `CLLocation.course`, được **làm mượt** để GPS nhiễu không làm bản đồ giật:

- Lệch ≤ 60°: xoay 55% quãng đường mỗi lần cập nhật.
- Lệch > 60° (rẽ gấp hoặc GPS nhảy): chỉ xoay 35% để tránh quay ngược bản đồ.

### Tần suất cập nhật

Camera chỉ được đặt lại khi thật sự cần:

- di chuyển > **5 m**, hoặc
- hướng đổi > **4°**, hoặc
- khoảng cách đổi > 15% (hoặc 40 m), hoặc
- đổi chế độ 2D/3D hoặc bấm "bám lại".

Nhờ vậy pin và CPU không bị đốt bởi hàng trăm lần `setCamera` mỗi phút.

---

## 2. Kéo bản đồ để xem trước

- Vuốt / zoom bằng tay → app **tự tạm dừng bám theo** (giống Apple Maps).
- Nút **mũi tên** (`location.north.fill`) hiện ra ngay khi camera ngừng bám; bấm để về lại.
- Bấm nút 3D/2D cũng tự bám lại.
- Khi ngừng dẫn đường, các nút "toàn tuyến", "vị trí của tôi", "đổi kiểu bản đồ" trở lại
  như chế độ duyệt bản đồ bình thường.

Cài đặt **Cài đặt → Bản đồ → Tự bám theo vị trí khi bắt đầu** quyết định app có tự bám ngay
khi bấm Bắt đầu hay không (mặc định bật).

---

## 3. Banner chỉ dẫn

Khi đang dẫn đường, thanh trên cùng hiển thị:

1. **Khoảng cách tới ngã rẽ kế tiếp** (cỡ lớn) + câu chỉ dẫn hiện tại.
2. Dòng "Sau đó: …" cho bước kế tiếp.
3. Hàng số liệu: **còn bao xa**, **còn bao lâu**, **giờ tới nơi** (ví dụ `14:35`), biển giới
   hạn tốc độ hiện tại.
4. **Thanh tiến độ** chuyến đi (đã đi / tổng quãng đường).

Các số này cập nhật theo GPS thật:

```
remainingDistance = tổng chiều dài tuyến − vị trí chiếu trên tuyến
remainingTime     = thời gian dự kiến × (remainingDistance / tổng chiều dài)
arrival           = bây giờ + remainingTime
```

Thẻ tuyến ngoài bản đồ cũng hiện giờ tới nơi dự kiến trước khi bạn bấm Bắt đầu.

---

## 4. Thanh tốc độ & cảnh báo trên màn hình chính

Từ 2.2 **không còn HUD toàn màn hình** — mọi thứ cần nhìn khi lái nằm ngay trên bản đồ:

- **Thanh trạng thái** ở đáy màn hình (chỉ hiện khi đã có tuyến hoặc đang dẫn đường):
  tốc độ hiện tại (đổi màu đỏ khi vượt ngưỡng), biển giới hạn tốc độ kiểu P.127 +
  nguồn (biển báo / vùng / OSM / bảng TT 38/2024), và **2 cảnh báo gần nhất** kèm khoảng
  cách, tô màu theo mức nguy hiểm (`xanh → vàng → cam → đỏ`).
- **Biển báo và camera nằm trực tiếp trên bản đồ** dưới dạng marker/nhãn ruột (glyph + số
  km/h), phóng to khi tới gần; bấm vào marker để xem chi tiết. Marker **đổi màu tại chỗ**
  (xám → màu loại → cam → đỏ) theo mức nguy hiểm, không xoá/thêm lại nên bản đồ không nháy.
- **Chưa chọn tuyến vẫn thấy cảnh báo**: app tự nạp cảnh báo trong bán kính 2,5 km và tải lại
  sau 45 giây hoặc khi bạn đi xa hơn 400 m.
- **Băng cảnh báo** hiện phía trên khi cảnh báo kế tiếp đã vào ngưỡng `D_warn`.
- Khoảng cách ước tính cập nhật theo tốc độ thật, không cần mở màn hình phụ.

Nút `view.3d` / `map` trên mép phải đổi **3D ↔ 2D bất cứ lúc nào** (cả khi chỉ xem bản đồ
lẫn khi đang dẫn đường); lựa chọn được nhớ trong Cài đặt.

---

## 5. Tự phục hồi khi đi lệch & tới nơi

- **Lệch tuyến**: nếu vị trí cách tuyến > 60 m liên tiếp 3 lần cập nhật (và đã quá 25 giây
  kể từ lần tính lại trước), app tự tính lại tuyến từ chỗ đang đứng, giữ nguyên chế độ dẫn
  đường và camera, rồi hiện thông báo *“Đã tính lại tuyến theo vị trí hiện tại”*.
- **Tới nơi**: khi còn ≤ 45 m tới điểm đến, app đọc *“Đã đến nơi.”*, hiện tên điểm đến và tự
  kết thúc dẫn đường.
- **Rung cảnh báo**: vừa vượt quá tốc độ cho phép → rung nhẹ kiểu `warning` (không rung lặp
  lại cho tới khi bạn giảm xuống dưới ngưỡng).

## 6. Câu đọc khi rẽ

Ngoài cảnh báo camera/tốc độ, app đọc cả chỉ dẫn rẽ:

- Còn > 40 m: *“Sau 300 m, rẽ phải vào Đường Láng.”*
- Còn ≤ 40 m: *“Rẽ phải vào Đường Láng.”*

Giọng đọc dùng `AVSpeechSynthesizer` với `vi-VN`, chạy **offline**, có cooldown để không
nói lặp.

---

## 7. Vì sao không có bản đồ vector riêng?

App dùng **MapKit** (Apple Maps) làm nền bản đồ: miễn phí, không cần API key, có ảnh vệ tinh,
giao thông trực tiếp và dựng nhà 3D. Nhờ vậy bản IPA chỉ ~3,5 MB và không phụ thuộc máy chủ
bên thứ ba. Tuyến xe máy chính xác hơn có thể bật bằng **VietMap Route v4** (tuỳ chọn, có gói
miễn phí) — xem [README](../README.md#-cấu-hình-xe-máy-vietmap).

---

## 8. Sự cố thường gặp

| Hiện tượng | Nguyên nhân | Cách xử lý |
|---|---|---|
| Bản đồ không xoay | Thiết bị không báo hướng (`course < 0`), thường do đứng yên | Đi thêm vài chục mét; kiểm tra la bàn trong app La bàn |
| Camera nhảy liên tục | GPS trong nhà / hầm | Ra ngoài trời, bật Wi-Fi để định vị phụ |
| Bản đồ không bám lại | Bạn vừa kéo bản đồ | Bấm nút mũi tên `location.north.fill` |
| Không thấy 3D | Đang ở chế độ 2D | Bấm nút `view.3d` hoặc bật trong Cài đặt |
| Tự tính lại tuyến liên tục | GPS sai số lớn hoặc đường mới chưa có trên bản đồ | Đi chậm lại; app giới hạn 1 lần/25 giây để không lặp |
| Tốn pin | Màn hình sáng + GPS + 3D | Giảm độ sáng, chuyển 2D bằng nút `map` |

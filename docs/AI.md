# 🤖 Trợ lý AI tìm tuyến (2.2)

AI trong app **không tự vẽ đường**. Nó chỉ làm ba việc: **hiểu câu tiếng Việt**,
**so sánh các phương án tuyến** và **viết lời giải thích**. Toạ độ, đường đi và thời gian
luôn do Apple Maps (MapKit) hoặc VietMap Route v4 tính — nên AI không thể bịa ra con đường
không tồn tại.

```
Câu người dùng
      │
      ▼
┌──────────────────┐   JSON ý định    ┌──────────────────┐   MKLocalSearch   ┌────────────────┐
│ AIClient + prompt│ ───────────────► │ RouteIntentParser│ ────────────────► │ Place (lat/lng)│
│ (Ckey.vn/OpenAI) │                  │  + chuẩn hoá     │                   │ thật từ MapKit │
└──────────────────┘                  └──────────────────┘                   └────────────────┘
      │ (không có key → dùng bộ phân tích offline ngay tại bước này)
      ▼
┌──────────────────┐   chọn 1 tuyến   ┌──────────────────┐
│ MKDirections /   │ ───────────────► │ AIRoutePlanner   │ → RouteSheet + bản đồ + giọng đọc
│ VietMap Route v4 │  nhiều phương án │  chooseRoute     │
└──────────────────┘                  └──────────────────┘
```

---

## 1. Nhà cung cấp & base URL

App dùng chuẩn **OpenAI Chat Completions**: `POST {base}/chat/completions` với header
`Authorization: Bearer <key>`.

| Trường | Mặc định | Ghi chú |
|---|---|---|
| Base URL | `https://api.xah.io/v1` | **Ckey.vn** (nhà cung cấp bạn chỉ định) |
| Model | `gpt-4o-mini` | đổi được, ví dụ `gpt-4.1-mini`, `qwen2.5`… |
| Temperature | `0.2` | thấp để dẫn đường chính xác |
| Bật AI | bật | tắt → app chạy hoàn toàn offline |
| Can thiệp sâu | bật | cho AI chọn tuyến / thêm điểm dừng |

Preset có sẵn trong **Cài đặt → Trợ lý AI**: Ckey.vn, OpenAI, Groq, OpenRouter,
Ollama (`http://192.168.1.10:11434/v1`), LM Studio (`http://192.168.1.10:1234/v1`).
Bạn cũng có thể gõ **bất kỳ base URL** nào khác.

Chuẩn hoá URL (`AIClient.chatCompletionsURL`):

| Bạn nhập | App gọi |
|---|---|
| `api.xah.io/v1` | `https://api.xah.io/v1/chat/completions` |
| `https://api.xah.io/v1/` | `https://api.xah.io/v1/chat/completions` |
| `https://api.xah.io/v1/chat/completions` | giữ nguyên (không nhân đôi path) |
| `http://192.168.1.10:11434/v1` | `http://192.168.1.10:11434/v1/chat/completions` |

- **Key** lưu trong **Keychain** (`ai.api.key`), không vào `UserDefaults`, không vào repo,
  không ghi log. Base URL / model / temperature lưu trong `UserDefaults`.
- HTTP trong LAN được bật (`NSAllowsLocalNetworking` + `NSLocalNetworkUsageDescription`)
  để dùng Ollama/LM Studio trong nhà.
- Nút **Kiểm tra kết nối** gửi một câu cực ngắn và in đúng lỗi (401 key sai, 404 sai base
  URL, timeout, hết quota…) bằng tiếng Việt.

---

## 2. Ba prompt

| Prompt | Vào | Ra |
|---|---|---|
| **Hiểu câu lệnh** (`intentPrompt`) | câu người dùng + vị trí hiện tại + vùng bản đồ | JSON `AIIntent` |
| **Chọn tuyến** (`rankPrompt`) | bảng số liệu từng tuyến + mức ưu tiên + cảnh báo | `route_index`, `reason`, `warnings[]` |
| **Điểm dừng** (`stopPrompt`) | độ dài tuyến, thời gian, danh mục có sẵn | `stops[]`, `positions[]` |
| **Nhận xét** (`narratePrompt`) | tuyến đã chọn + điểm 0–100 + cảnh báo | 2–4 câu tiếng Việt |

Schema `AIIntent` (mọi trường đều tuỳ chọn):

```json
{
  "origin": "Cầu Giấy",
  "destination": "Hồ Hoàn Kiếm",
  "waypoints": ["Hồ Tây"],
  "mode": "motorcycle",
  "avoid": ["highway", "congestion", "ferry", "cameras"],
  "preference": "fewestCameras",
  "depart_after": "8 giờ",
  "explanation": "Đi đường Trần Duy Hưng cho ít camera",
  "needs_clarification": false,
  "question": null
}
```

Bộ đọc JSON (`AIClient.decodeJSON`) chấp nhận phản hồi "bẩn": có ```json fence, có lời dẫn
trước/sau, tên trường thay thế (`from/to/via/stops/transport/travel_mode/goal`) — model nhỏ
trả lời lệch một chút vẫn dùng được.

---

## 3. AI can thiệp sâu

Khi bật **Can thiệp sâu** (`aiDeepPlanning`), sau khi có ≥ 2 phương án tuyến:

1. `MapViewModel` gửi bảng số liệu: quãng đường, thời gian, số camera, % cao tốc, phí cầu
   đường, số bước rẽ, điểm 0–100, mức ưu tiên.
2. AI trả `route_index` + lý do; app **chọn đúng tuyến đó** (`selectedRouteID`), vẽ lại và
   đọc nhận xét.
3. AI được phép thêm **điểm dừng** (`planStopsWithAI`) và **đổi phương tiện/mức ưu tiên** —
   nhưng chỉ qua các API có sẵn của app (`insertWaypoint`, `setPreference`, `changeMode`).

Người dùng vẫn kiểm soát: trong **sheet Chỉ đường → Điểm dừng dọc đường** có thể bấm
**＋** để thêm một gợi ý vào tuyến hoặc **✕** để bỏ điểm dừng AI vừa thêm; tuyến được tính
lại ngay (`insertWaypoint` / `removeWaypoint`).

Chốt an toàn (không phụ thuộc AI):

- `route_index` phải tồn tại, nếu không → bỏ qua và dùng mức ưu tiên offline.
- Xe máy + tuyến có > 5 % cao tốc → luôn thêm cảnh báo
  `SpeedLimitRules.motorcycleExpresswayNotice` dù AI nói gì.
- Điểm dừng chỉ được chọn trong danh sách địa điểm MapKit trả về, không nhận toạ độ từ AI.

---

## 4. Phương án khi không có AI

Đây là yêu cầu bắt buộc: **app phải dùng được khi không có key, không có mạng, hoặc AI lỗi**.

- `RouteIntentParser` là bộ phân tích tiếng Việt **trên máy**: nhận phương tiện
  (`xe máy`, `ô tô`, `đi bộ`, `xe buýt`), `từ … đến …`, `ghé …`, giờ đi (`lúc 8 giờ`),
  ý tránh (`cao tốc`, `kẹt xe`, `phà`, `camera`) và mức ưu tiên.
- `MapViewModel.preferredRouteID(in:)` xếp hạng tuyến theo mức ưu tiên + điểm 0–100
  (thuần offline, không mạng).
- `RouteInsight` soạn nhận xét từ số liệu thật.
- Khi AI lỗi giữa chừng, app **không chặn người dùng**: vẫn lập kế hoạch bằng offline và
  ghi chú `notice` vào bong bóng chat (*“AI không phản hồi, đã dùng bộ phân tích trên máy”*).

Bảng đối chiếu:

| Tình huống | Hiểu câu lệnh | Chọn tuyến | Nhận xét |
|---|---|---|---|
| Có key | AI | AI (`route_index`) | AI |
| Không key / tắt AI | offline | offline (mức ưu tiên + điểm) | offline |
| Có key nhưng mất mạng | offline | offline | offline |
| AI trả JSON hỏng | offline | offline | offline |

---

## 5. Mức ưu tiên tuyến

`RoutePreference` dùng chung cho AI, bộ chấm điểm và giao diện:

| Mức | Ý nghĩa |
|---|---|
| `fastest` | tổng thời gian ngắn nhất |
| `fewestCameras` | ít camera phạt nguội, chấp nhận chậm hơn |
| `avoidHighway` | không đi cao tốc (bắt buộc với xe máy) |
| `easiest` | ít rẽ, ít cao tốc, dễ đi với người mới |

Đổi mức ưu tiên trong **sheet Chỉ đường → ƯU TIÊN TUYẾN** sẽ chọn lại tuyến và (nếu có AI)
hỏi lại AI một lần.

---

## 6. Quyền riêng tư

- Chỉ gửi **câu chữ + tên địa điểm/số liệu tuyến** tới nhà cung cấp bạn chọn.
- **Không** gửi toạ độ GPS thô, danh bạ, lịch sử khác.
- Không có máy chủ của tác giả app; không telemetry.
- Muốn không gửi gì đi: tắt AI, hoặc trỏ base URL vào model chạy trong LAN (Ollama).

## 7. Kiểm thử

```bash
./scripts/selfcheck.sh          # cú pháp + plist + dữ liệu
# CI: job unit-tests chạy App/Tests/AITests.swift trên Simulator
```

`AITests` phủ: dựng/chuẩn hoá base URL (4 kiểu nhập), `AIConfig.isConfigured/needsKey`,
đọc JSON có fence và có ngoặc trong chuỗi, decode `AIIntent` với tên trường thay thế,
và bộ phân tích offline với 4 câu tiếng Việt thật.

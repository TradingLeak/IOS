# 🤖 Tích hợp AI (model & base URL tuỳ chỉnh)

App dùng API **tương thích OpenAI** nên đổi nhà cung cấp chỉ cần đổi `base URL` + `model`.

## 1. Luồng xử lý

```
Người dùng: "đi từ Cầu Giấy đến Hồ Tây, tránh đường đông"
        │
        ▼
① AIClient.chat()            POST {base_url}/chat/completions   (system prompt + câu người dùng)
        │
        ▼
② AIRoutePlanner.decodeIntent()   bóc JSON → AIIntent
   { "origin": "Cầu Giấy", "destination": "Hồ Tây", "mode": "automobile",
     "waypoints": [], "avoid": ["đường đông"], "explanation": "..." }
        │
        ▼
③ SearchService (MapKit)     tên địa danh → toạ độ thật (MKLocalSearch, thiên vị VN)
        │
        ▼
④ DirectionsService          MKDirections tính tuyến thật, lấy polyline + các bước rẽ
        │
        ▼
⑤ AIRoutePlanner.summarize()  AI viết 2–3 câu nhận xét lộ trình (có fallback tiếng Việt)
```

**AI không tự vẽ đường.** Nó chỉ chuyển ngôn ngữ tự nhiên thành ý định; tuyến đường do
Apple Maps tính để đảm bảo đúng đường thực tế và có turn-by-turn.

## 2. Cấu hình

| Trường | Mặc định | Ghi chú |
|---|---|---|
| Base URL | `https://api.xah.io/v1` (ckey.vn) | Tự thêm `/chat/completions`; chấp nhận cả URL đầy đủ |
| Model | `gpt-4o-mini` | Đổi theo model bạn mua |
| API key | trống | Lưu Keychain, hoặc nhúng lúc build qua secret `AI_API_KEY` |
| Temperature | 0.2 | Thanh trượt trong Cài đặt |

Chuẩn hoá URL (đã có test):

```
https://api.xah.io/v1        → https://api.xah.io/v1/chat/completions
https://api.xah.io/v1/       → https://api.xah.io/v1/chat/completions
api.xah.io/v1                → https://api.xah.io/v1/chat/completions   (tự thêm https)
http://192.168.1.10:11434/v1 → http://192.168.1.10:11434/v1/chat/completions (Ollama LAN)
https://.../v1/chat/completions → giữ nguyên
```

## 3. Request / response

**Request** (`AIClient.chat`):

```json
{
  "model": "gpt-4o-mini",
  "messages": [
    {"role": "system", "content": "<system prompt ở dưới>"},
    {"role": "user", "content": "đi từ Cầu Giấy đến Hồ Tây"}
  ],
  "temperature": 0.2,
  "stream": false
}
```

Header: `Content-Type: application/json`, `Authorization: Bearer <key>`.

**Response** — app đọc được nhiều biến thể:

| Dạng | Ví dụ |
|---|---|
| Chuẩn | `choices[0].message.content` |
| Content dạng mảng | `choices[0].message.content = [{"type":"text","text":"…"}]` |
| Model reasoning | `choices[0].message.reasoning_content` |
| Legacy | `choices[0].text` |
| Gateway khác | `response` hoặc `content` ở gốc JSON |

## 4. Schema JSON của ý định

```json
{
  "origin": "string | null",
  "destination": "string | null",
  "waypoints": ["string"],
  "mode": "automobile | walking | transit | null",
  "avoid": ["đường đông", "cao tốc", "phà"],
  "explanation": "một câu ngắn"
}
```

Bộ giải mã `AIIntent` chấp nhận cả khoá thay thế: `from/to`, `start/end`, `via/stops`,
`transport/travel_mode`, `note/reason/summary`. Giá trị `"null"`, `"nil"` được coi là rỗng.
Nếu model trả markdown ```json … ``` thì `AIClient.extractJSONObject` tự bóc.

## 5. Prompt (rút gọn)

System prompt (`AIRoutePlanner.systemPrompt`) nói rõ: chỉ trả JSON, giữ đúng dấu tiếng Việt,
không bịa địa danh, map từ ngữ phương tiện ("xe máy"→automobile, "đi bộ"/"xe đạp"→walking,
"xe buýt"/"tàu"→transit), đưa yêu cầu tránh đường vào `avoid`, `explanation` < 25 từ.

Prompt tóm tắt (`summaryPrompt`) yêu cầu 2–3 câu tiếng Việt, không bịa số liệu, tối đa 60 từ,
dựa trên số liệu thật (quãng đường, thời gian, số bước, advisory của Maps).

Sửa prompt: `App/Sources/Services/AIRoutePlanner.swift`.

## 6. Khi AI lỗi — app vẫn chạy

| Tình huống | Hành vi |
|---|---|
| Chưa có API key | Dùng `RouteIntentParser` (offline) — hiểu "từ A đến B", "đi bộ", "xe buýt", "tránh đường đông", "ghé X" |
| AI trả JSON hỏng | Gọi lại 1 lần với yêu cầu "chỉ trả JSON"; vẫn hỏng → parser offline |
| Mạng lỗi / 429 / hết quota | parser offline, kèm thông báo lỗi trong khung chat |
| Tuyến không tồn tại (vd xe buýt ở tỉnh lẻ) | báo rõ "Apple Maps chưa có dữ liệu xe buýt cho tuyến này" |
| Tóm tắt lỗi | dùng mẫu tiếng Việt `AIRoutePlanner.localSummary` |

## 7. Đổi nhà cung cấp

| Nhà cung cấp | Base URL | Model ví dụ |
|---|---|---|
| **ckey.vn** | `https://api.xah.io/v1` | `gpt-4o-mini`, `claude-sonnet-4-5`, `gemini-2.5-flash` |
| OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` |
| Groq | `https://api.groq.com/openai/v1` | `llama-3.3-70b-versatile` |
| OpenRouter | `https://openrouter.ai/api/v1` | `openai/gpt-4o-mini` |
| Ollama (máy LAN) | `http://<ip>:11434/v1` | `qwen2.5` (key để trống không dùng được — nhập chuỗi bất kỳ) |

Trong app: **Cài đặt → Cấu hình nhanh** có sẵn 4 preset.

## 8. Bảo mật

- Key lưu trong **Keychain** (`kSecAttrAccessibleAfterFirstUnlock`), không vào UserDefaults,
  không vào repo, không in ra log.
- Chỉ **nội dung câu bạn gõ** được gửi tới máy chủ AI; toạ độ/vị trí không gửi.
- Nhúng key qua `AI_API_KEY` chỉ nên dùng cho bản build cá nhân: repo public thì key nằm
  trong IPA phát hành và có thể bị trích ra.
- App dùng HTTP cho Ollama trong LAN; mặc định các provider khác đều HTTPS.

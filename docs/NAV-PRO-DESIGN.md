# 🚀 Thiết kế ứng dụng chỉ đường VietMap Pro

> **Tài liệu thiết kế phần mềm** — bản 1.0 (2026-10-28)
> Tác giả: Kỹ sư thiết kế phần mềm iOS (Arena agent) · nhánh `arena/12b5ae4c-ios`
>
> Mục tiêu: nâng VietMap từ "app chỉ đường MapKit + AI" thành **ứng dụng chỉ đường
> chuyên nghiệp, offline-first, phong cách tương lai (SpaceX)** — bản đồ OSM tải offline,
> tìm/tính tuyến thông minh nhờ AI (ckey.vn), và **cảnh báo biển báo/camera trực tiếp trên
> màn hình** từ 7 file `.bin` speedmap đã tải.

---

## 1. Tổng quan & tầm nhìn

### 1.1 Nguyên tắc thiết kế

| Nguyên tắc | Ý nghĩa thực thi |
|---|---|
| **Offline-first** | Bản đồ, tra cứu, tính tuyến, cảnh báo biển báo đều chạy được khi mất mạng. AI & dịch vụ online chỉ là lớp tăng cường. |
| **An toàn khi lái** | Cảnh báo to, rõ, bằng giây — lái xe chỉ cần liếc 0.3s. Tối giản thao tác, ưu tiên giọng nói. |
| **Tương lai – "SpaceX"** | Dark-first, đơn sắc + màu tín hiệu, đường hairline, chữ số mono, hiệu ứng glow nhẹ, chuyển động mượt. |
| **AI là trợ lý, không là trung tâm** | AI hiểu câu tiếng Việt, chấm điểm tuyến, tóm tắt — nhưng **không bao giờ chặn luồng chính** (có fallback rule-based). |
| **Dữ liệu có nguồn & chữ ký** | OSM (ODbL) + speedmap VietHUD — kiểm tra CRC/SHA-256/chữ ký ECDSA trước khi dùng. |

### 1.2 Ma trận tính năng (hiện tại → mục tiêu)

| Năng suất | Hiện tại (repo) | VietMap Pro |
|---|---|---|
| Bản đồ | Apple MapKit (online) | + **Vector OSM offline** (MapLibre) phong cách Orbital-dark |
| Tìm địa điểm | MKLocalSearch (online) | + **FTS5 offline** + gợi ý theo vùng, tên đường từ `names.bin` |
| Tính tuyến | MKDirections (online) | Phase 3: **Valhalla offline** (A* chi phí thực) |
| AI | ckey.vn (OpenAI-compat), tóm tắt tuyến, parse ý định | + Intent dạng JSON có schema, function-calling, chấm điểm tuyến, coach an toàn |
| Cảnh báo biển báo/camera | ❌ | ✅ **7 file speedmap `.bin` → HUD overlay trực tiếp** (Milestone P0, code trong PR này) |
| Chỉ đường (nav) | Banner từng bước cơ bản | + Reroute, voice tiếng Việt, background, lane guidance |
| Cập nhật dữ liệu | ❌ | + OTA `manifest.txt` (ECDSA P-256 + SHA-256), tải vùng theo yêu cầu |

---

## 2. Kiến trúc tổng thể

### 2.1 Sơ đồ lớp

```
┌────────────────────────────────────────────────────────────────────────┐
│                           UI LAYER (SwiftUI)                           │
│  SpaceX design system: Theme · Components · SpeedHudOverlay · Sheets   │
├────────────────────────────────────────────────────────────────────────┤
│                        PRESENTATION (MVVM + State)                     │
│   MapViewModel ── NavigationSession(state machine) ── SpeedmapController│
├──────────────┬───────────────────┬──────────────────┬──────────────────┤
│  Map/Render  │   Route/Search    │   AI Copilot     │  Hazard/Alert     │
│ MapKit (P0)  │ DirectionsService │ AIClient         │ SpeedmapDatabase  │
│ MapLibre(P2) │ SearchService     │ RouteIntentParser│  ├ metadata/index │
│              │ AIRoutePlanner    │ (ckey.vn/OPENAI) │  ├ tiles (LRU)    │
│              │ [P3 Valhalla]     │                  │  ├ cameras/signs  │
│              │ [P3 SQLite FTS5]  │                  │  └ names/seg_names│
├──────────────┴───────────────────┴──────────────────┴──────────────────┤
│                              DATA LAYER                                │
│  Bundle: speedmap/*.bin (8MB) · MBTiles (P2) · Valhalla tiles (P3)     │
│  Documents/: vùng tải ngoại tuyến · Keychain: API key · UserDefaults   │
└────────────────────────────────────────────────────────────────────────┘
         ▲ CLLocation (1–2 Hz)          │ OpenAI-compat HTTP
         └──────────────────────────────┴──► ckey.vn (https://api.xah.io/v1)
```

### 2.3 Map module → file trong repo

| Module | File | Trạng thái |
|---|---|---|
| Design tokens (hiện tại) | `App/Sources/Design/Theme.swift`, `Components.swift` | ✅ có |
| **Design tokens SpaceX** | `App/Sources/Design/SpaceXTheme.swift` | ✅ **Mới (P0)** |
| **Speedmap binary format** | `App/Sources/Speedmap/SpeedmapFormat.swift` | ✅ **Mới (P0)** |
| **Speedmap DB + matcher** | `App/Sources/Speedmap/SpeedmapDatabase.swift` | ✅ **Mới (P0)** |
| **Alert/HUD engine** | `App/Sources/Speedmap/SpeedmapController.swift` | ✅ **Mới (P0)** |
| **HUD overlay UI** | `App/Sources/Views/SpeedHudOverlay.swift` | ✅ **Mới (P0)** |
| AI client + intent | `Services/AIClient.swift`, `RouteIntentParser.swift`, `AIRoutePlanner.swift` | ✅ có |
| Điều hướng | `MapViewModel` (nav banner) | ⬆️ P1: `NavigationSession` |
| Bản đồ offline | `MapContainer.swift` (MapKit) | ⬜ P2: `OfflineMapContainer` (MapLibre) |
| Router offline | — | ⬜ P3: `ValhallaRouter` |
| OTA updater | — | ⬜ P3: `SpeedmapUpdater` |

---

## 3. Bản đồ & tra cứu OSM offline

### 3.1 Chuỗi dữ liệu (pipeline phía server/PC — chạy 1 lần rồi publish)

```
Geofabrik extracts (vietnam-latest.osm.pbf, cập nhật hằng tuần)
   │  (hoặc phủ BẮC/TRUNG/NAM riêng để chia vùng tải)
   ▼
┌─────────────────────────┐     ┌──────────────────────────────┐
│ tilemaker / planetiler  │────►│ MBTiles vector (z0–z15)      │
│ + openmaptiles schema   │     │ lớp: water/road/building/…   │
└─────────────────────────┘     └──────────────────────────────┘
   │                                     │
   │  osmium extract + custom tags       │  valhalla_build_tiles
   ▼                                     ▼
┌─────────────────────────┐     ┌──────────────────────────────┐
│ FTS5 geocoding index    │     │ Valhalla graph tiles (.vlt)  │
│ (địa chỉ, tên đường,    │     │ + elevation (SRTM)           │
│  admin boundaries)      │     └──────────────────────────────┘
   └──────────────► CI ký SHA-256 + manifest ECDSA ◄─────────────┘
```

### 3.2 Chọn công nghệ & lý do

| Bài toán | Chọn | Lý do | Alternatives |
|---|---|---|---|
| Render offline | **MapLibre Native** (`maplibre-gl-native`, SPM) | Miễn phí, OSM vector native, style JSON tùy biến được phong cách SpaceX, iOS 12+ | MapKit (không offline), Mapbox (đóng phí) |
| Tính tuyến offline | **Valhalla** (XCFramework do CI build) | Chi phí thực (thời gian/độ dài/cao tốc/trạm thu phí), supports `preferred_side`, `location` costing options → dễ nối AI scoring | OSRM (ít option), GraphHopper (cần Java), tự viết A* (quá lớn) |
| Tìm kiếm offline | **SQLite FTS5** + quadtree admin | Chuẩn, nhanh, VN không dấu/không dấu đều match được | Meili/Typesense quá nặng |
| Tên đường | Dùng tiếp `names.bin` + `seg_names.bin` (6.052 tên, 182.242 đoạn) | Đã có, siêu nhẹ, tra O(1) | — |
| Online fallback | MapKit/MKDirections (đang dùng) | Không đổi gì khi chưa có dữ liệu vùng | — |

### 3.3 Chiến lược "tải offline khi sử dụng trên điện thoại"

1. **Bundle sẵn vùng lõi** (Hà Nội + TP.HCM ≈ 60–120MB compressed) — hoặc bundle `speedmap` 8MB cho P0.
2. **Settings → Bản đồ ngoại tuyến**: danh sách vùng (Bắc/TRung/Nam/TP…), dung lượng, tiến trình `URLSessionDownloadTask` → di chuyển vào `Documents/regions/<id>/mbtiles` (hỗ trợ resume).
3. Renderer ưu tiên **local MbTiles**; nếu vùng chưa tải → MapKit (P0–P1) hoặc fetch online raster tile (P2, có toggle).
4. **Cập nhật**: so `manifest` version → tải delta nếu server hỗ trợ, SHA-256 từng file, atomic replace (ghi `*.tmp` → rename), giữ 1 bản cũ để rollback.

### 3.4 Style bản đồ "Orbital" (dark, SpaceX-like) — phác thảo MapLibre style

```
background:        #0A0C10 (void)
water:             #10141C
building:          #14181F (outline #1A1F28)
road:motorway:     #E8ECF2 w=5 + glow #4DA3FF33
road:primary       #C9D1DB w=3.5
road:minor         #59626E w=2
route casing:      #000000AA w=8   →  route fill: #4DA3FF → #9A6BFF (gradient)
poi:               #FFFFFFCC (icon line 1.25pt)
text:              #E8ECF2 / dim #8A93A0, font: system rounded, halo #000000AA
```

---

## 4. HUD speedmap — tích hợp 7 file `.bin` (Milestone P0 ✅)

Nguồn: [911273/VietHUD/speedmap](https://github.com/911273/VietHUD/tree/main/speedmap) —
format là "wire contract" giữa `tools/map_builder/build_speedmap.py` (builder) và
firmware đọc file (`src/map/SpeedMapFormat.h`). **Đã xác minh toàn bộ bằng dữ liệu thật
trong repo (khớp 100% từng byte).**

### 4.1 Định dạng 7 file (little-endian, `#pragma pack(1)`, tọa độ = Int32 °×1e7)

| File | Header | Cấu trúc | Số liệu thật (bản 2026.09) |
|---|---|---|---|
| `metadata.bin` | — | 1 × `SpeedMapMetadata` = **140 B** | `SLMP` v2, region `VN-HN`, **3.437 tile**, **182.242 segment**, `tileSizeDeg=0.01°`, điểm tự-test `(21.0379748, 105.8611572)` head 247 road 1, `crc32(index.bin)=0x39FEC2B9` ✅ khớp |
| `index.bin` | — | `TileIndexEntry[3437]` × **28 B** = 96.236 B | `{tileId, minLatE7, maxLatE7, minLonE7, maxLonE7, fileOffset, fileSize}` |
| `tiles.bin` | — | `RoadSegment[]` **28 B**/đoạn, nối tiếp theo slice của index | 182.242 × 28 = 5.102.776 B ✅ |
| `cameras.bin` | — | `CameraPoint[]` **20 B**/điểm, phẳng, nạp cả vào RAM | 7.753 camera ✅ (`id` = OSM node id uint64) |
| `signs.bin` | `TrafficSignHeader` 20 B | `TrafficSignPoint[]` × **20 B** | `VNSG` v1, **100.917 biển báo** ✅ |
| `names.bin` | `RoadNamesHeaderV2` 16 B | `offsets:u32[count]` rồi `pool UTF-8` | `VNNM` v2, **6.052 tên**, pool 120.339 B (16+24.208+120.339=144.563 ✅) |
| `seg_names.bin` | không header | `u32[segmentCount+1]`, **1-based theo segId**, value = nameId (0 = không tên) | 182.243 × 4 = 728.972 B ✅ |

Cấu trúc con (đã map đúng offsets từ firmware):

```c
SpeedMapMetadata (140B):  magic[4]"SLMP" | u16 version | region[16] | mapVersion[16]
  | u64 buildTs | u32 tileCount | u32 segmentCount | f32 tileSizeDeg
  | i32 testLatE7 | i32 testLonE7 | i16 testHeadingDeg | u32 testRoadId
  | attribution[64] | u32 crc32(index.bin)

RoadSegment (28B):  u32 id | i32 sLat | i32 sLon | i32 eLat | i32 eLon | u16 headingDeg
  | u8 roadClass | u8 direction(0=both,1=fwd,2=bwd,3=?) | i16 speedLimitKmh(-1=unknown)
  | u8 speedSource | u8 flags(bit0 conditional, bit1 oneway, bit4 bridge…, bit5 no-vehicle)

CameraPoint (20B):  u64 osmId | i32 lat | i32 lon | i16 limitKmh(-1=unknown) | u16 directionDeg(0xFFFF=2 chiều)

TrafficSignHeader (20B): "VNSG" | u16 ver | u32 count | u16 res | u32 crc32 | u32 ts
TrafficSignPoint  (20B): u32 id | i32 lat | i32 lon | u16 dir(0xFFFF=omni)
  | u8 type(1=giới hạn,2=khu dân cư,3=cấm vượt,4=camera,5=trạm thu phí,6=đèn,10=nguy hiểm)
  | u8 limitKmh(0=none) | u8 subType(0=bắt đầu,1=kết thúc) | u8 flags | u16 res

RoadNamesHeaderV2 (16B): "VNNM" | u16 ver=2 | u32 nameCount | u32 poolBytes | u16 res
  → nameId (1-based): offset = offsets[nameId-1] → chuỗi NUL-terminated trong pool
```

### 4.2 Kiến trúc module (code P0 trong repo này)

```
SpeedmapFormat.swift ──── ByteCursor (LE, bounds-checked) + mọi struct model + CRC32
        │
SpeedmapDatabase.swift ── load/validate (magic, version, size, CRC32 index)
        │                   • tiles: parse slice theo index, LRU cache 256 tile
        │                   • signs: sort theo latE7 → binary search dải (O(log n)+band)
        │                   • matchRoad(): point-to-segment + heading + direction + oneway
        │                   • roadName(segId): seg_names → names (O(1))
        │
SpeedmapController.swift ─ engine 1–2 Hz: match đường hiện tại → lấy speed limit,
        │                   quét camera/biển trong tầm, lookahead đổi giới hạn tốc độ,
        │                   dedupe/pass-behind → @Published alerts (tối đa 3)
        │
SpeedHudOverlay.swift ──── UI card cảnh báo + biển báo giới hạn tốc độ + đồng hồ tốc độ
        │                   (theme SpaceXTheme.swift)
        ▼
MapScreen (nạp bundle, nhận CLLocation, hiển thị overlay trực tiếp trên bản đồ)
```

### 4.3 Thuật toán cốt lõi (ported từ firmware, tinh cho iPhone)

**① Khoảng cách cảnh báo động** (mọi loại camera & thay đổi giới hạn):

```
D_warn = clamp(v_kmh × 4.5, 100 m, 400 m)      // lead-time ~15s, cap 400m (user rule 2026-10-12)
```

**② Biển báo quy phạm** (khu dân cư, cấm vượt, thu phí, đèn): `D_sign = 350 m` cố định.

**③ Map-matching** (xác định "đang đi đường nào" → giới hạn tốc độ hiện hành):

```
score = distance(m) + min(headingError°, 90) × 0.35
  headingError theo direction segment:
    forward → diff(course, heading); backward → diff(course, heading+180);
    both → min(hai hướng)
  oneway && headingError > 90 → loại ngay (đang đi ngược)
  hysteresis: giữ segment cũ nếu dist không kém quá 4m (tránh nhảy số)
```

**④ Lookahead đổi giới hạn tốc độ**: mẫu 6 điểm cách đều trên quỹ đạo heading,
tới hạn D_warn, điểm đầu tiên `matchRoad` ra limit khác limit hiện tại → card
"Giới hạn 40 · sau ~180 m".

**⑤ Lọc trước/sau** (chống báo sai): item được hiện khi `dist ≤ D_warn` **và**
(`course → item` trong nón 70° **hoặc** `dist ≤ 45 m`); giữ card cho tới khi item
lui ra sau quá 40 m (chống chớp màn hình khi vừa vượt qua).

**⑥ Camera một chiều**: nếu `directionDeg ≠ 0xFFFF` → chỉ cảnh báo khi sai số hướng
với course ≤ 100° (hoặc gần đích <45m).

### 4.4 UX cảnh báo trên màn hình

```
┌──────────────────────────────────────┐
│  [chip khu vực…]                     │  ← header cũ giữ nguyên
│  ┌────────────────────────────────┐  │
│  │ 🎥  Camera phạt nguội      165 m│  │  ← card nổi, viền phát sáng màu kind,
│  └────────────────────────────────┘  │     số mono đậm, icon SF Symbols
│  ┌────────────────────────────────┐  │
│  │ ⚠   Cấm vượt               240 m│  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │ (40)  80 ⏱   GIỚI HẠN TỐC ĐỘ  │  │  ← badge tròn kiểu biển báo + tốc độ hiện tại
│  └────────────────────────────────┘  │
```

- Ưu tiên sắp theo **khoảng cách** (gần nhất trước), tối đa 3 card (không che bản đồ).
- Nhóm màu: 🔴 camera/cấm vượt · 🟠 giới hạn mới/thu phí · 🔵 khu dân cư/đèn · ⚪ nguy hiểm.
- Card tự ẩn khi qua mặt; hiện lại nếu U-turn (hysteresis 20 m).
- Âm thanh (P1): 1 chime ngắn "bíp" khi card mới + voice `AVSpeechSynthesizer` (`vi-VN`)
  *"Chú ý, camera phạt nguội 150 mét"* — thư viện MP3 có thể mượn từ `VietHUD/sounds/`.

### 4.5 Tính toàn vẹn & cập nhật dữ liệu

- **At load**: magic/size đúng như bảng → `crc32(index.bin)` khớp metadata → nếu sai: **từ chối tải** (fail-safe, HUD simply ẩn, không hiện sai).
- **OTA (P3)**: tái dùng chính pipeline VietHUD: `manifest.txt` (version + size + SHA-256 từng file) + `manifest.txt.sig` (**ECDSA P-256**) → app tải 7 file → verify → ghi原子 (tmp + rename) → giữ backup để rollback. Kho: `911273/VietHUD` (`raw.githubusercontent.com/.../speedmap/`).

---

## 5. AI tích hợp (ckey.vn) — "tìm & tính tuyến thông minh"

### 5.1 Cấu hình (đã có, giữ nguyên)

| Trường | Giá trị |
|---|---|
| Base URL | `https://api.xah.io/v1` (ckey.vn, chuẩn OpenAI) |
| Model | mặc định `gpt-4o-mini` — **đổi tự do trong Cài đặt** |
| Endpoint | `POST /chat/completions` (+ `response_format: json_object`) |
| Key | Keychain (`KeychainStore`), không log, không commit |

### 5.2 Vai trò AI theo tầng

```
(1) Hiểu ý định     RouteIntentParser/AIRoutePlanner (CÓ) → JSON {origin, dest, waypoints, mode, avoid}
(2) Chấm điểm tuyến  (P3) AI nhận danh sách 2–3 tuyến + tiêu chí → xếp hạng + giải thích
(3) Tóm tắt lộ trình  (CÓ) aiSummary 2–3 dòng tiếng Việt
(4) Tra cứu địa lý    (P3) function-calling: search_places(query, near), get_place(id)
(5) Coach an toàn     (P1) "Trên đường có camera trước 200m, giữ 60km/h" (dữ liệu từ speedmap, template, không cần AI)
```

### 5.3 Nguyên tắc "không bao giờ hỏng luồng chính"

1. Mọi call AI đặt trong `Task` + timeout 15s (nội tại), lỗi → fallback:
   - intent parse lỗi → rule-based parser (regex tiếng Việt) **đang có sẵn**;
   - summary lỗi → ẩn khối tóm tắt, tuyến vẫn hiện.
2. Prompt hệ thống (chuẩn hóa cho mọi tính năng):

```
Bạn là trợ lý điều hướng của VietMap (bản đồ Việt Nam). Trả lời JSON đúng schema.
Ưu tiên: tiếng Việt tự nhiên, số liệu chính xác, không bịa địa danh ngoài dữ liệu trả về.
Nếu thiếu thông tin → yêu cầu làm rõ tối đa 1 câu.
```

3. **Riêng tư**: không gửi vị trí nền; chỉ gửi tọa độ khi người dùng chủ động hỏi/tìm
   (đã là hành vi hiện tại của `AIRoutePlanner`).

### 5.4 Tính tuyến "thông minh như Google Maps"

**Tuyến (P0–P1, online)**: `MKDirections` đã có 3 chế độ + điểm dừng.
**Tuyến (P3, offline)**: Valhalla costing options — AI chọn "ngân sách" trước khi gọi router:

```json
{ "costing": "auto",
  "costing_options": { "auto": { "use_highways": "avoid|shortest|balanced",
                                 "use_tolls": "true|false", "use_ferry": false } },
  "locations": [...], "alternatives": 3 }
```

→ AI dịch câu *"tránh đường cao tốc và trạm thu phí"* thành costing options (rule + LLM),
không cần AI tính geometry (thay geometry là việc của router thật).

---

## 6. Thiết kế giao diện — "SpaceX / tương lai"

### 6.1 Design tokens (đã code: `SpaceXTheme.swift`)

| Token | Giá trị | Dùng cho |
|---|---|---|
| `void` | `#000000` | nền tối sâu |
| `panel` | black 78% + hairline `white 14%` | glass panel/HUD |
| `ink` / `inkDim` | `#FFFFFF` / `#FFFFFF99` | chữ chính / phụ |
| `signalRed` | `#FF3B30` | camera, cấm vượt, tốc độ vượt giới hạn |
| `signalAmber` | `#FF9F0A` | giới hạn sắp đổi, thu phí |
| `iceBlue` | `#8CC8FF` | khu dân cư, đèn, chỉ dẫn |
| `traceGreen` | `#32D74B` | trạng thái OK/tải xong |
| Type | hệ thống, `monospacedDigit` cho mọi số | tốc độ, khoảng cách, thời gian |
| Radius | panel 14–16, control 12 | nhất quán 8pt grid |
| Motion | 180–260 ms ease-out; card alert slide+fade | mượt, không "nhảy" |

### 6.2 Nguyên tắc component

- **Hairline + glow**: viền 1px trắng mờ, glow cùng màu tín hiệu radius 8–12 (không blur dày).
- **Glass**: `.ultraThinMaterial` trên nền đen 78% → đọc được trên mọi kiểu bản đồ.
- **Quyền lực thị giác**: biển giới hạn tốc độ = vòng đỏ 3pt trên nền trắng (chuẩn giao thông),
  đối lập hoàn toàn với dark theme → mắt bắt ngay.
- **Text hierarchy**: title 13 semibold · distance 19 bold mono · body 12–15.
- **Dark-first, light-fallback**: màu signal không đổi chế độ; panel trong suốt thích ứng.

### 6.3 Màn hình chính (skeleton)

```
MapScreen (root)
 ├─ Header: menu ☰ · search bar "Tìm địa điểm…" · bản đồ
 ├─ Chips danh mục (giữ)
 ├─ [P0] SpeedHudOverlay: alert cards + speed/limit badge
 ├─ NavigationBanner (đang chỉ đường)
 ├─ Map (MapKit → MapLibre P2) + route polylines glow
 ├─ Side controls: vị trí · fit · giao thông · AI
 └─ Bottom: routeCard / actionBar (Trợ lý AI · Chỉ đường)

Sheets: Search · Route(2 tuyến) · AI · Settings · Favorites · Cities
        [+ P2: Offline Maps (quản lý vùng tải)]
```

### 6.4 Accessibility & an toàn

- Card cảnh báo ≥ 44pt cao, không cần tap (chỉ đọc).
- Dynamic Type: số khoảng cách scale theo `body` (test với x2).
- VoiceOver: card phát "Camera phạt nguội, 165 mét" (label đầy đủ).
- Không dùng riêng màu để phân loại (kèm icon + chữ).

---

## 7. Điều hướng (Navigation session) — P1

### 7.1 State machine

```
idle ──chọn tuyến──► preview ──Bắt đầu──► navigating ──đến nơi──► arrived
                        ▲                    │  │
                        │     off-route (>25m / 3s) → rerouting ─┐
                        └────── tuyến mới ◄──────────────────────┘
navigating ──Kết thúc──► idle        (rerouting throttle: tối đa 1 lần / 15s)
```

### 7.2 Thành phần

| Thành phần | Thiết kế |
|---|---|
| Vị trí | `CLLocation` 1–3m filter khi nav (`setNavigationMode(true)` ✅ đã thêm), `course` làm heading |
| Snap-to-route | проjection điểm gần nhất trên polyline; >25m trong 3s → off-route |
| Turn instruction | tính từ bearing delta giữa 2 chặng polyline (offline) / dùng `MKRouteStep` (online) |
| Voice | `AVSpeechSynthesizer` voice `vi-VN`, rate ~0.48; priority queue: reroute > cảnh báo > bước tiếp |
| Background | P1: `UIBackgroundModes: location` + `allowsBackgroundLocationUpdates` (chỉ khi đang nav) |
| Dashboard lock | P2: màn hình khóa kính chiếu hậu (orientation .landscape), giảm chi tiết, to số |

## 8. Performance, an toàn, riêng tư

| Hạng mục | Ngân sách |
|---|---|
| Cold start → map render | < 1.2 s (P0: nạp speedmap nền, không chặn) |
| Speedmap RAM | ≈ 10–15 MB (signs 2MB + tiles cache 256 tile ~1MB + index) |
| Tick HUD | 1–2 Hz, mỗi tick < 2 ms (tile cache hit; band search O(log n)) |
| GPS khi nav | 3 m filter; không nav: 8 m (đã code) |
| Pin | theo dõi qua `ProcessInfo.thermalState`; P1: giảm sample khi battery < 20% & không nav |
| Quyền | `NSLocationWhenInUseUsageDescription` ✅ · P1 thêm Always + background khi người dùng bật "chỉ đường nền" |
| Riêng tư | 100% khảo sát biển báo **offline**; AI opt-in; key trong Keychain; không analytics bên thứ 3 |
| Dữ liệu | ODbL attribution hiển thị trong Settings/About (lấy từ `metadata.attribution` ✅) |

## 9. Testing & CI

| Lớp | Công cụ | Trạng thái |
|---|---|---|
| Lint/repo health | `scripts/selfcheck.sh` (ubuntu CI) | ✅ |
| Unit test | XCTest trên Simulator (macos-15 CI) | ✅ |
| **Speedmap fixture** | file `.bin` tổng hợp tự build trong test (metadata/index/tiles/cameras/signs/names/seg_names) | ✅ `SpeedmapTests.swift` |
| **Self-test point** | dùng `metadata.testLat/testRoadId` trên **dữ liệu bundle thật** → assert match ra đúng roadId | ✅ (skip nếu thiếu bundle) |
| Golden matcher | bảng cases heading/oneway/parallel carriageway | P1 |
| Snapshot UI | swift-snapshot-testing | P2 |
| On-device lab | iPhone thật: route Hà Nội↔HCM, tunnel, xe máy | P1 |

## 10. Roadmap

| Phase | Nội dung | Ước lượng |
|---|---|---|
| **P0 — HUD + Design foundation** ✅ *trong PR này* | 7 file speedmap vào app · parser+matcher+engine · HUD overlay card · SpaceX tokens · tests + CI | 2–3 ngày |
| **P1 — Điều hướng pro** | NavigationSession state machine · reroute · voice vi-VN · background location · thiết lập âm báo camera | 1–2 tuần |
| **P2 — Bản đồ offline** | MapLibre SPM · MBTiles bundle/tải vùng · style Orbital-dark · Settings quản lý vùng | 2–3 tuần |
| **P3 — Router + Search offline** | Valhalla XCFramework · costing ↔ AI · FTS5 geocoder · AI function-calling | 3–4 tuần |
| **P4 — OTA + CarPlay** | manifest ECDSA updater · vùng delta · CarPlay dashboard | 1–2 tuần |

## 11. Rủi ro & biện pháp

| Rủi ro | Mức | Biện pháp |
|---|---|---|
| Bản đồ/MBTiles nặng (RAM/storage) | TB |懒 loading theo tile z/x/y, LRU, compress WAL off |
| Valhalla build iOS phức tạp | Cao | CI Docker build XCFramework; fallback OSRM hoặc giữ online router |
| MapKit → MapLibre đổi nhiều code | TB | Interface `MapRenderer` bọc 2 backend, MapViewModel không đổi |
| GPS sai trong hẻm/tầng hầm | TB | matcher có hysteresis + timeout 8s → "không rõ" thay vì hiện sai |
| AI chậm/mất mạng | Thấp | timeout + fallback rule-based (đã có) |
| Dữ liệu speedmap lỗi thời | Thấp | OTA manifest + hiển thị `mapVersion` trong Settings |
| App unsigned (không App Store) | Theo mục tiêu | TrollStore/Sideloadly — không ảnh hưởng kiến trúc |

---

###附 A. Tham chiếu

- Repo dữ liệu: `911273/VietHUD/speedmap` (manifest `2026.10.24.1739`)
- Format chuẩn (nguồn): VietHUD `src/map/SpeedMapFormat.h` — wire contract builder↔reader
- OSM: ODbL — `metadata.attribution = "(c) OpenStreetMap contributors, ODbL"`
- Code P0: `App/Sources/Speedmap/*`, `App/Sources/Design/SpaceXTheme.swift`,
  `App/Sources/Views/SpeedHudOverlay.swift`, test `App/Tests/SpeedmapTests.swift`

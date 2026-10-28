import Foundation

/// Ý định chỉ đường do AI trả về (JSON). Giải mã "dễ tính" để chịu được
/// nhiều biến thể tên khoá khác nhau giữa các model/gateway.
struct AIIntent: Decodable {
    var origin: String?
    var destination: String?
    var waypoints: [String]
    var mode: String?
    var avoid: [String]
    var explanation: String?

    init() {
        origin = nil
        destination = nil
        waypoints = []
        mode = nil
        avoid = []
        explanation = nil
    }

    init(origin: String?, destination: String?, waypoints: [String] = [],
         mode: String? = nil, avoid: [String] = [], explanation: String? = nil) {
        self.origin = origin
        self.destination = destination
        self.waypoints = waypoints
        self.mode = mode
        self.avoid = avoid
        self.explanation = explanation
    }

    var travelMode: TravelMode {
        TravelMode.parse(mode) ?? .motorcycle
    }

    // MARK: Decoding linh hoạt

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        origin = Self.string(container, keys: ["origin", "from", "start", "pickup", "diem_di"])
        destination = Self.string(container, keys: ["destination", "to", "end", "target", "diem_den"])
        waypoints = Self.stringArray(container, keys: ["waypoints", "via", "stops", "diem_dung"]) ?? []
        mode = Self.string(container, keys: ["mode", "travel_mode", "transport", "phuong_tien"])
        avoid = Self.stringArray(container, keys: ["avoid", "avoidance", "exclude", "tranh"]) ?? []
        explanation = Self.string(container, keys: ["explanation", "note", "reason", "summary", "giai_thich"])
    }

    private static func string(_ container: KeyedDecodingContainer<AnyKey>, keys: [String]) -> String? {
        for key in keys {
            guard let codingKey = AnyKey(stringValue: key) else { continue }
            guard let value = try? container.decodeIfPresent(String.self, forKey: codingKey) else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = trimmed.lowercased()
            if !trimmed.isEmpty && lowered != "null" && lowered != "nil" && lowered != "none" {
                return trimmed
            }
        }
        return nil
    }

    private static func stringArray(_ container: KeyedDecodingContainer<AnyKey>, keys: [String]) -> [String]? {
        for key in keys {
            guard let codingKey = AnyKey(stringValue: key) else { continue }
            if let values = try? container.decodeIfPresent([String].self, forKey: codingKey) {
                let cleaned = values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.lowercased() != "null" }
                return cleaned
            }
            if let single = try? container.decodeIfPresent(String.self, forKey: codingKey) {
                let trimmed = single.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.lowercased() != "null" else { continue }
                return trimmed
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        }
        return nil
    }
}

/// Bộ phân tích câu lệnh tiếng Việt **chạy offline**.
/// Dùng khi chưa cấu hình AI, hoặc AI trả lời lỗi — app vẫn chỉ đường được.
enum RouteIntentParser {

    static func parse(_ text: String) -> AIIntent? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        var intent = AIIntent()
        intent.mode = detectMode(lower)?.rawValue
        let avoid = detectAvoid(lower)
        intent.avoid = avoid
        if !avoid.isEmpty {
            intent.explanation = "Tuyến được chọn có tính đến việc tránh \(avoid.joined(separator: ", "))."
        }

        var working = trimmed
        let prefixes = ["chỉ đường", "tìm đường", "dẫn đường", "đi ", "giúp tôi", "làm ơn", "cho tôi", "hãy "]
        for prefix in prefixes where lower.hasPrefix(prefix) {
            working = String(working.dropFirst(prefix.count))
            break
        }
        working = working.trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = working.range(of: "từ ", options: [.caseInsensitive]) {
            working = String(working[range.upperBound...])
        }

        let separators = [" đến ", " tới ", "->", "→", " về ", " đi ", " - "]
        for separator in separators {
            guard let range = working.range(of: separator, options: [.caseInsensitive]) else { continue }
            var originText = String(working[working.startIndex..<range.lowerBound])
            var destinationText = String(working[range.upperBound...])

            let viaMarkers = [" qua ", " ghé ", " dừng ở ", " ngang "]
            for marker in viaMarkers {
                guard let viaRange = destinationText.range(of: marker, options: [.caseInsensitive]) else { continue }
                let waypoint = String(destinationText[viaRange.upperBound...])
                destinationText = String(destinationText[destinationText.startIndex..<viaRange.lowerBound])
                let cleanedWaypoint = clean(waypoint)
                if !cleanedWaypoint.isEmpty {
                    intent.waypoints = [cleanedWaypoint]
                }
                break
            }

            originText = clean(originText)
            destinationText = clean(destinationText)

            if !originText.isEmpty && !destinationText.isEmpty {
                intent.origin = originText
                intent.destination = destinationText
                return intent
            }
        }

        return nil
    }

    // MARK: - Chi tiết

    static func detectMode(_ lowercased: String) -> TravelMode? {
        if lowercased.contains("xe máy") || lowercased.contains("xe may") || lowercased.contains("mô tô")
            || lowercased.contains("mo to") || lowercased.contains("motorcycle")
            || lowercased.contains("motorbike") || lowercased.contains("xe hai bánh")
            || lowercased.contains("two-wheel") {
            return .motorcycle
        }
        if lowercased.contains("xe đạp") || lowercased.contains("đạp xe") { return .walking }
        if lowercased.contains("đi bộ") || lowercased.contains("bộ ") || lowercased.contains("walk") {
            return .walking
        }
        if lowercased.contains("xe buýt") || lowercased.contains("buýt") || lowercased.contains("công cộng")
            || lowercased.contains("bus") || lowercased.contains("tàu") || lowercased.contains("transit") {
            return .transit
        }
        if lowercased.contains("ô tô") || lowercased.contains("xe hơi")
            || lowercased.contains("lái xe") || lowercased.contains("car") || lowercased.contains("drive") {
            return .automobile
        }
        return nil
    }

    static func detectAvoid(_ lowercased: String) -> [String] {
        var result: [String] = []
        if lowercased.contains("tránh đường đông") || lowercased.contains("tránh kẹt xe")
            || lowercased.contains("tránh tắc đường") {
            result.append("đường đông")
        }
        if lowercased.contains("tránh cao tốc") {
            result.append("cao tốc")
        }
        if lowercased.contains("tránh phà") {
            result.append("phà")
        }
        if lowercased.contains("tránh đường nhỏ") || lowercased.contains("tránh hẻm") {
            result.append("đường nhỏ")
        }
        return result
    }

    /// Bỏ đuôi mô tả ("…, tránh đường đông", "… nhanh nhất") khỏi tên địa danh.
    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cutters = [",", " tránh", " qua ", " ghé", " dừng ở", " bằng", " nhanh nhất",
                       " ngắn nhất", " ít kẹt xe", " giúp", " nhé", " với"]
        for cutter in cutters {
            if let range = text.range(of: cutter, options: [.caseInsensitive]) {
                text = String(text[text.startIndex..<range.lowerBound])
            }
        }
        let leading = ["từ ", "đến ", "tới ", "về ", "đi ", "bằng "]
        var changed = true
        while changed {
            changed = false
            let lowered = text.lowercased()
            for prefix in leading where lowered.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                changed = true
                break
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

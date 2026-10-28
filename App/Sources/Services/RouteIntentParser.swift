import Foundation

/// Mức ưu tiên khi chọn tuyến — dùng chung cho AI, bộ chấm điểm và giao diện.
enum RoutePreference: String, CaseIterable, Identifiable, Codable {
    case fastest
    case fewestCameras
    case avoidHighway
    case easiest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fastest: return "Nhanh nhất"
        case .fewestCameras: return "Ít camera"
        case .avoidHighway: return "Tránh cao tốc"
        case .easiest: return "Dễ đi nhất"
        }
    }

    var shortTitle: String {
        switch self {
        case .fastest: return "Nhanh"
        case .fewestCameras: return "Ít camera"
        case .avoidHighway: return "Tránh cao tốc"
        case .easiest: return "Dễ đi"
        }
    }

    var symbol: String {
        switch self {
        case .fastest: return "bolt.fill"
        case .fewestCameras: return "camera.fill"
        case .avoidHighway: return "road.lanes"
        case .easiest: return "hand.thumbsup.fill"
        }
    }

    /// Câu giải thích ngắn cho người dùng.
    var detail: String {
        switch self {
        case .fastest: return "Ưu tiên tổng thời gian ngắn nhất."
        case .fewestCameras: return "Đi đường ít camera phạt nguội, dù chậm hơn một chút."
        case .avoidHighway: return "Không đi cao tốc (bắt buộc với xe máy)."
        case .easiest: return "Ít rẽ, ít điểm giao cắt, dễ đi với người mới."
        }
    }

    static func parse(_ raw: String?) -> RoutePreference? {
        guard let raw else { return nil }
        let text = raw.lowercased()
        if text.contains("camera") || text.contains("phạt nguội") || text.contains("phat nguoi") {
            return .fewestCameras
        }
        if text.contains("cao tốc") || text.contains("cao toc") || text.contains("highway")
            || text.contains("motorway") || text.contains("tránh cao") {
            return .avoidHighway
        }
        if text.contains("dễ") || text.contains("de di") || text.contains("easiest")
            || text.contains("đơn giản") || text.contains("don gian") {
            return .easiest
        }
        if text.contains("nhanh") || text.contains("fast") || text.contains("thời gian")
            || text.contains("time") {
            return .fastest
        }
        return nil
    }
}

/// Ý định AI trả về (schema nhỏ, dễ đọc với mọi model). Mọi trường đều tuỳ chọn.
struct AIIntent: Decodable {
    var origin: String?
    var destination: String?
    var waypoints: [String]?
    var mode: String?
    var avoid: [String]?
    var preference: String?
    var departAfter: String?
    var explanation: String?
    var needsClarification: Bool?
    var question: String?

    enum CodingKeys: String, CodingKey {
        case origin, destination, waypoints, mode, avoid, preference, explanation, question
        case departAfter = "depart_after"
        case needsClarification = "needs_clarification"
        // Tên thay thế hay gặp
        case from, to, via, stops, transport, travelMode = "travel_mode", goal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        origin = Self.text(container, .origin) ?? Self.text(container, .from)
        destination = Self.text(container, .destination) ?? Self.text(container, .to)
        waypoints = Self.list(container, .waypoints) ?? Self.list(container, .via) ?? Self.list(container, .stops)
        mode = Self.text(container, .mode) ?? Self.text(container, .transport) ?? Self.text(container, .travelMode)
        avoid = Self.list(container, .avoid)
        preference = Self.text(container, .preference) ?? Self.text(container, .goal)
        departAfter = Self.text(container, .departAfter)
        explanation = Self.text(container, .explanation)
        needsClarification = try? container.decodeIfPresent(Bool.self, forKey: .needsClarification)
        question = Self.text(container, .question)
    }

    /// Dựng ý định trực tiếp (bộ phân tích offline dùng).
    init(origin: String? = nil,
         destination: String? = nil,
         waypoints: [String] = [],
         mode: String? = nil,
         avoid: [String] = [],
         preference: String? = nil,
         departAfter: String? = nil,
         explanation: String? = nil) {
        self.origin = origin
        self.destination = destination
        self.waypoints = waypoints
        self.mode = mode
        self.avoid = avoid
        self.preference = preference
        self.departAfter = departAfter
        self.explanation = explanation
        self.needsClarification = nil
        self.question = nil
    }

    private static func text(_ container: KeyedDecodingContainer<CodingKeys>,
                             _ key: CodingKeys) -> String? {
        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func list(_ container: KeyedDecodingContainer<CodingKeys>,
                             _ key: CodingKeys) -> [String]? {
        if let values = try? container.decodeIfPresent([String].self, forKey: key) {
            let cleaned = values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned
        }
        if let value = text(container, key) {
            return [value]
        }
        return nil
    }
}

/// Ý định đã tra ra toạ độ thật.
struct RoutePlan {
    var origin: Place?
    var destination: Place
    var waypoints: [Place] = []
    var mode: TravelMode = .motorcycle
    var preference: RoutePreference = .fastest
    var avoid: [String] = []
    var departAfter: String?
    var explanation: String?
    /// Nguồn tạo kế hoạch: AI hay bộ phân tích offline.
    var usedAI: Bool = false
    /// Ghi chú khi AI lỗi nhưng vẫn plan được bằng offline.
    var notice: String?
}

/// AI chọn tuyến nào và vì sao.
struct AIDecision {
    var routeIndex: Int
    var reason: String
    var warnings: [String] = []
}

/// Bộ phân tích câu tiếng Việt **offline** — dùng khi AI tắt, chưa có key hoặc lỗi mạng.
enum RouteIntentParser {

    static func parse(_ raw: String) -> AIIntent {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()

        var intent = AIIntent()
        intent.mode = TravelMode.parse(lowered)?.rawValue
        intent.preference = RoutePreference.parse(lowered)?.rawValue

        // Điểm dừng: "ghé X", "qua X", "dừng ở X"
        var waypoints: [String] = []
        for marker in ["ghé ", "ghe ", "dừng ở ", "dung o ", "dừng tại ", "qua ", "via "] {
            guard let range = lowered.range(of: marker) else { continue }
            let tail = String(text[range.upperBound...])
            let stop = cut(tail)
            if !stop.isEmpty, waypoints.count < 4, !waypoints.contains(stop) {
                waypoints.append(stop)
            }
        }
        intent.waypoints = waypoints

        // Tránh gì
        var avoid: [String] = []
        if lowered.contains("cao tốc") || lowered.contains("cao toc") || lowered.contains("highway") {
            avoid.append("highway")
        }
        if lowered.contains("đường đông") || lowered.contains("duong dong") || lowered.contains("kẹt xe")
            || lowered.contains("ùn tắc") || lowered.contains("un tac") || lowered.contains("congestion") {
            avoid.append("congestion")
        }
        if lowered.contains("phà") || lowered.contains("pha ") || lowered.contains("ferry") {
            avoid.append("ferry")
        }
        if lowered.contains("camera") || lowered.contains("phạt nguội") || lowered.contains("phat nguoi") {
            avoid.append("cameras")
        }
        intent.avoid = avoid

        // Điểm đi / điểm đến
        if let range = lowered.range(of: " từ ") {
            let tail = String(text[range.upperBound...])
            if let toRange = tail.lowercased().range(of: " đến ") ?? tail.lowercased().range(of: " tới ")
                ?? tail.lowercased().range(of: " to ") {
                intent.origin = cut(String(tail[..<toRange.lowerBound]))
                intent.destination = cut(String(tail[toRange.upperBound...]))
            } else {
                intent.origin = cut(tail)
            }
        } else if let range = lowered.range(of: "đến ") ?? lowered.range(of: "tới ") ?? lowered.range(of: "to ") {
            let tail = String(text[range.upperBound...])
            intent.destination = cut(tail)
        } else if lowered.hasPrefix("đi ") || lowered.hasPrefix("di ") {
            let tail = String(text.dropFirst(3))
            intent.destination = cut(tail)
        }

        if let origin = intent.origin, origin.isEmpty { intent.origin = nil }
        if let destination = intent.destination, destination.isEmpty { intent.destination = nil }

        intent.departAfter = parseDeparture(lowered)
        return intent
    }

    /// Cắt phần đuôi câu (bỏ "lúc 8h", "tránh cao tốc", dấu câu…).
    private static func cut(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stopWords = [" lúc ", " vào lúc ", " khởi hành ", " đi lúc ", " tránh ", " ưu tiên ",
                         " sao cho ", " nhanh nhất", " ít camera", " dễ đi", ".", ",", ";", "!", "?"]
        for word in stopWords {
            if let range = text.range(of: word, options: .caseInsensitive) {
                text = String(text[..<range.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "lúc 8h", "8 giờ sáng", "17:30" → chuỗi giờ để hiển thị.
    private static func parseDeparture(_ lowered: String) -> String? {
        let patterns = ["lúc ", "vào lúc ", "khởi hành lúc ", "đi lúc "]
        for pattern in patterns {
            guard let range = lowered.range(of: pattern) else { continue }
            let tail = String(lowered[range.upperBound...]).trimmingCharacters(in: .whitespaces)

            // Chỉ lấy phần giờ: cắt ở dấu câu hoặc mệnh đề tiếp theo
            // ("lúc 8 giờ sáng, ghé An Bàng" → "8 giờ sáng").
            var head = String(tail.prefix(18))
            for separator in [",", ";", ".", " và ", " ghé ", " tránh ", " rồi ", " sau đó "] {
                if let cut = head.range(of: separator) {
                    head = String(head[..<cut.lowerBound])
                }
            }
            head = head.trimmingCharacters(in: .whitespaces)
            if !head.isEmpty, head.contains("giờ") || head.contains("h") || head.contains(":") {
                return head
            }
        }
        return nil
    }
}

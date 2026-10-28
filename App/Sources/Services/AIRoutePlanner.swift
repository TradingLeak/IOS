import Foundation
import MapKit

/// Ghép AI (hiểu câu nói) với MapKit (tính tuyến thật).
/// AI **không** tự vẽ đường: nó chỉ chuyển câu tiếng Việt thành ý định,
/// còn tuyến đường do Apple Maps tính để đảm bảo đúng đường thực tế.
@MainActor
final class AIRoutePlanner {
    private let client: AIClient
    private let search: SearchService

    init(client: AIClient = AIClient(), search: SearchService) {
        self.client = client
        self.search = search
    }

    struct ResolvedIntent {
        var origin: Place?
        var destination: Place
        var waypoints: [Place]
        var mode: TravelMode
        var explanation: String?
    }

    // MARK: - Hiểu câu nói

    func interpret(_ text: String, config: AIConfig) async throws -> AIIntent {
        guard config.isConfigured else {
            // Chưa có key → dùng bộ phân tích offline, vẫn hoạt động.
            guard let intent = RouteIntentParser.parse(text) else {
                throw AIError.notConfigured
            }
            return intent
        }

        let messages: [AIMessage] = [
            .system(Self.systemPrompt),
            .user(text)
        ]

        do {
            let content = try await client.chat(config: config, messages: messages, temperature: 0.1)
            if let intent = Self.decodeIntent(from: content), intent.destination != nil {
                return intent
            }
            // Một số model trả JSON kèm lời dẫn hoặc bọc markdown.
            let retry = try await client.chat(config: config,
                                              messages: messages + [
                                                .assistant(content),
                                                .user("Chỉ trả về JSON hợp lệ theo schema, không thêm chữ nào khác.")
                                              ],
                                              temperature: 0)
            if let intent = Self.decodeIntent(from: retry), intent.destination != nil {
                return intent
            }
            throw AIError.invalidJSON
        } catch {
            // AI lỗi mạng/quota → cứu bằng parser offline trước khi báo lỗi.
            if let fallback = RouteIntentParser.parse(text) {
                return fallback
            }
            throw error
        }
    }

    nonisolated static func decodeIntent(from content: String) -> AIIntent? {
        guard let json = AIClient.extractJSONObject(from: content),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIIntent.self, from: data)
    }

    // MARK: - Biến ý định thành địa điểm thật

    func resolve(intent: AIIntent,
                 originFallback: Place?,
                 region: MKCoordinateRegion) async throws -> ResolvedIntent {
        guard let destinationName = intent.destination, !destinationName.isEmpty else {
            throw SearchError.failed("Chưa xác định được điểm đến trong câu nói của bạn.")
        }

        guard let destination = try await firstMatch(for: destinationName, region: region) else {
            throw SearchError.failed("Không tìm thấy địa điểm \"\(destinationName)\" trên Apple Maps.")
        }

        var origin: Place?
        if let originName = intent.origin, !originName.isEmpty {
            origin = try await firstMatch(for: originName, region: region)
        }
        if origin == nil { origin = originFallback }

        var resolvedWaypoints: [Place] = []
        for name in intent.waypoints.prefix(3) {
            if let place = try await firstMatch(for: name, region: region) {
                resolvedWaypoints.append(place)
            }
        }

        return ResolvedIntent(origin: origin,
                              destination: destination,
                              waypoints: resolvedWaypoints,
                              mode: intent.travelMode,
                              explanation: intent.explanation)
    }

    private func firstMatch(for query: String, region: MKCoordinateRegion) async throws -> Place? {
        let results = try await search.search(query: query, near: region)
        return results.first
    }

    // MARK: - Tóm tắt lộ trình

    /// Luôn trả về một câu tóm tắt: nếu AI lỗi/chưa cấu hình thì dùng mẫu tiếng Việt.
    func summarize(route: RouteOption,
                   originName: String,
                   destinationName: String,
                   config: AIConfig) async -> String {
        let fallback = Self.localSummary(route: route,
                                         originName: originName,
                                         destinationName: destinationName)
        guard config.isConfigured else { return fallback }

        let facts = """
        Điểm đi: \(originName)
        Điểm đến: \(destinationName)
        Phương tiện: \(route.mode.title)
        Quãng đường: \(route.formattedDistance)
        Thời gian dự kiến: \(route.formattedDuration)
        Số bước rẽ: \(route.steps.count)
        Ghi chú từ Maps: \(route.advisoryNotices.joined(separator: "; "))
        """

        do {
            let reply = try await client.chat(config: config,
                                              messages: [
                                                .system(Self.summaryPrompt),
                                                .user(facts)
                                              ],
                                              temperature: 0.5,
                                              maxTokens: 220)
            let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? fallback : cleaned
        } catch {
            return fallback
        }
    }

    // MARK: - Chọn tuyến thông minh

    struct RouteAdvice: Codable {
        var recommended: Int?
        var reason: String?
    }

    /// AI giải thích vì sao nên đi tuyến nào; lỗi mạng thì dùng câu tiếng Việt soạn sẵn.
    func advise(routes: [RouteOption],
                scores: [RouteScore],
                originName: String,
                destinationName: String,
                config: AIConfig) async -> String? {
        let local = Self.localAdvice(routes: routes, scores: scores)
        guard config.isConfigured, routes.count > 1 else { return local }

        var lines: [String] = [
            "Điểm đi: \(originName)",
            "Điểm đến: \(destinationName)",
            "Phương tiện: \(routes[0].mode.title)",
            "Các phương án (điểm 0–100, cao hơn tốt hơn):"
        ]
        for (index, route) in routes.enumerated() {
            let score = scores.first { $0.routeID == route.id }
            let total = score.map { String(format: "%.0f", $0.total) } ?? "?"
            let cameras = score?.cameraCount ?? 0
            let highway = Int(((score?.expresswayShare ?? 0) * 100).rounded())
            lines.append("[\(index)] \(route.name): \(route.formattedDistance), \(route.formattedDuration), "
                         + "điểm \(total), \(cameras) camera, \(highway)% cao tốc")
        }

        do {
            let reply = try await client.chat(config: config,
                                              messages: [.system(Self.advicePrompt), .user(lines.joined(separator: "\n"))],
                                              temperature: 0.3,
                                              maxTokens: 220)
            let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if let json = AIClient.extractJSONObject(from: cleaned),
               let data = json.data(using: .utf8),
               let advice = try? JSONDecoder().decode(RouteAdvice.self, from: data),
               let reason = advice.reason,
               !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return reason.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return cleaned.isEmpty ? local : cleaned
        } catch {
            return local
        }
    }

    /// Câu giải thích offline (không cần AI) — luôn có sẵn.
    nonisolated static func localAdvice(routes: [RouteOption], scores: [RouteScore]) -> String? {
        guard let best = scores.first,
              let route = routes.first(where: { $0.id == best.routeID }) else { return nil }

        var text = "Nên đi \(route.name): \(route.formattedDuration), \(route.formattedDistance)"
        if let second = scores.dropFirst().first {
            let gap = Int((best.total - second.total).rounded())
            if gap > 0 {
                text += " — điểm \(Int(best.total.rounded())) so với \(Int(second.total.rounded())) của phương án sau"
            }
        }
        text += "."
        if !best.summary.isEmpty {
            text += " " + best.summary + "."
        }
        return text
    }

    nonisolated static func localSummary(route: RouteOption, originName: String, destinationName: String) -> String {
        var text = "Tuyến \(route.mode.title.lowercased()) từ \(originName) đến \(destinationName) dài "
            + "\(route.formattedDistance), dự kiến \(route.formattedDuration)."
        if route.steps.count <= 3 {
            text += " Đường khá đơn giản, chỉ \(route.steps.count) bước rẽ."
        } else {
            text += " Có \(route.steps.count) bước rẽ, nên bám theo danh sách chỉ dẫn bên dưới."
        }
        if !route.advisoryNotices.isEmpty {
            text += " Lưu ý: \(route.advisoryNotices.joined(separator: "; "))."
        }
        return text
    }

    // MARK: - Prompt

    static let systemPrompt = """
    Bạn là bộ phân tích câu lệnh chỉ đường cho ứng dụng bản đồ Việt Nam.
    Người dùng nói tiếng Việt tự nhiên (có thể không dấu, viết tắt).
    Hãy trả về DUY NHẤT một JSON object, không markdown, không giải thích ngoài JSON:
    {
      "origin": string hoặc null,
      "destination": string hoặc null,
      "waypoints": [string],
      "mode": "automobile" | "motorcycle" | "walking" | "transit" | null,
      "avoid": [string],
      "explanation": string
    }
    Quy tắc:
    - Giữ nguyên tên địa danh người dùng nói, viết đúng dấu tiếng Việt, không bịa thêm.
    - Không nói rõ điểm đi thì để null (ứng dụng sẽ dùng vị trí hiện tại).
    - "xe máy", "xe mô tô", "motorbike", "xe hai bánh" → motorcycle;
      "ô tô", "xe hơi", "lái xe" → automobile; "đi bộ", "xe đạp" → walking;
      "xe buýt", "tàu", "công cộng" → transit.
    - "tránh đường đông", "tránh cao tốc", "tránh phà" → đưa vào avoid.
    - explanation: một câu ngắn (dưới 25 từ) giải thích lựa chọn.
    - Nếu câu nói không liên quan đến đường đi, để destination = null.
    """

    static let summaryPrompt = """
    Bạn là trợ lý dẫn đường người Việt. Dựa trên số liệu tuyến đường được cung cấp,
    hãy viết 2–3 câu tiếng Việt tự nhiên: nhận xét tuyến (nhanh hay chậm, có nên đi giờ cao điểm),
    một mẹo di chuyển thực tế, và gợi ý một điểm dừng dọc đường nếu phù hợp.
    Không bịa số liệu mới, không markdown, không gạch đầu dòng, tối đa 60 từ.
    """

    static let advicePrompt = """
    Bạn là trợ lý dẫn đường người Việt, đang giúp người dùng chọn giữa các phương án tuyến.
    Dữ liệu gồm điểm số 0–100 (cao hơn tốt hơn), số camera, % đường cao tốc.
    Với xe máy, tuyến có cao tốc là KHÔNG hợp lệ. Ưu tiên an toàn và ít camera.
    Trả về DUY NHẤT JSON: {"recommended": số thứ tự phương án, "reason": "1–2 câu tiếng Việt"}
    Không markdown, không giải thích ngoài JSON, tối đa 45 từ.
    """
}

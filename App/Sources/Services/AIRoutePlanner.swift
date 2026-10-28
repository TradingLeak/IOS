import Foundation
import MapKit
import CoreLocation

/// Lớp AI can thiệp **sâu** vào việc tìm tuyến và lập kế hoạch chuyến đi:
///
/// 1. Hiểu câu tiếng Việt → ý định (đi/đến/phương tiện/tránh/ghé/giờ đi/mức ưu tiên).
/// 2. Tra tên thành toạ độ thật bằng MapKit.
/// 3. Sau khi app tính tuyến, AI **chọn tuyến** và giải thích, kèm cảnh báo an toàn.
/// 4. Gợi ý điểm dừng dọc đường và giờ tới từng mốc.
///
/// Không có key / lỗi mạng → tự chuyển sang bộ phân tích offline (`RouteIntentParser`)
/// và bộ chấm điểm nội bộ (`RouteScorer`), nên app không bao giờ "chết" vì AI.
final class AIRoutePlanner {

    private let client: AIClient
    private let search: SearchService

    init(search: SearchService, client: AIClient = AIClient()) {
        self.search = search
        self.client = client
    }

    // MARK: - 1. Hiểu câu lệnh

    struct Interpretation {
        var intent: AIIntent
        var usedAI: Bool
        var notice: String?
    }

    func interpret(_ prompt: String, config: AIConfig) async -> Interpretation {
        let offline = RouteIntentParser.parse(prompt)
        guard config.isConfigured, config.enabled else {
            let notice = config.needsKey
                ? "Chưa có API key AI — đang dùng bộ phân tích tiếng Việt trên máy."
                : nil
            return Interpretation(intent: offline, usedAI: false, notice: notice)
        }

        do {
            let reply = try await client.chat(
                config: config,
                messages: [
                    .system(Self.intentPrompt),
                    .user(prompt)
                ],
                temperature: 0,
                maxTokens: 320
            )
            var intent = try AIClient.decodeJSON(AIIntent.self, from: reply)
            // AI trả thiếu trường nào thì bù bằng kết quả offline.
            if intent.destination == nil { intent.destination = offline.destination }
            if intent.origin == nil { intent.origin = offline.origin }
            if intent.mode == nil { intent.mode = offline.mode }
            if (intent.waypoints ?? []).isEmpty, let offlineStops = offline.waypoints {
                intent.waypoints = offlineStops
            }
            if (intent.avoid ?? []).isEmpty, let offlineAvoid = offline.avoid {
                intent.avoid = offlineAvoid
            }
            if intent.preference == nil { intent.preference = offline.preference }
            return Interpretation(intent: intent, usedAI: true, notice: nil)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return Interpretation(intent: offline,
                                  usedAI: false,
                                  notice: "AI lỗi: \(message) Đang dùng bộ phân tích trên máy.")
        }
    }

    // MARK: - 2. Tra toạ độ + dựng kế hoạch

    func makePlan(prompt: String,
                  config: AIConfig,
                  originFallback: Place?,
                  region: MKCoordinateRegion) async -> Result<RoutePlan, Error> {

        let interpretation = await interpret(prompt, config: config)
        let intent = interpretation.intent

        if intent.needsClarification == true, intent.destination == nil {
            return .failure(SearchError.failed(intent.question ?? "Bạn muốn đi đâu? Hãy nói rõ điểm đến."))
        }

        guard let destinationName = intent.destination, !destinationName.isEmpty else {
            return .failure(SearchError.failed("Chưa xác định được điểm đến. Ví dụ: “đi xe máy từ Cầu Giấy đến Hồ Tây”."))
        }

        guard let destination = await resolvePlace(destinationName, region: region, near: originFallback) else {
            return .failure(SearchError.failed("Không tìm thấy địa điểm “\(destinationName)”. Thử ghi rõ tỉnh/thành phố."))
        }

        var origin: Place? = originFallback
        if let originName = intent.origin, !originName.isEmpty {
            origin = await resolvePlace(originName, region: region, near: destination) ?? originFallback
        }

        var stops: [Place] = []
        for name in intent.waypoints ?? [] {
            if let place = await resolvePlace(name, region: region, near: destination) {
                stops.append(place)
            }
        }

        let mode = TravelMode.parse(intent.mode) ?? .motorcycle
        let preference = RoutePreference.parse(intent.preference)
            ?? ((intent.avoid ?? []).contains("highway") ? .avoidHighway : .fastest)

        var plan = RoutePlan(origin: origin,
                             destination: destination,
                             waypoints: stops,
                             mode: mode,
                             preference: preference,
                             avoid: intent.avoid ?? [],
                             departAfter: intent.departAfter,
                             explanation: intent.explanation,
                             usedAI: interpretation.usedAI,
                             notice: interpretation.notice)
        if plan.origin == nil {
            plan.origin = originFallback
        }
        return .success(plan)
    }

    /// Tra tên địa điểm; ưu tiên kết quả gần `near` và trong khu vực đang xem.
    func resolvePlace(_ name: String, region: MKCoordinateRegion, near: Place?) async -> Place? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if lowered.contains("vị trí của tôi") || lowered.contains("vi tri cua toi")
            || lowered == "đây" || lowered == "here" || lowered.contains("chỗ tôi") {
            return nil
        }

        var searchRegion = region
        if let near {
            searchRegion = MKCoordinateRegion(center: near.coordinate,
                                              latitudinalMeters: 60_000,
                                              longitudinalMeters: 60_000)
        }

        if let first = try? await search.search(query: trimmed, near: searchRegion), let place = first.first {
            return place
        }
        // Thử lại với khu vực rộng hơn (cả nước) khi tên không có trong vùng đang xem.
        if let first = try? await search.search(query: trimmed, near: MapPreset.vietnam.region) {
            return first.first
        }
        return nil
    }

    // MARK: - 3. AI chọn tuyến (can thiệp sâu)

    func chooseRoute(routes: [RouteOption],
                     scores: [RouteScore],
                     preference: RoutePreference,
                     originName: String,
                     destinationName: String,
                     alerts: [ActiveAlert],
                     config: AIConfig) async -> AIDecision? {
        guard config.isConfigured, config.deepPlanning, routes.count > 1 else { return nil }

        let facts = routeFacts(routes: routes,
                               scores: scores,
                               alerts: alerts,
                               originName: originName,
                               destinationName: destinationName,
                               preference: preference)

        do {
            let reply = try await client.chat(
                config: config,
                messages: [
                    .system(Self.rankPrompt),
                    .user(facts)
                ],
                temperature: 0,
                maxTokens: 260
            )
            let decoded = try AIClient.decodeJSON(RankingReply.self, from: reply)
            guard let index = decoded.routeIndex, routes.indices.contains(index) else { return nil }

            var warnings = decoded.warnings ?? []
            // Kiểm tra an toàn: xe máy mà tuyến có cao tốc thì luôn cảnh báo.
            if routes[index].mode == .motorcycle,
               RouteScorer.expresswayShare(routes[index]) > 0.05,
               !warnings.contains(where: { $0.lowercased().contains("cao tốc") }) {
                warnings.append(SpeedLimitRules.motorcycleExpresswayNotice)
            }
            let reason = (decoded.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return AIDecision(routeIndex: index,
                              reason: reason.isEmpty ? "AI chọn tuyến này vì cân bằng thời gian và cảnh báo." : reason,
                              warnings: warnings)
        } catch {
            return nil
        }
    }

    /// Dữ liệu gửi cho AI — gọn, có số liệu thật để AI không bịa.
    private func routeFacts(routes: [RouteOption],
                            scores: [RouteScore],
                            alerts: [ActiveAlert],
                            originName: String,
                            destinationName: String,
                            preference: RoutePreference) -> String {
        var lines: [String] = [
            "Điểm đi: \(originName)",
            "Điểm đến: \(destinationName)",
            "Phương tiện: \(routes[0].mode.title)",
            "Ưu tiên của người dùng: \(preference.rawValue) (\(preference.title))",
            "Các phương án (index: mô tả):"
        ]
        for (index, route) in routes.enumerated() {
            let score = scores.first { $0.routeID == route.id }
            let total = score.map { String(format: "%.0f", $0.total) } ?? "?"
            let cameras = score?.cameraCount ?? 0
            let speedAlerts = score?.speedAlertCount ?? 0
            let highway = Int(((score?.expresswayShare ?? RouteScorer.expresswayShare(route)) * 100).rounded())
            let toll = route.tollCost.map { "\($0) đồng" } ?? "0"
            let steps = route.steps.count
            lines.append("[\(index)] \(route.name): \(Int(route.distance)) m, "
                         + "\(Int(route.expectedTravelTime / 60)) phút, điểm \(total), "
                         + "\(cameras) camera, \(speedAlerts) biển giới hạn, \(highway)% cao tốc, "
                         + "phí \(toll), \(steps) bước rẽ")
        }
        if !alerts.isEmpty {
            let kinds = Dictionary(grouping: alerts, by: { $0.alert.kind.shortTitle })
                .map { "\($0.key) ×\($0.value.count)" }
                .sorted()
            lines.append("Cảnh báo dọc tuyến đang chọn: " + kinds.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 4. Điểm dừng + kế hoạch chuyến đi

    /// AI gợi ý nên dừng ở đâu (xăng/cà phê/ăn/ nghỉ), rồi app tra địa điểm thật.
    func plannedStops(for route: RouteOption,
                      preference: RoutePreference,
                      config: AIConfig) async -> [Place] {
        let geometry = RouteGeometry(coordinates: route.coordinates)
        guard !geometry.isEmpty else { return [] }

        var categories: [NearbyCategory] = []
        var fractions: [Double] = [0.45]

        if config.isConfigured, config.deepPlanning {
            if let ai = await askStopPlan(route: route, config: config) {
                categories = ai.categories
                fractions = ai.fractions
            }
        }

        if categories.isEmpty {
            // Mặc định: đường dài thì chọn trạm xăng + quán cà phê ở giữa tuyến.
            categories = route.distance > 15_000
                ? [.fuel, .cafe]
                : [.cafe]
            fractions = route.distance > 40_000 ? [0.33, 0.66] : [0.5]
        }

        var found: [Place] = []
        for fraction in fractions.prefix(2) {
            guard let point = geometry.point(at: geometry.totalDistance * max(0.1, min(0.9, fraction))) else { continue }
            for category in categories.prefix(2) {
                if let places = try? await search.nearby(category, around: point, radiusMeters: 2_500),
                   let first = places.first {
                    if !found.contains(where: { $0.name == first.name }) {
                        found.append(first)
                    }
                }
            }
        }
        return Array(found.prefix(3))
    }

    private struct StopPlanReply: Decodable {
        var stops: [String]?
        var positions: [Double]?
    }

    private func askStopPlan(route: RouteOption, config: AIConfig) async -> (categories: [NearbyCategory], fractions: [Double])? {
        let prompt = [
            "Tuyến \(route.mode.title) dài \(Int(route.distance / 1000)) km, khoảng \(Int(route.expectedTravelTime / 60)) phút.",
            NearbyCategory.all.map { "\($0.id)=\($0.title)" }.joined(separator: ", ")
        ].joined(separator: "\n")

        guard let reply = try? await client.chat(config: config,
                                                 messages: [.system(Self.stopPrompt), .user(prompt)],
                                                 temperature: 0.2,
                                                 maxTokens: 160),
              let decoded = try? AIClient.decodeJSON(StopPlanReply.self, from: reply),
              let ids = decoded.stops, !ids.isEmpty else { return nil }

        let categories = ids.compactMap { id in
            NearbyCategory.all.first { $0.id.lowercased() == id.lowercased() }
        }
        let fractions = (decoded.positions ?? []).filter { $0 > 0.1 && $0 < 0.95 }
        return (categories, fractions.isEmpty ? [0.5] : fractions)
    }

    // MARK: - 5. Câu trả lời / tóm tắt

    func narrate(plan: RoutePlan,
                 route: RouteOption?,
                 score: RouteScore?,
                 config: AIConfig) async -> String {
        let local = localNarrative(plan: plan, route: route, score: score)
        guard config.isConfigured, config.deepPlanning, let route else { return local }

        var facts: [String] = [
            "Điểm đi: \(plan.origin?.name ?? "vị trí hiện tại")",
            "Điểm đến: \(plan.destination.name)",
            "Phương tiện: \(plan.mode.title)",
            "Mục tiêu: \(plan.preference.title)"
        ]
        if !plan.waypoints.isEmpty {
            facts.append("Điểm dừng: " + plan.waypoints.map { $0.name }.joined(separator: ", "))
        }
        facts.append("Tuyến đang chọn: \(route.name), \(route.formattedDistance), \(route.formattedDuration)")
        if let score {
            facts.append("Điểm an toàn/thuận lợi: \(Int(score.total.rounded()))/100, "
                         + "\(score.cameraCount) camera, \(score.speedAlertCount) biển giới hạn")
        }
        if !route.advisoryNotices.isEmpty {
            facts.append("Lưu ý: " + route.advisoryNotices.joined(separator: "; "))
        }
        if let depart = plan.departAfter {
            facts.append("Giờ khởi hành mong muốn: \(depart)")
        }

        let prompt = facts.joined(separator: "\n")
        if let reply = try? await client.chat(config: config,
                                              messages: [.system(Self.narratePrompt), .user(prompt)],
                                              temperature: 0.4,
                                              maxTokens: 240) {
            let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        return local
    }

    private func localNarrative(plan: RoutePlan, route: RouteOption?, score: RouteScore?) -> String {
        var parts: [String] = []
        if let route {
            parts.append(RouteInsight.summary(route: route,
                                              originName: plan.origin?.name ?? "vị trí của bạn",
                                              destinationName: plan.destination.name))
        } else {
            parts.append("Đã hiểu: \(plan.mode.title.lowercased()) tới \(plan.destination.name).")
        }
        if !plan.waypoints.isEmpty {
            parts.append("Có dừng tại " + plan.waypoints.map { $0.name }.joined(separator: ", ") + ".")
        }
        if let score, score.cameraCount > 0 {
            parts.append("Tuyến đi qua \(score.cameraCount) camera — app sẽ cảnh báo trước.")
        }
        if let depart = plan.departAfter {
            parts.append("Khởi hành \(depart).")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Prompt

    private static let intentPrompt = """
    Bạn là bộ phân tích câu lệnh dẫn đường cho ứng dụng bản đồ Việt Nam.
    Đọc câu của người dùng và CHỈ trả về một object JSON, không giải thích, không markdown.

    Schema:
    {
      "origin": "tên điểm đi hoặc null",
      "destination": "tên điểm đến",
      "waypoints": ["các điểm muốn ghé"],
      "mode": "automobile" | "motorcycle" | "walking" | "transit",
      "avoid": ["highway" | "congestion" | "ferry" | "toll" | "cameras"],
      "preference": "fastest" | "fewestCameras" | "avoidHighway" | "easiest",
      "depart_after": "8:00" hoặc null,
      "explanation": "một câu ngắn giải thích bạn hiểu gì",
      "needs_clarification": false,
      "question": null
    }

    Quy tắc:
    - Giữ nguyên tên địa danh tiếng Việt, KHÔNG tự thêm tỉnh/thành nếu người dùng không nói.
    - Người dùng nói "xe máy", "mô tô", "hai bánh" → motorcycle. "ô tô", "xe hơi" → automobile.
    - "tránh cao tốc" → avoid có "highway" và preference "avoidHighway".
    - "ít camera", "né phạt nguội" → preference "fewestCameras" và avoid có "cameras".
    - "nhanh nhất", "gấp" → preference "fastest". "dễ đi" → "easiest".
    - Nếu thiếu điểm đến, đặt needs_clarification = true và hỏi lại trong question.
    - KHÔNG bịa toạ độ, chỉ trả tên.
    """

    private static let rankPrompt = """
    Bạn là chuyên gia chọn tuyến đường ở Việt Nam. Bạn nhận danh sách phương án tuyến kèm
    số liệu thật (thời gian, quãng đường, camera phạt nguội, biển giới hạn tốc độ, % cao tốc,
    phí cầu đường, số bước rẽ) và mức ưu tiên của người dùng.

    CHỈ trả về JSON:
    {"route_index": 0, "reason": "một đến hai câu tiếng Việt vì sao chọn tuyến này", "warnings": ["cảnh báo nếu có"]}

    Quy tắc bắt buộc:
    - route_index là số trong dấu [] của danh sách, phải tồn tại.
    - Ưu tiên "fewestCameras" → chọn tuyến ít camera nhất dù chậm hơn.
    - Ưu tiên "avoidHighway" hoặc phương tiện xe máy → KHÔNG chọn tuyến có cao tốc nếu còn tuyến khác.
    - Ưu tiên "easiest" → chọn tuyến ít bước rẽ, ít cao tốc.
    - Ưu tiên "fastest" → chọn thời gian ngắn nhất, nhưng nếu chênh lệch dưới 3 phút mà tuyến
      kia ít camera hơn nhiều thì nêu điều đó trong reason.
    - Không bịa số liệu mới.
    """

    private static let stopPrompt = """
    Bạn giúp lập kế hoạch dừng nghỉ cho một chuyến đi ở Việt Nam.
    Bạn nhận độ dài tuyến, thời gian dự kiến và danh sách mã danh mục địa điểm.

    CHỈ trả về JSON:
    {"stops": ["fuel"], "positions": [0.5]}

    Quy tắc:
    - "stops" chỉ dùng đúng các mã được cung cấp, tối đa 2 mã.
    - "positions" là tỉ lệ 0–1 dọc tuyến, cùng số phần tử với stops, chỉ trong khoảng 0.2–0.8.
    - Chuyến dưới 10 km: có thể trả mảng rỗng.
    """

    private static let narratePrompt = """
    Bạn là trợ lý dẫn đường Việt Nam. Dựa CHỈ trên số liệu được cung cấp, viết 2–4 câu
    tiếng Việt tự nhiên: tuyến đã chọn, vì sao hợp với mục tiêu, cảnh báo camera/biển báo
    đáng chú ý, và mẹo ngắn (giờ đi, điểm dừng). Không bịa số liệu, không markdown,
    không mở đầu bằng "Chắc chắn rồi".
    """
}

// MARK: - Kiểu dữ liệu phụ

private struct RankingReply: Decodable {
    var routeIndex: Int?
    var reason: String?
    var warnings: [String]?

    enum CodingKeys: String, CodingKey {
        case routeIndex = "route_index"
        case reason, warnings
        case index
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        routeIndex = (try? container.decodeIfPresent(Int.self, forKey: .routeIndex))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .index))
        reason = try? container.decodeIfPresent(String.self, forKey: .reason)
        warnings = try? container.decodeIfPresent([String].self, forKey: .warnings)
    }
}

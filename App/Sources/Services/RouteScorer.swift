import Foundation

/// Điểm số của một phương án tuyến — dùng cho "tìm đường thông minh".
struct RouteScore: Identifiable, Equatable {
    let id: UUID
    let routeID: UUID
    let total: Double
    let timeScore: Double
    let distanceScore: Double
    let safetyScore: Double
    let comfortScore: Double
    let cameraCount: Int
    let speedAlertCount: Int
    let expresswayShare: Double
    let tollCost: Int?
    let reasons: [String]
    let summary: String

    /// Nhãn ngắn để vẽ trên bản đồ / danh sách.
    var badge: String {
        if total >= 85 { return "Rất tốt" }
        if total >= 70 { return "Tốt" }
        if total >= 55 { return "Tạm được" }
        return "Nên tránh"
    }
}

/// Chấm điểm nhiều tuyến theo thời gian, quãng đường, mật độ camera,
/// mức độ đi vào cao tốc (quan trọng với xe máy) và phí cầu đường.
struct RouteScorer {

    var database: AlertDatabase
    var preferences: AlertPreferences = .all

    func score(_ routes: [RouteOption]) -> [RouteScore] {
        guard !routes.isEmpty else { return [] }

        let times = routes.map { max(1, $0.expectedTravelTime) }
        let distances = routes.map { max(1, $0.distance) }
        guard let minTime = times.min(), let minDistance = distances.min() else { return [] }

        var scores: [RouteScore] = []

        for (index, route) in routes.enumerated() {
            var cameras = 0
            var speedAlerts = 0
            if !database.isEmpty {
                let geometry = RouteGeometry(coordinates: route.coordinates)
                let alerts = database.alongRoute(geometry,
                                                 corridor: 60,
                                                 kinds: preferences.enabledKinds)
                cameras = alerts.filter { $0.alert.kind.isCamera }.count
                speedAlerts = alerts.filter { $0.alert.kind.carriesSpeedLimit }.count
            }

            let highway = Self.expresswayShare(route)

            let timeScore = min(100, 100 * minTime / times[index])
            let distanceScore = min(100, 100 * minDistance / distances[index])

            let kilometers = max(0.3, route.distance / 1000)
            let cameraDensity = Double(cameras) / kilometers
            let safetyScore = max(0, min(100, 100 - cameraDensity * 6 - Double(speedAlerts) / kilometers * 2))

            let highwayPenalty = highway * (route.mode == .motorcycle ? 130 : 45)
            let complexity = min(20, Double(route.steps.count) * 0.7)
            let comfortScore = max(0, min(100, 100 - highwayPenalty - complexity))

            let weights: (time: Double, distance: Double, safety: Double, comfort: Double)
            if route.mode == .motorcycle {
                weights = (0.40, 0.15, 0.20, 0.25)
            } else if route.mode == .walking {
                weights = (0.45, 0.40, 0.10, 0.05)
            } else {
                weights = (0.50, 0.20, 0.18, 0.12)
            }

            var total = timeScore * weights.time
                + distanceScore * weights.distance
                + safetyScore * weights.safety
                + comfortScore * weights.comfort

            if let toll = route.tollCost, toll > 0 {
                total -= min(6, Double(toll) / 30_000)
            }
            // Xe máy đi vào cao tốc là vi phạm → trừ mạnh, gần như loại phương án này.
            if route.mode == .motorcycle, highway > 0.05 {
                total -= 25
            }
            total = max(0, min(100, total))

            var reasons: [String] = []
            let extraSeconds = times[index] - minTime
            if extraSeconds < 60 {
                reasons.append("Nhanh nhất trong các phương án")
            } else {
                reasons.append("Chậm hơn tuyến nhanh nhất \(Format.duration(extraSeconds))")
            }
            if cameras > 0 {
                reasons.append("Đi qua \(cameras) camera")
            }
            if speedAlerts > 0 {
                reasons.append("\(speedAlerts) biển/vùng giới hạn tốc độ")
            }
            if highway > 0.05 {
                if route.mode == .motorcycle {
                    reasons.append("Có \(Int((highway * 100).rounded()))% đường cao tốc — xe máy không được đi")
                } else {
                    reasons.append("Đi \(Int((highway * 100).rounded()))% đường cao tốc")
                }
            }
            if let tollText = route.tollCostText {
                reasons.append("Phí cầu đường khoảng \(tollText)")
            }
            if route.isEstimatedProfile {
                reasons.append("Thời gian là ước lượng cho xe máy")
            }

            scores.append(RouteScore(id: route.id,
                                     routeID: route.id,
                                     total: total,
                                     timeScore: timeScore,
                                     distanceScore: distanceScore,
                                     safetyScore: safetyScore,
                                     comfortScore: comfortScore,
                                     cameraCount: cameras,
                                     speedAlertCount: speedAlerts,
                                     expresswayShare: highway,
                                     tollCost: route.tollCost,
                                     reasons: reasons,
                                     summary: reasons.prefix(2).joined(separator: " · ")))
        }

        return scores.sorted { $0.total > $1.total }
    }

    // MARK: - Cao tốc

    /// Tỉ lệ (0...1) quãng đường đi trên cao tốc.
    static func expresswayShare(_ route: RouteOption) -> Double {
        guard route.distance > 0 else { return 0 }
        var meters = 0.0
        for step in route.steps where isExpressway(step) {
            meters += max(0, step.distance)
        }
        if meters <= 0, isExpresswayName(route.name) { return 1 }
        return min(1, meters / route.distance)
    }

    static func isExpressway(_ step: RouteStep) -> Bool {
        if let name = step.roadName, isExpresswayName(name) { return true }
        return isExpresswayName(step.instruction)
    }

    static func isExpresswayName(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        let lower = text.lowercased()
        let needles = ["cao tốc", "cao toc", "đường trên cao", "duong tren cao",
                       "ct.", "ct0", "ct1", "ct2", "expressway", "motorway", "đường vành đai trên cao"]
        return needles.contains { lower.contains($0) }
    }
}

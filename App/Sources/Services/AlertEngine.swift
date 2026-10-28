import Foundation
import CoreLocation

/// Tính cảnh báo đang hoạt động, giới hạn tốc độ hiện tại và câu đọc lên.
struct AlertEngine {

    let database: AlertDatabase
    var preferences: AlertPreferences = .all

    // MARK: - Cảnh báo dọc tuyến

    /// Danh sách cảnh báo nằm trên (hoặc rất gần) tuyến, sắp theo thứ tự đi.
    /// `distance` ở bước này = vị trí trên tuyến tính từ điểm đi.
    func alertsAlongRoute(_ route: RouteOption,
                          corridor: Double = 90,
                          kinds: Set<AlertKind>? = nil) -> [ActiveAlert] {
        let geometry = RouteGeometry(coordinates: route.coordinates)
        guard !geometry.isEmpty else { return [] }

        let allowed = kinds ?? preferences.enabledKinds
        return database.alongRoute(geometry, corridor: corridor, kinds: allowed)
    }

    /// Các cảnh báo phía trước vị trí hiện tại, kèm khoảng cách thật.
    func aheadAlerts(from distanceAlongRoute: Double,
                     alerts: [ActiveAlert],
                     speedKmh: Double,
                     horizon: Double = 1_200) -> [ActiveAlert] {
        let warn = ActiveAlert.warnDistance(forSpeed: speedKmh,
                                            min: preferences.warnDistanceMin,
                                            max: preferences.warnDistanceMax)

        var result: [ActiveAlert] = []
        for alert in alerts {
            let distance = alert.distanceAlongRoute - distanceAlongRoute
            let behindTolerance = alert.alert.kind == .speedZone ? (alert.alert.length ?? 0) : 8
            guard distance >= -behindTolerance, distance <= horizon else { continue }
            result.append(ActiveAlert(alert: alert.alert,
                                      distance: distance,
                                      warnDistance: warn,
                                      distanceAlongRoute: alert.distanceAlongRoute))
        }

        result.sort { $0.distance < $1.distance }
        return result
    }

    // MARK: - Giới hạn tốc độ

    func speedLimit(at distanceAlongRoute: Double,
                    alerts: [ActiveAlert],
                    roadNames: [String],
                    mode: TravelMode) -> SpeedLimitInfo {
        var best: SpeedLimitInfo?
        var bestPosition = -Double.infinity

        for active in alerts {
            let alert = active.alert
            guard let limit = alert.speedLimit else { continue }

            let start = active.distanceAlongRoute
            let applies: Bool
            switch alert.kind {
            case .speedZone:
                let length = alert.length ?? 0
                applies = distanceAlongRoute >= start - 15 && distanceAlongRoute <= start + max(length, 50)
            case .speedSign, .residentialZone:
                // Áp dụng từ lúc tới biển (sai số 20 m) cho tới khi có biển khác.
                applies = distanceAlongRoute >= start - 20
            default:
                applies = false
            }

            guard applies, start >= bestPosition else { continue }
            bestPosition = start
            let source: SpeedLimitSource = alert.kind == .speedZone ? .zone : .sign
            best = SpeedLimitInfo(limit: limit,
                                  source: source,
                                  alertID: alert.id,
                                  roadName: alert.road)
        }

        if let best { return best }

        if let estimated = SpeedLimitRules.estimate(roadNames: roadNames, mode: mode) {
            return SpeedLimitInfo(limit: estimated,
                                  source: .estimated,
                                  alertID: nil,
                                  roadName: roadNames.first)
        }

        return SpeedLimitInfo(limit: nil, source: .unknown, alertID: nil, roadName: roadNames.first)
    }

    /// Tên đường suy ra từ bước chỉ dẫn hiện tại và bước kế tiếp (nếu có).
    static func roadNames(currentStep: RouteStep?, nextStep: RouteStep?) -> [String] {
        var names: [String] = []
        for step in [currentStep, nextStep] {
            guard let step else { continue }
            if let name = step.roadName, !name.isEmpty {
                names.append(name)
            } else if let name = SpeedLimitRules.roadName(in: step.instruction) {
                names.append(name)
            }
        }
        return names
    }

    // MARK: - Ngữ cảnh tốc độ

    func speedContext(coordinate: CLLocationCoordinate2D,
                      speedKmh: Double,
                      route: RouteOption?,
                      geometry: RouteGeometry?,
                      alerts: [ActiveAlert],
                      currentStep: RouteStep?,
                      nextStep: RouteStep?,
                      mode: TravelMode) -> SpeedContext {
        var context = SpeedContext()
        context.speedKmh = max(0, speedKmh)
        context.tolerance = preferences.overspeedTolerance

        let roadNames = Self.roadNames(currentStep: currentStep, nextStep: nextStep)
        context.roadName = roadNames.first ?? currentStep?.instruction

        guard let geometry, !geometry.isEmpty,
              let projection = geometry.projection(of: coordinate) else {
            let info = speedLimit(at: 0, alerts: alerts, roadNames: roadNames, mode: mode)
            context.limit = info.limit
            context.limitSource = info.source
            return context
        }

        let info = speedLimit(at: projection.along, alerts: alerts, roadNames: roadNames, mode: mode)
        context.limit = info.limit
        context.limitSource = info.source
        if let name = info.roadName { context.roadName = name }

        let ahead = aheadAlerts(from: projection.along, alerts: alerts, speedKmh: context.speedKmh)
        context.nextAlert = ahead.first { $0.alert.kind.isSafetyCritical } ?? ahead.first
        return context
    }

    // MARK: - Câu đọc lên

    static func announcement(for active: ActiveAlert, mode: TravelMode) -> String {
        let alert = active.alert
        let distance = Format.hudDistance(max(0, active.distance))
        let limitText = alert.speedLimit.map { ", giới hạn \($0) ki lô mét trên giờ" } ?? ""

        switch alert.kind {
        case .speedCamera:
            return "Chú ý, camera bắn tốc độ phía trước, còn \(distance)."
        case .redLightCamera:
            return "Chú ý, camera đèn đỏ phía trước, còn \(distance)."
        case .surveillanceCamera:
            return "Camera giám sát giao thông phía trước, còn \(distance)."
        case .speedSign:
            return "Biển báo tốc độ\(limitText) phía trước, còn \(distance)."
        case .speedZone:
            if active.distance < 0 {
                return "Bạn đang trong vùng giới hạn\(limitText)."
            }
            return "Sắp vào vùng giới hạn\(limitText), còn \(distance)."
        case .residentialZone:
            return "Sắp vào khu vực đông dân cư\(limitText), còn \(distance)."
        case .noOvertake:
            return "Đoạn đường cấm vượt, còn \(distance)."
        case .tollStation:
            return "Trạm thu phí phía trước, còn \(distance)."
        case .schoolZone:
            return "Khu vực trường học phía trước, còn \(distance). Hãy giảm tốc độ."
        case .checkpoint:
            return "Điểm kiểm tra tốc độ phía trước, còn \(distance)."
        case .hazard:
            return "Cảnh báo sự cố trên đường, còn \(distance)."
        case .other:
            return "\(alert.displayName) phía trước, còn \(distance)."
        }
    }

    static func overspeedAnnouncement(_ context: SpeedContext) -> String? {
        guard context.isOverLimit, let limit = context.limit else { return nil }
        if context.isHardOverspeed {
            return "Bạn đang vượt quá tốc độ quy định \(limit) ki lô mét trên giờ. Hãy giảm tốc độ."
        }
        return "Chú ý tốc độ, giới hạn \(limit) ki lô mét trên giờ."
    }

    /// Nhắc xe máy khi tuyến đi vào cao tốc.
    static func motorcycleWarning(for route: RouteOption) -> String? {
        guard route.mode == .motorcycle else { return nil }
        let share = RouteScorer.expresswayShare(route)
        if share > 0.05 {
            return SpeedLimitRules.motorcycleExpresswayNotice
        }
        return nil
    }
}

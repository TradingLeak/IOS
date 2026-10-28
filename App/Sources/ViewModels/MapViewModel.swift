import Foundation
import SwiftUI
import MapKit
import CoreLocation
import Combine
import UIKit

/// Trạng thái trung tâm của màn hình bản đồ.
@MainActor
final class MapViewModel: ObservableObject {

    // MARK: Dịch vụ

    let location: LocationService
    let searchService = SearchService()
    private let store = PlacesStore()
    private let voice = VoiceAlertService()
    private lazy var planner = AIRoutePlanner(search: searchService)

    // MARK: Dữ liệu cảnh báo

    private let bundledAlerts: [RoadAlert]
    private let bundledSources: [AlertSource]
    @Published private(set) var alertDatabase: AlertDatabase
    private var importedAlerts: [RoadAlert] = []
    private var preferences = AlertPreferences.all

    // MARK: Trợ lý AI

    @Published var aiConfig = AIConfig()
    @Published var preference: RoutePreference = .fastest
    /// AI đã chọn tuyến nào và vì sao (can thiệp sâu vào kết quả tìm tuyến).
    @Published var aiDecision: AIDecision?
    /// Kế hoạch chuyến đi AI dựng (điểm đi/đến/điểm dừng/phương tiện/giờ đi).
    @Published var aiPlan: RoutePlan?
    @Published var aiThinking = false
    @Published var aiError: String?
    @Published var transcript: [AIChatBubble] = []
    @Published var aiNarration: String?
    /// AI đang bật nhưng chưa nhập key.
    var aiNeedsKey: Bool { aiConfig.needsKey }

    // MARK: Cấu hình (đồng bộ từ AppSettings)

    private(set) var vietmapKey = ""
    /// Tự bám theo vị trí khi bắt đầu dẫn đường (đồng bộ từ Cài đặt).
    private var followOnStart = true
    private var didApplyDefaultMode = false

    // MARK: Bản đồ

    @Published var selectedPreset: MapPreset = .vietnam
    @Published var fitToken = 0
    @Published var focusCoordinate: CLLocationCoordinate2D?
    @Published var focusToken = 0

    // MARK: Tuyến đường

    @Published var origin: Place?
    @Published var destination: Place?
    @Published var waypoints: [Place] = []
    @Published var mode: TravelMode = .motorcycle
    @Published var routes: [RouteOption] = []
    @Published var selectedRouteID: UUID?
    @Published var isPlanning = false
    @Published var isNavigating = false
    @Published var navigationStepIndex = 0

    // MARK: Dẫn đường thông minh (chấm điểm + nhận xét offline)

    @Published var routeScores: [RouteScore] = []
    @Published var routeAdvice: String?
    @Published var routeSummary: String?
    @Published var suggestedStops: [Place] = []
    @Published var isLoadingStops = false

    // MARK: Cảnh báo tốc độ / camera

    @Published var routeAlerts: [ActiveAlert] = []
    @Published var aheadAlerts: [ActiveAlert] = []
    @Published var nearbyAlertPoints: [RoadAlert] = []
    @Published var speedContext = SpeedContext()
    @Published var speedKmh: Double = 0
    @Published var isLoadingAlerts = false
    @Published var alertStatusMessage: String?

    private var routeGeometry: RouteGeometry?

    // Trạng thái phụ trợ khi dẫn đường
    private var lastSyncedPreference: RoutePreference?
    private var lastNearbyRefresh: Date?
    private var lastNearbyCenter: CLLocationCoordinate2D?
    private var wasOverLimit = false
    private var offRouteSamples = 0
    private var lastRerouteAt = Date.distantPast

    // MARK: Địa điểm

    @Published var nearbyPlaces: [Place] = []
    @Published var activeCategory: NearbyCategory?
    @Published var recents: [Place] = []
    @Published var favorites: [Place] = []

    // MARK: Camera dẫn đường (2D / 3D theo thời gian thực)

    /// Bám theo vị trí + hướng đi; người dùng kéo bản đồ sẽ tạm tắt.
    @Published var isFollowingUser = true
    @Published var followToken = 0
    /// Hướng di chuyển hiện tại (độ) để xoay bản đồ.
    @Published var courseDegrees: Double = 0
    /// Vị trí đang dùng cho camera khi dẫn đường.
    @Published var navigationCoordinate: CLLocationCoordinate2D?

    // MARK: UI

    @Published var toast: String?
    @Published var errorMessage: String?
    @Published var showRouteSheet = false

    // MARK: - Vòng đời

    init(location: LocationService = LocationService()) {
        self.location = location
        let database = AlertDatabase.loadBundled()
        self.bundledAlerts = database.alerts
        self.bundledSources = database.sources
        self.alertDatabase = database
        self.importedAlerts = AlertFileStore.loadImported()
        if !importedAlerts.isEmpty {
            rebuildDatabase()
        }
    }

    func bootstrap() {
        recents = store.recents()
        favorites = store.favorites()
        location.requestLocation()
        // Chưa có tuyến vẫn thấy biển báo/camera quanh mình trên bản đồ.
        refreshNearbyAlertsIfNeeded()
    }

    /// Đồng bộ toàn bộ cài đặt (VietMap, cảnh báo, camera dẫn đường).
    func syncSettings(_ settings: AppSettings) {
        vietmapKey = settings.vietmapKey
        if aiConfig != settings.aiConfig {
            aiConfig = settings.aiConfig
        }
        // Chỉ áp mức ưu tiên khi người dùng thật sự đổi trong Cài đặt — tránh ghi đè
        // lựa chọn vừa bấm trong sheet hoặc do AI đề xuất.
        if lastSyncedPreference != settings.routePreference {
            preference = settings.routePreference
            lastSyncedPreference = settings.routePreference
        }
        followOnStart = settings.followUserInNavigation
        preferences = settings.alertPreferences
        voice.isEnabled = preferences.voiceEnabled
        if !didApplyDefaultMode {
            mode = settings.defaultMode
            didApplyDefaultMode = true
        }
        if !isNavigating {
            speedContext.tolerance = preferences.overspeedTolerance
        }
        if !preferences.showOnMap {
            nearbyAlertPoints = []
        }
    }

    // MARK: - Dịch vụ dẫn xuất

    private var routing: RoutingService {
        RoutingService(vietmapKey: vietmapKey)
    }

    private var scorer: RouteScorer {
        RouteScorer(database: alertDatabase, preferences: preferences)
    }

    private var engine: AlertEngine {
        AlertEngine(database: alertDatabase, preferences: preferences)
    }

    // MARK: - Dữ liệu dẫn xuất

    var selectedRoute: RouteOption? {
        if let selectedRouteID, let route = routes.first(where: { $0.id == selectedRouteID }) {
            return route
        }
        return routes.first
    }

    var hasRoute: Bool { selectedRoute != nil }

    var currentPlace: Place? {
        guard let coordinate = location.coordinate else { return nil }
        return Place(name: "Vị trí của tôi",
                     subtitle: Format.coordinates(coordinate),
                     coordinate: coordinate)
    }

    func score(for route: RouteOption) -> RouteScore? {
        routeScores.first { $0.routeID == route.id }
    }

    var recommendedScore: RouteScore? {
        routeScores.first
    }

    var mapPins: [MapPin] {
        var pins: [MapPin] = []
        if let origin {
            pins.append(MapPin(id: "origin", coordinate: origin.coordinate,
                               title: "Điểm đi", subtitle: origin.name, kind: .origin))
        }
        if let destination {
            pins.append(MapPin(id: "destination", coordinate: destination.coordinate,
                               title: "Điểm đến", subtitle: destination.name, kind: .destination))
        }
        for (index, waypoint) in waypoints.enumerated() {
            pins.append(MapPin(id: "waypoint-\(index)", coordinate: waypoint.coordinate,
                               title: "Điểm dừng \(index + 1)", subtitle: waypoint.name, kind: .waypoint))
        }
        for place in nearbyPlaces.prefix(30) {
            pins.append(MapPin(id: place.id.uuidString, coordinate: place.coordinate,
                               title: place.name, subtitle: place.displaySubtitle, kind: .poi))
        }
        if preferences.showOnMap {
            for item in alertPinItems {
                let alert = item.alert
                var subtitle = alert.displaySubtitle
                if let distance = item.distance, distance >= 0 {
                    let gap = Format.hudDistance(distance)
                    subtitle = subtitle.isEmpty ? "còn \(gap)" : "còn \(gap) · \(subtitle)"
                }
                pins.append(MapPin(id: "alert-\(alert.id)",
                                   coordinate: alert.coordinate,
                                   title: alert.displayName,
                                   subtitle: subtitle,
                                   kind: .camera,
                                   alertKind: alert.kind,
                                   limit: alert.speedLimit,
                                   severity: Self.severity(for: alert, level: item.level),
                                   distance: item.distance))
            }
        }
        return pins
    }

    /// Khoảng cách đã đi được trên tuyến đang chọn (mét), `nil` khi chưa có GPS.
    private var alongRouteMeters: Double? {
        guard let geometry = routeGeometry, let coordinate = location.coordinate else { return nil }
        return geometry.projection(of: coordinate)?.along
    }

    /// Cảnh báo được vẽ trên bản đồ: trên tuyến (nếu có) hoặc quanh vị trí hiện tại.
    ///
    /// Trên tuyến, khoảng cách của `ActiveAlert` là mốc tuyệt đối dọc đường — phải đổi sang
    /// **khoảng cách còn lại** thì nhãn “còn 320 m” và màu mức nguy hiểm mới đúng.
    private var alertPinItems: [(alert: RoadAlert, distance: Double?, level: ActiveAlert.Level?)] {
        if !routeAlerts.isEmpty {
            let progress = alongRouteMeters
            var items: [(alert: RoadAlert, distance: Double?, level: ActiveAlert.Level?)] = routeAlerts.map { alert in
                guard let progress else { return (alert.alert, nil, nil) }
                let remaining = alert.distanceAlongRoute - progress
                let level: ActiveAlert.Level
                if remaining < -8 {
                    level = .passed
                } else if remaining <= alert.warnDistance * 0.45 {
                    level = .close
                } else if remaining <= alert.warnDistance {
                    level = .approaching
                } else {
                    level = .far
                }
                return (alert.alert, remaining, level)
            }

            // Bản đồ chỉ nên ghim cảnh báo quanh chỗ đang đứng (đỡ rối, đỡ tốn pin).
            if progress != nil {
                let window = items.filter { item in
                    guard let distance = item.distance else { return true }
                    return distance >= -600 && distance <= 5_000
                }
                if !window.isEmpty { items = window }
            }
            return Array(items.prefix(60))
        }
        return nearbyAlertPoints.prefix(40).map { ($0, nil, nil) }
    }

    /// Mức nguy hiểm 0…3 để tô màu marker trên bản đồ (AI không liên quan — thuần dữ liệu).
    static func severity(for alert: RoadAlert, level: ActiveAlert.Level?) -> Int {
        if let level {
            switch level {
            case .close: return 3
            case .approaching: return 2
            case .far: return alert.kind.isSafetyCritical ? 1 : 0
            case .passed: return 0
            }
        }
        if alert.kind.isSafetyCritical { return alert.speedLimit != nil ? 2 : 1 }
        return 0
    }

    var routePolylines: [MapPolyline] {
        var lines: [MapPolyline] = []
        let selected = selectedRoute
        for route in routes where route.id != selected?.id {
            lines.append(MapPolyline(id: "alt-\(route.id)", coordinates: route.coordinates, style: .alternate))
        }
        if let selected {
            lines.append(MapPolyline(id: "casing", coordinates: selected.coordinates, style: .casing))
            lines.append(MapPolyline(id: "primary", coordinates: selected.coordinates, style: .primary))
        }
        return lines
    }

    var currentStep: RouteStep? {
        guard let route = selectedRoute, !route.steps.isEmpty else { return nil }
        let index = min(navigationStepIndex, route.steps.count - 1)
        return route.steps[index]
    }

    var nextStep: RouteStep? {
        guard let route = selectedRoute, navigationStepIndex + 1 < route.steps.count else { return nil }
        return route.steps[navigationStepIndex + 1]
    }

    var nextAlert: ActiveAlert? {
        speedContext.nextAlert ?? aheadAlerts.first
    }

    var alertDataSummary: String {
        let total = alertDatabase.count
        let cameras = alertDatabase.cameraCount
        let imported = importedAlerts.count
        if total == 0 { return "Chưa có dữ liệu cảnh báo" }
        if imported > 0 {
            return "\(total) điểm · \(cameras) camera · \(imported) điểm do bạn nhập/OSM"
        }
        return "\(total) điểm · \(cameras) camera"
    }

    var alertSources: [AlertSource] { alertDatabase.sources }

    var importedAlertCount: Int { importedAlerts.count }

    // MARK: - Bản đồ

    func selectPreset(_ preset: MapPreset) {
        selectedPreset = preset
        searchService.updateRegion(preset.region)
        focusCoordinate = preset.coordinate
        focusToken += 1
    }

    func focus(on place: Place) {
        focusCoordinate = place.coordinate
        focusToken += 1
    }

    func focus(on coordinate: CLLocationCoordinate2D) {
        focusCoordinate = coordinate
        focusToken += 1
    }

    func focusOnUser() {
        if let coordinate = location.coordinate {
            focusCoordinate = coordinate
            focusToken += 1
            return
        }
        if location.isDenied {
            errorMessage = "Ứng dụng chưa được cấp quyền vị trí. Mở Cài đặt → Bản đồ Việt Nam → Vị trí."
            return
        }
        location.requestLocation()
        toast = "Đang xác định vị trí của bạn…"
    }

    // MARK: - Tuyến đường

    func setOrigin(_ place: Place) {
        origin = place
        remember(place)
        if destination != nil {
            Task { await planRoute() }
        }
    }

    func setDestination(_ place: Place) {
        destination = place
        remember(place)
        if origin == nil {
            origin = currentPlace
        }
        Task { await planRoute() }
    }

    func swapEndpoints() {
        guard origin != nil || destination != nil else { return }
        let oldOrigin = origin
        origin = destination
        destination = oldOrigin
        Task { await planRoute() }
    }

    func clearRoute() {
        origin = nil
        destination = nil
        waypoints = []
        routes = []
        routeScores = []
        selectedRouteID = nil
        routeSummary = nil
        routeAdvice = nil
        suggestedStops = []
        routeAlerts = []
        aheadAlerts = []
        routeGeometry = nil
        isNavigating = false
        navigationStepIndex = 0
        showRouteSheet = false
        voice.stop()
        location.stopUpdating()
    }

    func planRoute() async {
        guard let origin, let destination else { return }
        isPlanning = true
        errorMessage = nil
        defer { isPlanning = false }

        do {
            let result = try await routing.routes(from: origin,
                                                  to: destination,
                                                  mode: mode,
                                                  waypoints: waypoints)
            routes = result
            routeScores = scorer.score(result)
            aiDecision = nil
            selectedRouteID = preferredRouteID(in: result) ?? result.first?.id
            fitToken += 1
            routeSummary = nil
            routeAdvice = nil
            aiNarration = nil
            suggestedStops = []
            applySelectedRoute()
            refreshInsights()
            Task { await requestAIRanking() }
            Task { await requestAINarration() }
        } catch {
            routes = []
            routeScores = []
            selectedRouteID = nil
            routeAlerts = []
            routeGeometry = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Đổi phương tiện mặc định trong Cài đặt (áp dụng ngay nếu đang rảnh).
    func applyDefaultMode(_ newMode: TravelMode) {
        guard !isNavigating, mode != newMode else { return }
        mode = newMode
        if hasRoute {
            Task { await planRoute() }
        }
    }

    func changeMode(_ newMode: TravelMode) {
        guard mode != newMode else { return }
        mode = newMode
        Task { await planRoute() }
    }

    func selectRoute(_ route: RouteOption) {
        guard selectedRouteID != route.id else { return }
        selectedRouteID = route.id
        fitToken += 1
        applySelectedRoute()
        refreshInsights()
    }

    /// Tính lại hình học tuyến + cảnh báo dọc tuyến cho phương án đang chọn.
    private func applySelectedRoute() {
        guard let route = selectedRoute else {
            routeGeometry = nil
            routeAlerts = []
            aheadAlerts = []
            return
        }
        let geometry = RouteGeometry(coordinates: route.coordinates)
        routeGeometry = geometry
        routeAlerts = engine.alertsAlongRoute(route)
        if let coordinate = location.coordinate {
            let along = geometry.projection(of: coordinate)?.along ?? 0
            aheadAlerts = engine.aheadAlerts(from: along, alerts: routeAlerts, speedKmh: speedKmh)
        }
    }

    /// Nhận xét + đề xuất tuyến soạn offline, cập nhật ngay khi đổi phương án.
    func refreshInsights() {
        guard let route = selectedRoute else {
            routeSummary = nil
            routeAdvice = nil
            return
        }
        routeSummary = RouteInsight.summary(route: route,
                                            originName: origin?.name ?? "vị trí của bạn",
                                            destinationName: destination?.name ?? "điểm đến",
                                            alerts: routeAlerts)
        routeAdvice = RouteInsight.advice(routes: routes, scores: routeScores)
    }

    func startNavigation() {
        guard hasRoute else { return }
        navigationStepIndex = 0
        isNavigating = true
        isFollowingUser = followOnStart
        followToken += 1
        voice.reset()
        voice.isEnabled = preferences.voiceEnabled
        location.startUpdating()
        applySelectedRoute()
        if let first = selectedRoute?.steps.first {
            speak(first.instruction, key: "step-0", cooldown: 0)
        }
    }

    func stopNavigation() {
        isNavigating = false
        navigationStepIndex = 0
        isFollowingUser = true
        wasOverLimit = false
        offRouteSamples = 0
        voice.stop()
        location.stopUpdating()
    }

    /// Cập nhật bước đi + tốc độ + cảnh báo theo vị trí thật.
    func updateNavigation(with coordinate: CLLocationCoordinate2D) {
        speedKmh = location.speedKmh
        navigationCoordinate = coordinate
        if let course = location.courseDegrees {
            courseDegrees = Self.smoothHeading(old: courseDegrees, new: course)
        }

        guard let geometry = routeGeometry else {
            updateSpeedContextWithoutRoute(coordinate: coordinate)
            refreshNearbyAlertsIfNeeded()
            return
        }

        let projection = geometry.projection(of: coordinate)
        let along = projection?.along ?? 0

        if isNavigating, let route = selectedRoute, !route.steps.isEmpty {
            let current = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            var advanced = false
            while navigationStepIndex < route.steps.count - 1 {
                let step = route.steps[navigationStepIndex]
                let end = CLLocation(latitude: step.endCoordinate.latitude,
                                     longitude: step.endCoordinate.longitude)
                let threshold = max(35, min(90, step.distance * 0.25))
                if current.distance(from: end) < threshold {
                    navigationStepIndex += 1
                    advanced = true
                } else {
                    break
                }
            }

            if advanced, let step = currentStep {
                speak(RouteInsight.nextStepAnnouncement(step: step),
                      key: "step-\(navigationStepIndex)",
                      cooldown: 0)
            }

            // Nhắc trước ngã rẽ ~250 m (mỗi bước một lần).
            let toStep = distanceToNextStep
            if toStep > 45, toStep <= 250, let step = currentStep {
                speak(RouteInsight.turnAnnouncement(step: step, distance: toStep),
                      key: "turn-\(navigationStepIndex)",
                      cooldown: 120)
            }
        }

        let context = engine.speedContext(coordinate: coordinate,
                                          speedKmh: speedKmh,
                                          route: selectedRoute,
                                          geometry: geometry,
                                          alerts: routeAlerts,
                                          currentStep: currentStep,
                                          nextStep: nextStep,
                                          mode: mode)
        speedContext = context
        aheadAlerts = engine.aheadAlerts(from: along, alerts: routeAlerts, speedKmh: speedKmh)

        guard isNavigating else {
            wasOverLimit = false
            return
        }

        // Rung nhẹ khi vừa vượt quá tốc độ cho phép.
        if context.isOverLimit, !wasOverLimit {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        wasOverLimit = context.isOverLimit

        // Đã tới nơi (trong vòng 45 m) → tự kết thúc.
        if let destination,
           Self.distance(from: coordinate, to: destination.coordinate) < 45 {
            speak("Đã đến nơi.", key: "arrived", cooldown: 0)
            toast = "Đã tới \(destination.name)"
            stopNavigation()
            return
        }

        // Lệch tuyến liên tiếp → tính lại từ vị trí hiện tại.
        if let projection, projection.offset > 60 {
            offRouteSamples += 1
        } else {
            offRouteSamples = 0
        }
        if offRouteSamples >= 3,
           Date().timeIntervalSince(lastRerouteAt) > 25,
           !isPlanning,
           destination != nil {
            offRouteSamples = 0
            lastRerouteAt = Date()
            Task { await rerouteFromCurrentPosition() }
        }

        if let next = context.nextAlert, next.isImminent, next.alert.kind.isSafetyCritical {
            speak(AlertEngine.announcement(for: next, mode: mode),
                  key: "alert-\(next.id)",
                  cooldown: 60)
        }
        if context.isOverLimit, let text = AlertEngine.overspeedAnnouncement(context) {
            speak(text, key: "overspeed-\(context.limit ?? 0)", cooldown: 45)
        }
    }

    /// Làm mượt hướng đi để bản đồ không bị giật khi GPS nhảy.
    static func smoothHeading(old: Double, new: Double) -> Double {
        guard new.isFinite, new >= 0, new <= 360 else { return old }
        var delta = new - old
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        // Giữ nguyên hướng cũ nếu lệch quá 60° (rẽ gấp thường do nhiễu GPS).
        if abs(delta) > 60, old != 0 { return old + delta * 0.35 }
        return (old + delta * 0.55).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - Camera dẫn đường

    /// Khoảng cách camera tới điểm nhìn — xa dần khi đi nhanh (giống app dẫn đường thương mại).
    var navigationCameraDistance: Double {
        let speed = max(0, speedKmh)
        return min(900, max(180, 150 + speed * 4.2))
    }

    /// Tạm dừng bám theo (người dùng vừa kéo bản đồ).
    func pauseFollowing() {
        guard isNavigating, isFollowingUser else { return }
        isFollowingUser = false
    }

    /// Bám theo vị trí trở lại.
    func resumeFollowing() {
        isFollowingUser = true
        followToken += 1
        if let coordinate = location.coordinate ?? navigationCoordinate {
            navigationCoordinate = coordinate
        }
    }

    // MARK: - Tiến độ dẫn đường

    /// Quãng đường còn lại tới điểm đến (mét).
    var remainingDistance: Double {
        guard let route = selectedRoute else { return 0 }
        guard isNavigating, let geometry = routeGeometry, let coordinate = location.coordinate,
              let projection = geometry.projection(of: coordinate) else {
            return route.distance
        }
        return max(0, geometry.totalDistance - projection.along)
    }

    /// Thời gian còn lại ước tính (giây).
    var remainingTime: TimeInterval {
        guard let route = selectedRoute else { return 0 }
        guard route.distance > 1 else { return route.expectedTravelTime }
        let ratio = remainingDistance / route.distance
        return route.expectedTravelTime * max(0, min(1, ratio))
    }

    /// Tỉ lệ đã đi 0…1 (cho thanh tiến độ).
    var navigationProgress: Double {
        guard let route = selectedRoute, route.distance > 1 else { return 0 }
        return max(0, min(1, 1 - remainingDistance / route.distance))
    }

    /// Còn bao xa tới cuối bước hiện tại (mét) — số lớn hiển thị trên banner.
    var distanceToNextStep: Double {
        guard let route = selectedRoute,
              navigationStepIndex < route.steps.count,
              let coordinate = location.coordinate else { return 0 }
        let end = route.steps[navigationStepIndex].endCoordinate
        return Self.distance(from: coordinate, to: end)
    }

    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    /// Tính lại tuyến khi đi lệch đường — giữ nguyên chế độ dẫn đường và camera.
    private func rerouteFromCurrentPosition() async {
        guard let place = currentPlace, destination != nil else { return }
        let wasNavigating = isNavigating
        origin = place
        await planRoute()
        guard wasNavigating, hasRoute else { return }
        navigationStepIndex = 0
        isNavigating = true
        followToken += 1
        applySelectedRoute()
        toast = "Đã tính lại tuyến theo vị trí hiện tại"
    }

    private func updateSpeedContextWithoutRoute(coordinate: CLLocationCoordinate2D) {
        let nearby = alertDatabase.nearby(around: coordinate,
                                          radius: 350,
                                          kinds: preferences.enabledKinds,
                                          limit: 20)
        let limitAlert = nearby.first { $0.speedLimit != nil }
        var context = SpeedContext()
        context.speedKmh = speedKmh
        context.tolerance = preferences.overspeedTolerance
        context.limit = limitAlert?.speedLimit
        context.limitSource = limitAlert == nil ? .estimated : .sign
        context.roadName = limitAlert?.road
        speedContext = context
    }

    // MARK: - Cảnh báo

    func loadNearbyAlerts() {
        let center = location.coordinate ?? selectedPreset.coordinate
        nearbyAlertPoints = alertDatabase.nearby(around: center,
                                                 radius: 3_500,
                                                 kinds: preferences.enabledKinds,
                                                 limit: 80)
        if nearbyAlertPoints.isEmpty {
            alertStatusMessage = "Không có cảnh báo nào quanh đây trong bộ dữ liệu."
        } else {
            alertStatusMessage = "\(nearbyAlertPoints.count) điểm cảnh báo quanh bạn (bán kính 3,5 km)."
        }
    }

    func clearNearbyAlerts() {
        nearbyAlertPoints = []
        alertStatusMessage = nil
    }

    /// Tự nạp cảnh báo quanh vị trí khi **chưa có tuyến**, để biển báo/camera vẫn hiện trên
    /// bản đồ và thanh tốc độ có dữ liệu ngay từ lúc mở app.
    /// Giới hạn 1 lần/45 giây và chỉ tải lại khi đã đi xa hơn 400 m (đỡ tốn pin).
    func refreshNearbyAlertsIfNeeded() {
        guard preferences.showOnMap, !isNavigating else { return }
        let center = location.coordinate ?? selectedPreset.coordinate
        if let last = lastNearbyRefresh, Date().timeIntervalSince(last) < 45,
           let previous = lastNearbyCenter, Self.distance(from: previous, to: center) < 400 {
            return
        }
        lastNearbyRefresh = Date()
        lastNearbyCenter = center
        nearbyAlertPoints = alertDatabase.nearby(around: center,
                                                 radius: 2_500,
                                                 kinds: preferences.enabledKinds,
                                                 limit: 60)
    }

    /// Nhập tệp JSON do người dùng chọn trong ứng dụng Files.
    func importAlerts(from data: Data) throws -> String {
        let result = try AlertDatabase.fromJSON(data)
        guard result.database.count > 0 else {
            throw SearchError.failed("Tệp JSON không có cảnh báo hợp lệ nào.")
        }

        var merged = importedAlerts.filter { existing in
            !result.database.alerts.contains { $0.id == existing.id }
        }
        merged.append(contentsOf: result.database.alerts)
        importedAlerts = merged

        try AlertFileStore.saveImported(importedAlerts)
        rebuildDatabase()
        applySelectedRoute()

        var message = "Đã nhập \(result.database.count) cảnh báo. Tổng dữ liệu nhập: \(importedAlerts.count)."
        if !result.warnings.isEmpty {
            message += " " + result.warnings.joined(separator: " ")
        }
        alertStatusMessage = message
        return message
    }

    func clearImportedAlerts() {
        importedAlerts = []
        try? AlertFileStore.clearImported()
        rebuildDatabase()
        applySelectedRoute()
        alertStatusMessage = "Đã xoá dữ liệu cảnh báo do bạn nhập."
    }

    /// Xuất toàn bộ dữ liệu cảnh báo đang dùng ra tệp để chia sẻ.
    func exportAlerts() throws -> URL {
        try AlertFileStore.writeExport(alerts: alertDatabase.alerts, sources: alertDatabase.sources)
    }

    /// Tải biển tốc độ + camera từ OpenStreetMap cho khu vực quanh tuyến đang chọn.
    func downloadOSMAlerts() async {
        guard let route = selectedRoute else {
            alertStatusMessage = "Hãy chọn tuyến đường trước khi tải dữ liệu OpenStreetMap."
            return
        }
        isLoadingAlerts = true
        alertStatusMessage = nil
        defer { isLoadingAlerts = false }

        do {
            let alerts = try await OSMAlertService().fetchAlerts(around: route.coordinates)
            guard !alerts.isEmpty else {
                alertStatusMessage = "OpenStreetMap chưa có biển tốc độ/camera trong khu vực này."
                return
            }

            // Thay thế các mục OSM cũ, giữ nguyên dữ liệu người dùng tự nhập.
            var merged = importedAlerts.filter { $0.source != "osm" }
            merged.append(contentsOf: alerts)
            importedAlerts = merged
            try AlertFileStore.saveImported(importedAlerts)
            rebuildDatabase()
            applySelectedRoute()
            alertStatusMessage = "Đã thêm \(alerts.count) điểm từ OpenStreetMap (© OSM contributors, ODbL)."
        } catch {
            alertStatusMessage = error.localizedDescription
        }
    }

    private func rebuildDatabase() {
        let database = AlertDatabase(alerts: bundledAlerts + importedAlerts,
                                     sources: bundledSources,
                                     generatedAt: alertDatabase.generatedAt,
                                     version: alertDatabase.datasetVersion)
        alertDatabase = database
    }

    // MARK: - Điểm dừng dọc đường

    func remember(_ place: Place) {
        store.addRecent(place)
        recents = store.recents()
    }

    func toggleFavorite(_ place: Place) {
        let added = store.toggleFavorite(place)
        favorites = store.favorites()
        toast = added ? "Đã thêm vào yêu thích" : "Đã bỏ khỏi yêu thích"
    }

    func isFavorite(_ place: Place) -> Bool {
        store.isFavorite(place)
    }

    func reloadPlaces() {
        recents = store.recents()
        favorites = store.favorites()
    }

    func clearHistory() {
        store.clearRecents()
        reloadPlaces()
    }

    func clearFavorites() {
        store.clearFavorites()
        reloadPlaces()
    }

    func loadNearby(_ category: NearbyCategory) async {
        let center = location.coordinate ?? selectedPreset.coordinate
        activeCategory = category
        do {
            let places = try await searchService.nearby(category, around: center)
            nearbyPlaces = places
            fitToken += 1
            toast = places.isEmpty
                ? "Không tìm thấy \(category.title.lowercased()) quanh đây"
                : "\(places.count) \(category.title.lowercased()) quanh đây"
        } catch {
            nearbyPlaces = []
            errorMessage = error.localizedDescription
        }
    }

    func clearNearby() {
        nearbyPlaces = []
        activeCategory = nil
    }

    /// Nhấn giữ trên bản đồ → đặt làm điểm đến.
    func setDestinationFromMap(_ coordinate: CLLocationCoordinate2D) async {
        let place = await searchService.reverseGeocode(coordinate)
        destination = place
        remember(place)
        if origin == nil { origin = currentPlace }
        toast = "Điểm đến: \(place.name)"
        await planRoute()
    }

    // MARK: - AI: tìm tuyến, chọn tuyến, lập kế hoạch

    /// Chọn tuyến theo mức ưu tiên hiện tại (dùng khi AI tắt hoặc chưa trả lời).
    func preferredRouteID(in routes: [RouteOption]) -> UUID? {
        guard !routes.isEmpty else { return nil }
        guard routes.count > 1 else { return routes.first?.id }

        func score(of route: RouteOption) -> RouteScore? {
            routeScores.first { $0.routeID == route.id }
        }

        let sorted = routes.sorted { lhs, rhs in
            switch preference {
            case .fastest:
                if abs(lhs.expectedTravelTime - rhs.expectedTravelTime) > 30 {
                    return lhs.expectedTravelTime < rhs.expectedTravelTime
                }
                return lhs.distance < rhs.distance
            case .fewestCameras:
                let left = score(of: lhs)?.cameraCount ?? 0
                let right = score(of: rhs)?.cameraCount ?? 0
                if left != right { return left < right }
                return lhs.expectedTravelTime < rhs.expectedTravelTime
            case .avoidHighway:
                let left = score(of: lhs)?.expresswayShare ?? RouteScorer.expresswayShare(lhs)
                let right = score(of: rhs)?.expresswayShare ?? RouteScorer.expresswayShare(rhs)
                if abs(left - right) > 0.01 { return left < right }
                return lhs.expectedTravelTime < rhs.expectedTravelTime
            case .easiest:
                let left = score(of: lhs)?.comfortScore ?? 0
                let right = score(of: rhs)?.comfortScore ?? 0
                if abs(left - right) > 1 { return left > right }
                return lhs.steps.count < rhs.steps.count
            }
        }
        return sorted.first?.id
    }

    /// Người dùng đổi mức ưu tiên trong sheet chỉ đường.
    func setPreference(_ newValue: RoutePreference) {
        guard preference != newValue else { return }
        preference = newValue
        if let id = preferredRouteID(in: routes) {
            selectedRouteID = id
            fitToken += 1
            applySelectedRoute()
            refreshInsights()
        }
        Task { await requestAIRanking(force: true) }
    }

    /// Hỏi AI nên chọn tuyến nào; không có AI thì giữ lựa chọn theo mức ưu tiên.
    func requestAIRanking(force: Bool = false) async {
        guard routes.count > 1, aiConfig.isConfigured, aiConfig.deepPlanning else { return }
        if !force, aiDecision != nil { return }

        let decision = await planner.chooseRoute(routes: routes,
                                                 scores: routeScores,
                                                 preference: preference,
                                                 originName: origin?.name ?? "vị trí của bạn",
                                                 destinationName: destination?.name ?? "điểm đến",
                                                 alerts: routeAlerts,
                                                 config: aiConfig)
        guard let decision else { return }
        aiDecision = decision

        if routes.indices.contains(decision.routeIndex) {
            let chosen = routes[decision.routeIndex]
            if selectedRouteID != chosen.id {
                selectedRouteID = chosen.id
                fitToken += 1
                applySelectedRoute()
                refreshInsights()
            }
        }
        if !decision.warnings.isEmpty {
            toast = decision.warnings.first
        }
    }

    /// AI viết nhận xét tuyến (thay câu soạn sẵn khi có kết nối).
    func requestAINarration() async {
        guard let route = selectedRoute, let plan = aiPlan ?? currentPlan(route: route) else { return }
        guard aiConfig.isConfigured else { return }
        let text = await planner.narrate(plan: plan,
                                         route: route,
                                         score: score(for: route),
                                         config: aiConfig)
        aiNarration = text
    }

    private func currentPlan(route: RouteOption) -> RoutePlan? {
        guard let destination else { return nil }
        return RoutePlan(origin: origin,
                         destination: destination,
                         waypoints: waypoints,
                         mode: mode,
                         preference: preference,
                         avoid: [],
                         departAfter: nil,
                         explanation: nil,
                         usedAI: aiConfig.isConfigured,
                         notice: nil)
    }

    /// Người dùng nhập câu lệnh tiếng Việt trong sheet trợ lý.
    func askAI(_ text: String) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        transcript.append(AIChatBubble(role: .user, text: prompt))
        aiThinking = true
        aiError = nil
        defer { aiThinking = false }

        let result = await planner.makePlan(prompt: prompt,
                                            config: aiConfig,
                                            originFallback: currentPlace,
                                            region: selectedPreset.region)

        switch result {
        case .failure(let error):
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            aiError = message
            transcript.append(AIChatBubble(role: .assistant, text: message, isError: true))

        case .success(let plan):
            aiPlan = plan
            origin = plan.origin ?? origin ?? currentPlace
            destination = plan.destination
            waypoints = plan.waypoints
            mode = plan.mode
            preference = plan.preference
            showRouteSheet = true
            remember(plan.destination)

            await planRoute()
            await requestAINarration()

            var reply: [String] = []
            if let explanation = plan.explanation, !explanation.isEmpty {
                reply.append(explanation)
            } else {
                reply.append("Đã hiểu: \(plan.mode.title.lowercased()) từ "
                             + "\(plan.origin?.name ?? "vị trí của bạn") đến \(plan.destination.name).")
            }
            if !plan.waypoints.isEmpty {
                reply.append("Dừng tại " + plan.waypoints.map { $0.name }.joined(separator: ", ") + ".")
            }
            if let route = selectedRoute {
                reply.append("Tuyến \(route.formattedDistance), khoảng \(route.formattedDuration)"
                             + (route.arrivalText().map { ", tới nơi \($0)." } ?? "."))
            }
            if let decision = aiDecision, !decision.reason.isEmpty {
                reply.append("AI chọn: " + decision.reason)
            } else if let narration = aiNarration, !narration.isEmpty {
                reply.append(narration)
            }
            if let notice = plan.notice {
                reply.append(notice)
            }
            transcript.append(AIChatBubble(role: .assistant, text: reply.joined(separator: " ")))
        }
    }

    /// Gợi ý điểm dừng dọc tuyến — AI chọn loại điểm, app tra địa điểm thật.
    func planStopsWithAI() async {
        guard let route = selectedRoute else { return }
        isLoadingStops = true
        defer { isLoadingStops = false }

        let places = await planner.plannedStops(for: route, preference: preference, config: aiConfig)
        suggestedStops = places
        if suggestedStops.isEmpty {
            toast = "Không tìm thấy điểm dừng nào dọc tuyến."
        }
    }

    /// Chèn một điểm dừng vào giữa hành trình (lập kế hoạch nhiều chặng).
    func insertWaypoint(_ place: Place) {
        guard destination != nil else { return }
        waypoints.append(place)
        Task { await planRoute() }
    }

    func removeWaypoint(_ place: Place) {
        waypoints.removeAll { $0.id == place.id || $0.name == place.name }
        Task { await planRoute() }
    }

    // MARK: - Tốc độ & cảnh báo trên màn hình chính

    /// Tốc độ hiện tại (km/h) — 0 khi chưa có GPS.
    var liveSpeedKmh: Double { speedContext.speedKmh }

    /// Giới hạn tốc độ đang áp dụng (biển báo / vùng / ước tính TT 38).
    var liveLimit: Int? { speedContext.limit }

    var isOverLimit: Bool { speedContext.isOverLimit }

    var speedLimitSourceText: String { speedContext.limitSource.rawValue }

    /// 3 cảnh báo gần nhất phía trước, dùng cho thanh trạng thái ở màn hình chính.
    ///
    /// Có tuyến → cảnh báo dọc tuyến (khoảng cách theo đường).
    /// Chưa có tuyến → cảnh báo quanh vị trí hiện tại (khoảng cách chim bay) để màn hình
    /// chính vẫn có thông tin mà không cần mở HUD.
    var upcomingAlerts: [ActiveAlert] {
        let onRoute = aheadAlerts.filter { $0.distance >= -5 }
        if !onRoute.isEmpty {
            return Array(onRoute.sorted { $0.distance < $1.distance }.prefix(3))
        }
        guard routeAlerts.isEmpty, let coordinate = location.coordinate else { return [] }
        let warn = ActiveAlert.warnDistance(forSpeed: speedKmh,
                                            min: preferences.warnDistanceMin,
                                            max: preferences.warnDistanceMax)
        return nearbyAlertPoints
            .map { alert in
                ActiveAlert(alert: alert,
                            distance: Self.distance(from: coordinate, to: alert.coordinate),
                            warnDistance: warn,
                            distanceAlongRoute: 0)
            }
            .sorted { $0.distance < $1.distance }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - Giọng nói

    func speak(_ text: String, key: String, cooldown: TimeInterval = 40) {
        voice.isEnabled = preferences.voiceEnabled
        voice.announce(text, key: key, cooldown: cooldown)
    }

    func stopSpeaking() {
        voice.stop()
    }

    // MARK: - Tiện ích

    func dismissToast() {
        toast = nil
    }

    func dismissError() {
        errorMessage = nil
    }
}

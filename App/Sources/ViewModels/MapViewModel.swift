import Foundation
import SwiftUI
import MapKit
import CoreLocation
import Combine

struct AIChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    var isError: Bool = false
}

/// Trạng thái trung tâm của màn hình bản đồ.
@MainActor
final class MapViewModel: ObservableObject {

    // MARK: Dịch vụ

    let location: LocationService
    let searchService = SearchService()
    private let store = PlacesStore()
    private lazy var planner = AIRoutePlanner(search: searchService)
    private let voice = VoiceAlertService()

    // MARK: Dữ liệu cảnh báo

    private let bundledAlerts: [RoadAlert]
    private let bundledSources: [AlertSource]
    @Published private(set) var alertDatabase: AlertDatabase
    private var importedAlerts: [RoadAlert] = []
    private var preferences = AlertPreferences.all

    // MARK: Cấu hình AI (đồng bộ từ AppSettings)

    private(set) var config = AIConfig(baseURL: "", model: "", apiKey: "", temperature: 0.2)
    private(set) var vietmapKey = ""
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

    // MARK: Dẫn đường thông minh

    @Published var routeScores: [RouteScore] = []
    @Published var aiAdvice: String?
    @Published var aiAdviceThinking = false
    @Published var suggestedStops: [Place] = []
    @Published var isLoadingStops = false

    // MARK: Cảnh báo tốc độ / camera

    @Published var routeAlerts: [ActiveAlert] = []
    @Published var aheadAlerts: [ActiveAlert] = []
    @Published var nearbyAlertPoints: [RoadAlert] = []
    @Published var speedContext = SpeedContext()
    @Published var speedKmh: Double = 0
    @Published var showHUD = false
    @Published var isLoadingAlerts = false
    @Published var alertStatusMessage: String?

    private var routeGeometry: RouteGeometry?

    // MARK: AI

    @Published var aiThinking = false
    @Published var aiSummary: String?
    @Published var aiError: String?
    @Published var transcript: [AIChatMessage] = []

    // MARK: Địa điểm

    @Published var nearbyPlaces: [Place] = []
    @Published var activeCategory: NearbyCategory?
    @Published var recents: [Place] = []
    @Published var favorites: [Place] = []

    // MARK: UI

    @Published var toast: String?
    @Published var errorMessage: String?
    @Published var showRouteSheet = false
    @Published var mapTypeIndex = 0

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
        transcript = [
            AIChatMessage(role: .assistant,
                          text: "Chào bạn! Nhắn kiểu \"đi xe máy từ Cầu Giấy đến Hồ Tây\" hoặc "
                              + "\"chỉ đường đi bộ từ Hồ Hoàn Kiếm đến Nhà thờ Lớn\", mình sẽ tìm tuyến, "
                              + "chấm điểm từng phương án và cảnh báo tốc độ, camera trên đường.")
        ]
    }

    func syncConfig(_ config: AIConfig) {
        self.config = config
    }

    /// Đồng bộ toàn bộ cài đặt (AI, cảnh báo, VietMap).
    func syncSettings(_ settings: AppSettings) {
        config = settings.config
        vietmapKey = settings.vietmapKey
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
            for alert in alertPins {
                pins.append(MapPin(id: "alert-\(alert.id)",
                                   coordinate: alert.coordinate,
                                   title: alert.displayName,
                                   subtitle: alert.displaySubtitle,
                                   kind: .camera))
            }
        }
        return pins
    }

    /// Cảnh báo được vẽ trên bản đồ: trên tuyến (nếu có) hoặc quanh vị trí hiện tại.
    private var alertPins: [RoadAlert] {
        if !routeAlerts.isEmpty {
            return routeAlerts.prefix(40).map(\.alert)
        }
        return Array(nearbyAlertPoints.prefix(40))
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
        aiSummary = nil
        aiAdvice = nil
        suggestedStops = []
        routeAlerts = []
        aheadAlerts = []
        routeGeometry = nil
        isNavigating = false
        showHUD = false
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
            selectedRouteID = routeScores.first?.routeID ?? result.first?.id
            fitToken += 1
            aiSummary = nil
            aiAdvice = nil
            suggestedStops = []
            applySelectedRoute()

            if let route = selectedRoute {
                await generateSummary(for: route)
            }
            await generateAdvice()
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
        Task { await generateAdvice() }
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

    func startNavigation() {
        guard hasRoute else { return }
        navigationStepIndex = 0
        isNavigating = true
        voice.reset()
        voice.isEnabled = preferences.voiceEnabled
        if preferences.hudAutoOpen {
            showHUD = true
        }
        location.startUpdating()
        applySelectedRoute()
        if let first = selectedRoute?.steps.first {
            focusCoordinate = first.endCoordinate
            focusToken += 1
            speak(first.instruction, key: "step-0", cooldown: 0)
        }
    }

    func stopNavigation() {
        isNavigating = false
        navigationStepIndex = 0
        showHUD = false
        voice.stop()
        location.stopUpdating()
    }

    func presentHUD() {
        showHUD = true
        if !isNavigating {
            location.startUpdating()
        }
    }

    /// Cập nhật bước đi + tốc độ + cảnh báo theo vị trí thật.
    func updateNavigation(with coordinate: CLLocationCoordinate2D) {
        speedKmh = location.speedKmh

        guard let geometry = routeGeometry else {
            updateSpeedContextWithoutRoute(coordinate: coordinate)
            return
        }

        let projection = geometry.projection(of: coordinate)
        let along = projection?.along ?? 0

        if isNavigating, let route = selectedRoute, !route.steps.isEmpty {
            let current = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            while navigationStepIndex < route.steps.count - 1 {
                let step = route.steps[navigationStepIndex]
                let end = CLLocation(latitude: step.endCoordinate.latitude,
                                     longitude: step.endCoordinate.longitude)
                let threshold = max(35, min(90, step.distance * 0.25))
                if current.distance(from: end) < threshold {
                    navigationStepIndex += 1
                } else {
                    break
                }
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

        guard isNavigating else { return }

        if let next = context.nextAlert, next.isImminent, next.alert.kind.isSafetyCritical {
            speak(AlertEngine.announcement(for: next, mode: mode),
                  key: "alert-\(next.id)",
                  cooldown: 60)
        }
        if context.isOverLimit, let text = AlertEngine.overspeedAnnouncement(context) {
            speak(text, key: "overspeed-\(context.limit ?? 0)", cooldown: 45)
        }
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

    func suggestStopsAlongRoute() async {
        guard let geometry = routeGeometry, !geometry.isEmpty else { return }
        isLoadingStops = true
        defer { isLoadingStops = false }

        let fractions: [Double] = [0.25, 0.5, 0.75]
        var places: [Place] = []
        let categories: [NearbyCategory] = NearbyCategory.all.filter { $0.id == "fuel" }
            + NearbyCategory.all.filter { $0.id == "cafe" }

        for fraction in fractions {
            guard let point = geometry.point(at: geometry.totalDistance * fraction) else { continue }
            for category in categories {
                if let found = try? await searchService.nearby(category, around: point, radiusMeters: 2_500),
                   let first = found.first {
                    places.append(first)
                }
            }
        }

        var unique: [Place] = []
        for place in places where !unique.contains(where: { $0.name == place.name }) {
            unique.append(place)
        }

        suggestedStops = Array(unique.prefix(4))
        if suggestedStops.isEmpty {
            toast = "Không tìm thấy điểm dừng nào dọc tuyến."
        }
    }

    // MARK: - Địa điểm

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

    // MARK: - AI

    func askAI(_ text: String) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        transcript.append(AIChatMessage(role: .user, text: prompt))
        aiThinking = true
        aiError = nil
        defer { aiThinking = false }

        do {
            let intent = try await planner.interpret(prompt, config: config)
            let resolved = try await planner.resolve(intent: intent,
                                                     originFallback: currentPlace,
                                                     region: selectedPreset.region)

            origin = resolved.origin ?? origin
            destination = resolved.destination
            waypoints = resolved.waypoints
            mode = resolved.mode
            showRouteSheet = true

            await planRoute()

            let originName = origin?.name ?? "vị trí của bạn"
            var reply = resolved.explanation
                ?? "Đã tìm tuyến \(resolved.mode.title.lowercased()) từ \(originName) đến \(resolved.destination.name)."
            if !resolved.waypoints.isEmpty {
                reply += " Có dừng tại \(resolved.waypoints.map(\.name).joined(separator: ", "))."
            }
            if let route = selectedRoute {
                reply += " Tổng \(route.formattedDistance), khoảng \(route.formattedDuration)."
            }
            if let advice = aiAdvice {
                reply += " " + advice
            }
            transcript.append(AIChatMessage(role: .assistant, text: reply))
            remember(resolved.destination)
        } catch {
            let message = error.localizedDescription
            aiError = message
            transcript.append(AIChatMessage(role: .assistant, text: message, isError: true))
        }
    }

    func generateSummary(for route: RouteOption) async {
        let originName = origin?.name ?? "vị trí của bạn"
        let destinationName = destination?.name ?? "điểm đến"
        aiThinking = true
        defer { aiThinking = false }
        aiSummary = await planner.summarize(route: route,
                                            originName: originName,
                                            destinationName: destinationName,
                                            config: config)
    }

    func refreshSummary() async {
        guard let route = selectedRoute else { return }
        await generateSummary(for: route)
        await generateAdvice()
    }

    /// AI giải thích vì sao nên chọn tuyến này (có tính cảnh báo + cao tốc).
    func generateAdvice() async {
        guard routes.count > 1 else {
            aiAdvice = nil
            return
        }
        aiAdviceThinking = true
        defer { aiAdviceThinking = false }
        aiAdvice = await planner.advise(routes: routes,
                                        scores: routeScores,
                                        originName: origin?.name ?? "vị trí của bạn",
                                        destinationName: destination?.name ?? "điểm đến",
                                        config: config)
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

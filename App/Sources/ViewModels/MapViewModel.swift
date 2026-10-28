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
    private let directions = DirectionsService()
    private let store = PlacesStore()
    private lazy var planner = AIRoutePlanner(search: searchService)

    // MARK: Cấu hình AI (đồng bộ từ AppSettings)
    private(set) var config = AIConfig(baseURL: "", model: "", apiKey: "", temperature: 0.2)

    // MARK: Bản đồ
    @Published var selectedPreset: MapPreset = .vietnam
    @Published var fitToken = 0
    @Published var focusCoordinate: CLLocationCoordinate2D?
    @Published var focusToken = 0

    // MARK: Tuyến đường
    @Published var origin: Place?
    @Published var destination: Place?
    @Published var waypoints: [Place] = []
    @Published var mode: TravelMode = .automobile
    @Published var routes: [RouteOption] = []
    @Published var selectedRouteID: UUID?
    @Published var isPlanning = false
    @Published var isNavigating = false
    @Published var navigationStepIndex = 0

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
    }

    func bootstrap() {
        recents = store.recents()
        favorites = store.favorites()
        location.requestLocation()
        transcript = [
            AIChatMessage(role: .assistant,
                          text: "Chào bạn! Nhắn kiểu \"đi từ Cầu Giấy đến Hồ Tây\" hoặc "
                              + "\"chỉ đường đi bộ từ Hồ Hoàn Kiếm đến Nhà thờ Lớn\", mình sẽ tìm tuyến trên bản đồ.")
        ]
    }

    func syncConfig(_ config: AIConfig) {
        self.config = config
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
        return pins
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
        selectedRouteID = nil
        aiSummary = nil
        isNavigating = false
        navigationStepIndex = 0
        showRouteSheet = false
    }

    func planRoute() async {
        guard let origin, let destination else { return }
        isPlanning = true
        errorMessage = nil
        defer { isPlanning = false }

        do {
            let result = try await directions.routes(from: origin,
                                                     to: destination,
                                                     mode: mode,
                                                     waypoints: waypoints)
            routes = result
            selectedRouteID = result.first?.id
            fitToken += 1
            aiSummary = nil
            if let route = result.first {
                await generateSummary(for: route)
            }
        } catch {
            routes = []
            selectedRouteID = nil
            errorMessage = error.localizedDescription
        }
    }

    func changeMode(_ newMode: TravelMode) {
        guard mode != newMode else { return }
        mode = newMode
        Task { await planRoute() }
    }

    func selectRoute(_ route: RouteOption) {
        selectedRouteID = route.id
        fitToken += 1
    }

    func startNavigation() {
        guard hasRoute else { return }
        navigationStepIndex = 0
        isNavigating = true
        if let route = selectedRoute, let first = route.steps.first {
            focusCoordinate = first.endCoordinate
            focusToken += 1
        }
    }

    func stopNavigation() {
        isNavigating = false
        navigationStepIndex = 0
    }

    /// Cập nhật bước đi hiện tại theo vị trí thật.
    func updateNavigation(with coordinate: CLLocationCoordinate2D) {
        guard isNavigating, let route = selectedRoute, !route.steps.isEmpty else { return }
        let current = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        while navigationStepIndex < route.steps.count - 1 {
            let step = route.steps[navigationStepIndex]
            let end = CLLocation(latitude: step.endCoordinate.latitude,
                                 longitude: step.endCoordinate.longitude)
            if current.distance(from: end) < 40 {
                navigationStepIndex += 1
            } else {
                break
            }
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
    }

    // MARK: - Tiện ích

    func dismissToast() {
        toast = nil
    }

    func dismissError() {
        errorMessage = nil
    }
}

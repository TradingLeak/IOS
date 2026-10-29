import SwiftUI
import MapKit
import Combine

@MainActor
struct MapScreen: View {
    @StateObject private var location: LocationService
    @StateObject private var model: MapViewModel
    @StateObject private var settings = AppSettings()
    /// Gói OSM Việt Nam dùng chung giữa bản đồ và màn hình quản lý dữ liệu.
    @StateObject private var offlineMaps = OfflineMapStore.shared
    @State private var didPromptMissingMap = false
    /// HUD speedmap: dữ liệu camera/biển báo độc lập với gói bản đồ nền.
    @StateObject private var hud = SpeedmapController()
    /// Giọng nói tiếng Việt: chỉ đường + đọc cảnh báo.
    @StateObject private var voice = VoiceGuide()

    /// ID card HUD đã phát âm — chỉ đọc lại (beep/voice) khi xuất hiện card MỚI.
    @State private var seenAlertIDs: Set<String> = []

    @State private var activeSheet: ActiveSheet?
    @State private var showsDrivingHUD = false
    @Environment(\.scenePhase) private var scenePhase
    private let hudClock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Sheets

    enum SearchTarget: String, Identifiable {
        case origin
        case destination

        var id: String { rawValue }
        var title: String { self == .origin ? "Chọn điểm đi" : "Chọn điểm đến" }
    }

    enum ActiveSheet: Identifiable {
        case search(SearchTarget)
        case route
        case ai
        case settings
        case favorites
        case cities
        case offlineMap

        var id: String {
            switch self {
            case .search(let target): return "search-\(target.rawValue)"
            case .route: return "route"
            case .ai: return "ai"
            case .settings: return "settings"
            case .favorites: return "favorites"
            case .cities: return "cities"
            case .offlineMap: return "offlineMap"
            }
        }
    }

    init() {
        let location = LocationService()
        _location = StateObject(wrappedValue: location)
        _model = StateObject(wrappedValue: MapViewModel(location: location))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            MapContainer(pins: model.mapPins,
                         polylines: model.routePolylines,
                         focusCoordinate: model.focusCoordinate,
                         focusToken: model.focusToken,
                         fitToken: model.fitToken,
                         mapProvider: settings.mapProvider,
                         offlineDatabase: offlineMaps.database,
                         mapTypeIndex: settings.mapTypeIndex,
                         showTraffic: settings.showTraffic,
                         showPOIs: settings.showPOIs,
                         onSelectPin: handlePinTap,
                         onLongPress: { coordinate in
                             Task { await model.setDestinationFromMap(coordinate) }
                         })
                .ignoresSafeArea()

            VStack(spacing: 10) {
                header
                categoryChips
                if model.isNavigating { navigationBanner }
                if hud.isReady {
                    SpeedHudOverlay(controller: hud)
                }
                Spacer(minLength: 0)
                mapSourceNotice
                bottomPanel
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    sideControls
                        .padding(.trailing, 14)
                        .padding(.bottom, 172)
                }
            }
        }
        .overlay(alignment: .bottom) { toastView }
        .animation(.easeInOut(duration: 0.22), value: model.toast)
        .alert("Không thực hiện được", isPresented: errorBinding) {
            Button("Đóng", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear {
            model.bootstrap()
            model.syncConfig(settings.config)
            hud.loadBundled()
            syncLocationMode()
        }
        .task {
            await offlineMaps.restore()
            if !offlineMaps.isReady, !didPromptMissingMap, activeSheet == nil, !showsDrivingHUD {
                didPromptMissingMap = true
                activeSheet = .offlineMap
            }
        }
        .onChange(of: settings.mapProvider) { provider in
            if provider == .openStreetMap, !offlineMaps.isReady, activeSheet == nil {
                activeSheet = .offlineMap
            }
        }
        .onChange(of: model.isNavigating) { navigating in
            syncLocationMode()
            // Không stop() khi kết thúc: thông báo "Đã đến nơi" (nếu có) phải kịp phát.
            if navigating, settings.voiceGuidance, let first = model.currentStep {
                voice.speak("Bắt đầu chỉ đường. \(first.instruction)")
            }
        }
        .onChange(of: model.navigationStepIndex) { _ in
            guard model.isNavigating, settings.voiceGuidance,
                  let step = model.currentStep else { return }
            voice.speak(step.instruction)
        }
        .onChange(of: model.navAnnouncement) { announcement in
            guard let announcement else { return }
            if settings.voiceGuidance {
                switch announcement {
                case .arrived:
                    voice.speak("Đã đến nơi.")
                case .rerouted:
                    voice.speak("Bạn đi lệch tuyến. Đang đi theo tuyến mới.")
                case .rerouteFailed:
                    voice.speak("Không tính lại được tuyến. Tiếp tục theo tuyến cũ.")
                }
            }
            model.navAnnouncement = nil
        }
        .onChange(of: hud.alerts) { alerts in
            let currentIDs = Set(alerts.map(\.id))
            let newIDs = currentIDs.subtracting(seenAlertIDs)
            seenAlertIDs = currentIDs
            guard scenePhase == .active, !newIDs.isEmpty,
                  let first = alerts.first(where: { newIDs.contains($0.id) }) else { return }
            let urgent: Set<HazardAlert.Kind> = [.camera, .noOvertaking, .speedLimitChange]
            if settings.alertBeep, urgent.contains(first.kind) {
                AlertSound.beep()
            }
            if settings.voiceGuidance {
                voice.speak(VoiceGuide.alertText(first))
            }
        }
        .onReceive(model.location.$lastLocation) { lastLocation in
            guard scenePhase == .active, location.isAuthorized, let lastLocation else {
                hud.resetLocation()
                return
            }
            hud.update(with: lastLocation)
        }
        .onReceive(hudClock) { now in hud.invalidateIfNeeded(now: now) }
        .onChange(of: showsDrivingHUD) { _ in syncLocationMode() }
        .onChange(of: scenePhase) { phase in
            syncLocationMode()
            if phase != .active {
                hud.resetLocation()
                seenAlertIDs = []
                voice.stop()
            }
        }
        .fullScreenCover(isPresented: $showsDrivingHUD) {
            DrivingHUDScreen(location: location, controller: hud, settings: settings, voice: voice)
        }
        .onChange(of: settings.baseURL) { _ in model.syncConfig(settings.config) }
        .onChange(of: settings.model) { _ in model.syncConfig(settings.config) }
        .onChange(of: settings.apiKey) { _ in model.syncConfig(settings.config) }
        .onChange(of: settings.temperature) { _ in model.syncConfig(settings.config) }
        .onChange(of: model.showRouteSheet) { value in
            if value {
                model.showRouteSheet = false
                activeSheet = .route
            }
        }
        .onChange(of: model.toast) { value in
            guard let value else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                if model.toast == value { model.dismissToast() }
            }
        }
        .onReceive(model.location.$coordinate) { coordinate in
            if let coordinate {
                model.updateNavigation(with: coordinate)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .search(let target):
                SearchSheet(searchService: model.searchService,
                            title: target.title,
                            currentPlace: model.currentPlace,
                            recents: model.recents,
                            favorites: model.favorites,
                            onSelect: { place in
                                activeSheet = nil
                                if target == .origin {
                                    model.setOrigin(place)
                                } else {
                                    model.setDestination(place)
                                }
                                model.focus(on: place)
                            },
                            onUseCurrentLocation: {
                                guard let place = model.currentPlace else { return nil }
                                return place
                            })
            case .route:
                RouteSheet(model: model, settings: settings) {
                    activeSheet = .search(.origin)
                } onPickDestination: {
                    activeSheet = .search(.destination)
                }
            case .ai:
                AIAssistantSheet(model: model, settings: settings) {
                    activeSheet = nil
                }
            case .offlineMap:
                OfflineMapDownloadView(store: offlineMaps) { settings.mapProvider = .apple }
            case .settings:
                SettingsView(settings: settings, model: model, hud: hud)
            case .favorites:
                FavoritesSheet(favorites: model.favorites,
                               recents: model.recents,
                               onSelect: { place in
                                   activeSheet = nil
                                   model.setDestination(place)
                                   model.focus(on: place)
                               })
            case .cities:
                CityPickerSheet(selected: model.selectedPreset) { preset in
                    activeSheet = nil
                    model.selectPreset(preset)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Menu {
                Section("Lái xe") {
                    Button { showsDrivingHUD = true } label: {
                        Label("HUD lái xe offline", systemImage: "speedometer")
                    }
                }
                Section("Trợ lý") {
                    Button { activeSheet = .ai } label: {
                        Label("Hỏi trợ lý AI", systemImage: "sparkles")
                    }
                }
                Section("Địa điểm") {
                    Button { activeSheet = .favorites } label: {
                        Label("Yêu thích & gần đây", systemImage: "star")
                    }
                    Button { activeSheet = .cities } label: {
                        Label("Chọn thành phố", systemImage: "building.2")
                    }
                }
                Section("Bản đồ") {
                    Button { activeSheet = .offlineMap } label: {
                        Label("Tải bản đồ Việt Nam offline", systemImage: "arrow.down.circle")
                    }
                    Picker("Nguồn bản đồ", selection: $settings.mapProvider) {
                        ForEach(MapProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    if settings.mapProvider == .apple {
                        Picker("Kiểu bản đồ", selection: $settings.mapTypeIndex) {
                            Text("Tiêu chuẩn").tag(0)
                            Text("Vệ tinh lai").tag(1)
                            Text("Vệ tinh").tag(2)
                            Text("Tối giản").tag(3)
                        }
                        Toggle("Giao thông", isOn: $settings.showTraffic)
                    }
                }
                Section {
                    Button { activeSheet = .settings } label: {
                        Label("Cài đặt AI & bản đồ", systemImage: "gearshape")
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(AppTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(AppTheme.cardStroke, lineWidth: 1)
                            )
                    )
                    .softShadow()
            }

            Button {
                activeSheet = .search(.destination)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Tìm địa điểm, địa chỉ…")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .padding(.horizontal, 15)
                .frame(height: 46)
                .frame(maxWidth: .infinity, alignment: .leading)
                .floatingCard(cornerRadius: 15)
            }
            .buttonStyle(.plain)

            Button {
                activeSheet = .cities
            } label: {
                Image(systemName: "map")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(AppTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(AppTheme.cardStroke, lineWidth: 1)
                            )
                    )
                    .softShadow()
            }
            .buttonStyle(.plain)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NearbyCategory.all) { category in
                    FilterChip(title: category.title,
                               symbol: category.symbol,
                               isSelected: model.activeCategory == category) {
                        if model.activeCategory == category {
                            model.clearNearby()
                        } else {
                            Task { await model.loadNearby(category) }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
        }
        .scrollClipDisabledIfAvailable()
    }

    // MARK: - Side controls

    private var sideControls: some View {
        VStack(spacing: 10) {
            FloatingIconButton(symbol: "speedometer", accessibilityLabel: "Mở HUD lái xe offline") {
                showsDrivingHUD = true
            }
            FloatingIconButton(symbol: "location.fill",
                               active: location.isAuthorized,
                               accessibilityLabel: "Về vị trí của tôi") {
                model.focusOnUser()
            }
            FloatingIconButton(symbol: model.hasRoute ? "arrow.up.left.and.arrow.down.right" : "square.stack.3d.up.fill",
                               accessibilityLabel: model.hasRoute ? "Xem toàn bộ tuyến" : "Đổi nguồn Apple Maps / OpenStreetMap") {
                if model.hasRoute {
                    model.fitToken += 1
                } else {
                    settings.mapProvider = settings.mapProvider == .apple ? .openStreetMap : .apple
                }
            }
            if settings.mapProvider == .apple {
                FloatingIconButton(symbol: "point.topleft.down.curvedto.point.bottomright.up",
                                   active: settings.showTraffic,
                                   accessibilityLabel: "Bật/tắt giao thông") {
                    settings.showTraffic.toggle()
                }
            }
            FloatingIconButton(symbol: "sparkles",
                               active: model.aiThinking,
                               accessibilityLabel: "Trợ lý AI") {
                activeSheet = .ai
            }
        }
    }

    @ViewBuilder
    private var mapSourceNotice: some View {
        if settings.mapProvider == .openStreetMap {
            VStack(spacing: 3) {
                Link("© OpenStreetMap contributors", destination: OpenStreetMapOverlay.copyrightURL)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minHeight: 28)
                if let attribution = offlineMaps.database?.manifest.attribution {
                    Text(attribution).font(.system(size: 9)).multilineTextAlignment(.center)
                }
                if !offlineMaps.isReady {
                    Button("Chưa có bản đồ Việt Nam · Bấm để tải") { activeSheet = .offlineMap }
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(offlineMaps.isReady
                     ? "OSM Việt Nam: offline · Tìm kiếm & tính tuyến: Apple Maps"
                     : "Cần tải gói OSM Việt Nam trước khi xem bản đồ")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Bottom

    @ViewBuilder
    private var bottomPanel: some View {
        if let route = model.selectedRoute {
            routeCard(route)
        } else {
            actionBar
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                activeSheet = .ai
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Trợ lý AI")
                            .font(.system(size: 15, weight: .semibold))
                        Text(settings.config.isConfigured
                             ? "Model: \(settings.model)"
                             : "Nhập câu tiếng Việt để tìm tuyến")
                            .font(.system(size: 11))
                            .opacity(0.85)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .primaryGradientBackground(cornerRadius: 18)
            }
            .buttonStyle(.plain)

            Button {
                activeSheet = .route
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .primaryGradientBackground(cornerRadius: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chỉ đường")
        }
    }

    private func routeCard(_ route: RouteOption) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(destinationTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        Label(route.formattedDuration, systemImage: "clock.fill")
                        Label(route.formattedDistance, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        Label(route.mode.title, systemImage: route.mode.symbol)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
                Button {
                    model.clearRoute()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            if let summary = model.aiSummary, !summary.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            HStack(spacing: 10) {
                Button {
                    activeSheet = .route
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                        Text("Chi tiết")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.subtleFill)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    model.startNavigation()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.north.fill")
                        Text("Bắt đầu")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .primaryGradientBackground(cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .floatingCard()
    }

    private var destinationTitle: String {
        let destination = model.destination?.name ?? "Điểm đến"
        let origin = model.origin?.name ?? "Vị trí của bạn"
        return "\(destination) · từ \(origin)"
    }

    // MARK: - Navigation banner

    private var navigationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: model.currentStep?.symbol ?? "location.north.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(AppTheme.accentGradient))

            VStack(alignment: .leading, spacing: 2) {
                Text(model.currentStep?.instruction ?? "Đang di chuyển")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                if let next = model.nextStep {
                    Text("Sau đó: \(next.instruction)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                model.stopNavigation()
            } label: {
                Text("Kết thúc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.danger.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .floatingCard()
    }

    // MARK: - Toast & helpers

    @ViewBuilder
    private var toastView: some View {
        if let toast = model.toast {
            Text(toast)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .padding(.bottom, 132)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { value in if !value { model.dismissError() } }
        )
    }

    /// HUD tự lấy GPS liên tục ngay cả khi chưa chọn tuyến. Không yêu cầu quyền nền.
    private func syncLocationMode() {
        let driving = model.isNavigating || showsDrivingHUD
        location.setNavigationMode(driving && scenePhase == .active)
        if driving && scenePhase == .active {
            location.startUpdating()
        } else {
            location.stopUpdating()
        }
    }

    private func handlePinTap(_ pin: MapPin) {
        switch pin.kind {
        case .poi, .favorite:
            let place = Place(name: pin.title, subtitle: pin.subtitle, coordinate: pin.coordinate)
            model.setDestination(place)
            model.focus(on: place)
        case .origin:
            if let origin = model.origin {
                model.focus(on: origin)
            }
        case .destination:
            if let destination = model.destination {
                model.focus(on: destination)
            }
        case .waypoint:
            break
        }
    }
}

// MARK: - Tiện ích tương thích phiên bản

private extension View {
    @ViewBuilder
    func scrollClipDisabledIfAvailable() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollClipDisabled()
        } else {
            self
        }
    }
}

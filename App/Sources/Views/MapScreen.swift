import SwiftUI
import MapKit
import Combine

@MainActor
struct MapScreen: View {
    @StateObject private var location: LocationService
    @StateObject private var model: MapViewModel
    @StateObject private var settings = AppSettings()

    @State private var activeSheet: ActiveSheet?

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

        var id: String {
            switch self {
            case .search(let target): return "search-\(target.rawValue)"
            case .route: return "route"
            case .ai: return "ai"
            case .settings: return "settings"
            case .favorites: return "favorites"
            case .cities: return "cities"
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
                Spacer(minLength: 0)
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
            case .settings:
                SettingsView(settings: settings, model: model)
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
                    Picker("Kiểu bản đồ", selection: Binding(
                        get: { settings.mapTypeIndex },
                        set: { settings.mapTypeIndex = $0 }
                    )) {
                        Text("Tiêu chuẩn").tag(0)
                        Text("Vệ tinh lai").tag(1)
                        Text("Vệ tinh").tag(2)
                        Text("Tối giản").tag(3)
                    }
                    Toggle("Giao thông", isOn: Binding(
                        get: { settings.showTraffic },
                        set: { settings.showTraffic = $0 }
                    ))
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
            FloatingIconButton(symbol: "location.fill",
                               active: location.isAuthorized,
                               accessibilityLabel: "Về vị trí của tôi") {
                model.focusOnUser()
            }
            FloatingIconButton(symbol: model.hasRoute ? "arrow.up.left.and.arrow.down.right" : "square.stack.3d.up.fill",
                               accessibilityLabel: model.hasRoute ? "Xem toàn bộ tuyến" : "Đổi kiểu bản đồ") {
                if model.hasRoute {
                    model.fitToken += 1
                } else {
                    settings.mapTypeIndex = (settings.mapTypeIndex + 1) % 4
                }
            }
            FloatingIconButton(symbol: "point.topleft.down.curvedto.point.bottomright.up",
                               active: settings.showTraffic,
                               accessibilityLabel: "Bật/tắt giao thông") {
                settings.showTraffic.toggle()
            }
            FloatingIconButton(symbol: "sparkles",
                               active: model.aiThinking,
                               accessibilityLabel: "Trợ lý AI") {
                activeSheet = .ai
            }
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

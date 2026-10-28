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
        case alerts

        var id: String {
            switch self {
            case .search(let target): return "search-\(target.rawValue)"
            case .route: return "route"
            case .ai: return "ai"
            case .settings: return "settings"
            case .favorites: return "favorites"
            case .cities: return "cities"
            case .alerts: return "alerts"
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
                         showPOIs: settings.showPOIs && !model.isNavigating,
                         isNavigating: model.isNavigating,
                         navigationCoordinate: model.navigationCoordinate,
                         navigationHeading: model.courseDegrees,
                         navigationDistance: model.navigationCameraDistance,
                         navigationPitch3D: settings.navigationPitch3D,
                         isFollowingUser: model.isFollowingUser,
                         followToken: model.followToken,
                         onFollowBroken: { model.pauseFollowing() },
                         onSelectPin: handlePinTap,
                         onLongPress: { coordinate in
                             Task { await model.setDestinationFromMap(coordinate) }
                         })
                .ignoresSafeArea()

            VStack(spacing: 10) {
                if model.isNavigating {
                    navigationBanner
                } else {
                    header
                    categoryChips
                }
                if let alert = model.nextAlert, model.isNavigating, alert.isImminent {
                    alertBanner(alert)
                }
                Spacer(minLength: 0)
                if model.hasRoute || model.isNavigating || location.isAuthorized {
                    statusStrip
                }
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
                        .padding(.bottom, 158)
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
            model.syncSettings(settings)
        }
        .onChange(of: settings.vietmapAPIKey) { _ in model.syncSettings(settings) }
        .onChange(of: settings.voiceAlerts) { _ in model.syncSettings(settings) }
        .onChange(of: settings.showAlertPins) { _ in model.syncSettings(settings) }
        .onChange(of: settings.overspeedTolerance) { _ in model.syncSettings(settings) }
        .onChange(of: settings.alertKinds) { _ in model.syncSettings(settings) }
        .onChange(of: settings.followUserInNavigation) { _ in model.syncSettings(settings) }
        .onChange(of: settings.aiBaseURL) { _ in model.syncSettings(settings) }
        .onChange(of: settings.aiModel) { _ in model.syncSettings(settings) }
        .onChange(of: settings.aiAPIKey) { _ in model.syncSettings(settings) }
        .onChange(of: settings.aiEnabled) { _ in model.syncSettings(settings) }
        .onChange(of: settings.aiDeepPlanning) { _ in model.syncSettings(settings) }
        .onChange(of: settings.routePreference) { _ in model.syncSettings(settings) }
        .onChange(of: settings.defaultMode) { value in
            model.syncSettings(settings)
            model.applyDefaultMode(value)
        }
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        activeSheet = .settings
                    }
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
            case .alerts:
                AlertsSheet(model: model, settings: settings)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Menu {
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
                        Label("Cài đặt", systemImage: "gearshape")
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
            // 3D / 2D luôn đổi được, kể cả khi chỉ xem bản đồ
            FloatingIconButton(symbol: settings.navigationPitch3D ? "view.3d" : "map",
                               active: settings.navigationPitch3D,
                               accessibilityLabel: settings.navigationPitch3D
                               ? "Đang 3D — chuyển sang 2D" : "Đang 2D — chuyển sang 3D") {
                settings.navigationPitch3D.toggle()
                if model.isNavigating { model.resumeFollowing() }
            }

            if model.isNavigating, !model.isFollowingUser {
                FloatingIconButton(symbol: "location.north.fill",
                                   active: true,
                                   accessibilityLabel: "Bám theo vị trí") {
                    model.resumeFollowing()
                }
            }

            FloatingIconButton(symbol: "camera.fill",
                               active: !model.routeAlerts.isEmpty,
                               badge: model.routeAlerts.isEmpty ? nil : "\(model.routeAlerts.count)",
                               accessibilityLabel: "Cảnh báo giao thông") {
                activeSheet = .alerts
            }

            FloatingIconButton(symbol: "sparkles",
                               active: model.aiThinking,
                               accessibilityLabel: "Trợ lý AI") {
                activeSheet = .ai
            }

            if !model.isNavigating {
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
            }

            FloatingIconButton(symbol: settings.showTraffic ? "car.2.fill" : "car.fill",
                               active: settings.showTraffic,
                               accessibilityLabel: "Bật/tắt mật độ giao thông") {
                settings.showTraffic.toggle()
            }
        }
    }

    // MARK: - Tốc độ hiện tại & cảnh báo sắp tới (màn hình chính)

    private var statusStrip: some View {
        HStack(alignment: .center, spacing: 12) {
            // Tốc độ hiện tại
            VStack(spacing: -2) {
                Text("\(Int(model.liveSpeedKmh.rounded()))")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.isOverLimit ? AppTheme.danger : Color.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                Text("km/h")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 58)

            if let limit = model.liveLimit {
                SpeedLimitSignView(limit: limit, size: 38, muted: true)
            } else {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                    .frame(width: 38, height: 38)
            }

            Rectangle()
                .fill(AppTheme.cardStroke)
                .frame(width: 1, height: 38)

            // Danh sách cảnh báo sắp tới
            VStack(alignment: .leading, spacing: 4) {
                if model.upcomingAlerts.isEmpty {
                    Text(model.isNavigating ? "Không có cảnh báo phía trước" : "Cảnh báo hiện trên bản đồ")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(model.speedLimitSourceText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    ForEach(model.upcomingAlerts.prefix(2)) { alert in
                        HStack(spacing: 6) {
                            Image(systemName: alert.alert.kind.symbol)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(alert.alert.kind.tint))
                            Text(alert.alert.kind.shortTitle)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(Format.hudDistance(max(0, alert.distance)))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(alert.levelColor)
                        }
                    }
                    if model.upcomingAlerts.count > 2 {
                        Text("+\(model.upcomingAlerts.count - 2) cảnh báo nữa")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .floatingCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tốc độ \(Int(model.liveSpeedKmh.rounded())) km/h, giới hạn "
                            + "\(model.liveLimit.map { "\($0)" } ?? "chưa rõ"), "
                            + "\(model.upcomingAlerts.count) cảnh báo phía trước")
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
                activeSheet = .route
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 17, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Chỉ đường")
                            .font(.system(size: 15, weight: .semibold))
                        Text(model.destination?.name ?? "Nhập điểm đến để tìm tuyến")
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
                activeSheet = .favorites
            } label: {
                Image(systemName: "star.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 56, height: 56)
                    .floatingCard(cornerRadius: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Yêu thích & gần đây")
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
                        if let arrival = route.arrivalText() {
                            Text("· \(arrival)")
                        }
                        Label(route.mode.title, systemImage: route.mode.symbol)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
                if let score = model.score(for: route) {
                    ScoreBadge(score: score)
                }
                Button {
                    model.clearRoute()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Label("\(model.routeAlerts.count) cảnh báo", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(model.routeAlerts.isEmpty ? Color.secondary : AppTheme.warning)
                if route.isEstimatedProfile {
                    Label("ước lượng xe máy", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11, weight: .medium))

            if let advice = model.routeAdvice, !advice.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.accentDeep)
                    Text(advice)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
            }

            if let summary = model.routeSummary, !summary.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.bubble.fill")
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
                    activeSheet = .ai
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hỏi trợ lý AI về tuyến này")

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
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                Image(systemName: model.currentStep?.symbol ?? "location.north.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppTheme.accentGradient))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if model.distanceToNextStep > 0 {
                            Text(Format.hudDistance(model.distanceToNextStep))
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                        }
                        Text(model.currentStep?.instruction ?? "Đang di chuyển")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(2)
                    }
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

            HStack(spacing: 12) {
                Label("Còn \(Format.distance(model.remainingDistance))",
                      systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Label(Format.remaining(model.remainingTime), systemImage: "clock.fill")
                if let arrival = Format.arrival(after: model.remainingTime) {
                    Text("· \(arrival)")
                }
                Spacer(minLength: 0)
                if let limit = model.speedContext.limit {
                    SpeedLimitSignView(limit: limit, size: 24, muted: true)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)

            ProgressView(value: model.navigationProgress)
                .tint(AppTheme.accent)
                .scaleEffect(x: 1, y: 0.7, anchor: .center)
        }
        .padding(12)
        .floatingCard()
    }

    // MARK: - Băng cảnh báo

    private func alertBanner(_ alert: ActiveAlert) -> some View {
        HStack(spacing: 11) {
            Image(systemName: alert.alert.kind.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(alert.alert.kind.tint))

            VStack(alignment: .leading, spacing: 1) {
                Text(alert.alert.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(alert.distanceText
                     + (alert.alert.speedLimit.map { " · giới hạn \($0) km/h" } ?? ""))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(alert.levelColor)
            }

            Spacer(minLength: 0)

            if let limit = alert.alert.speedLimit {
                SpeedLimitSignView(limit: limit, size: 32, muted: true)
            }
        }
        .padding(10)
        .floatingCard(cornerRadius: 16)
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
        case .camera:
            model.focus(on: pin.coordinate)
            model.toast = pin.title
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

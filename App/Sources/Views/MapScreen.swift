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
        case reportIncident

        var id: String {
            switch self {
            case .search(let target): return "search-\(target.rawValue)"
            case .route: return "route"
            case .ai: return "ai"
            case .settings: return "settings"
            case .favorites: return "favorites"
            case .cities: return "cities"
            case .alerts: return "alerts"
            case .reportIncident: return "report-incident"
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

            // Toàn bộ nút nằm trong MỘT VStack: không còn lớp phủ neo tuyệt đối
            // (trước đây `sideControls` dùng padding.bottom cứng 158 nên đè lên
            // thẻ dẫn đường / dải làn / banner cảnh báo trên máy màn hình nhỏ).
            GeometryReader { proxy in
                let compact = proxy.size.height < 720
                VStack(spacing: compact ? 8 : 10) {
                    topStack(compact: compact)

                    Spacer(minLength: 8)

                    if model.toast != nil {
                        toastView
                    }
                    bottomCluster(compact: compact)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
            case .reportIncident:
                ReportIncidentSheet(model: model, settings: settings)
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

    /// Cột nút phụ. Tối đa 4 nút để không chiếm quá 1/3 chiều cao màn hình;
    /// các tuỳ chọn ít dùng gom vào menu “…” (bấm một lần là thấy).
    private func sideControls(compact: Bool) -> some View {
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

            // Máy màn hình thấp: đưa báo cáo sự cố vào menu để cột nút ngắn lại.
            if !compact {
                FloatingIconButton(symbol: "exclamationmark.bubble.fill",
                                   active: !model.activeIncidents.isEmpty,
                                   badge: model.activeIncidents.isEmpty ? nil : "\(model.activeIncidents.count)",
                                   accessibilityLabel: "Báo cáo sự cố trên đường") {
                    activeSheet = .reportIncident
                }
            }

            moreMenu(compact: compact)
        }
    }

    /// Menu gom các nút ít dùng: AI, mật độ giao thông, kiểu bản đồ, về vị trí, xem tuyến.
    private func moreMenu(compact: Bool) -> some View {
        Menu {
            if compact {
                Button {
                    activeSheet = .reportIncident
                } label: {
                    Label("Báo cáo sự cố", systemImage: "exclamationmark.bubble.fill")
                }
            }

            Button {
                activeSheet = .ai
            } label: {
                Label("Trợ lý AI", systemImage: "sparkles")
            }

            Button {
                settings.showTraffic.toggle()
            } label: {
                Label(settings.showTraffic ? "Tắt mật độ giao thông" : "Bật mật độ giao thông",
                      systemImage: settings.showTraffic ? "car.2.fill" : "car.fill")
            }

            if !model.isNavigating {
                Button {
                    model.focusOnUser()
                } label: {
                    Label("Về vị trí của tôi", systemImage: "location.fill")
                }

                if model.hasRoute {
                    Button {
                        model.fitToken += 1
                    } label: {
                        Label("Xem toàn bộ tuyến", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                } else {
                    Button {
                        settings.mapTypeIndex = (settings.mapTypeIndex + 1) % 4
                    } label: {
                        Label("Đổi kiểu bản đồ", systemImage: "square.stack.3d.up.fill")
                    }
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(AppTheme.card)
                    .overlay(Circle().stroke(AppTheme.cardStroke, lineWidth: 1))
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }
            .frame(width: 46, height: 46)
            .softShadow()
        }
        .accessibilityLabel("Thêm tuỳ chọn bản đồ")
    }

    // MARK: - Thẻ tốc độ & cảnh báo (kiểu app dẫn đường VN: khối tối gọn)

    /// Nền tối dùng chung cho thẻ tốc độ, banner cảnh báo và nút pill.
    static let hudSurface = Color(red: 0.11, green: 0.15, blue: 0.20)

    /// Thẻ tốc độ: biển giới hạn → nhãn → số km/h → cảnh báo kế tiếp.
    /// Gọn trong ~132 pt nên không tranh chỗ với bản đồ.
    private func speedCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let limit = model.liveLimit {
                SpeedLimitSignView(limit: limit, size: compact ? 48 : 56, muted: true)
                    .padding(.bottom, compact ? 7 : 9)
            } else {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: (compact ? 48 : 56) * 0.55, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: compact ? 48 : 56, height: compact ? 48 : 56)
                    .padding(.bottom, compact ? 7 : 9)
            }

            Text("TỐC ĐỘ HIỆN TẠI")
                .font(.system(size: 8.5, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(model.liveSpeedKmh.rounded()))")
                    .font(.system(size: compact ? 25 : 27, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.isOverLimit
                                     ? Color(red: 1.0, green: 0.42, blue: 0.38)
                                     : Color.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                Text("km/h")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }

            if let alert = model.nextAlert {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.vertical, 6)

                HStack(spacing: 5) {
                    Image(systemName: alert.alert.kind.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(alert.alert.kind.tint)
                    Text(alert.alert.kind.shortTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(Format.hudDistance(max(0, alert.distance)))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
        }
        .padding(compact ? 10 : 12)
        .frame(width: compact ? 116 : 132, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Self.hudSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tốc độ \(Int(model.liveSpeedKmh.rounded())) km/h, giới hạn "
                            + "\(model.liveLimit.map { "\($0)" } ?? "chưa rõ")"
                            + (model.nextAlert.map { ", cảnh báo \($0.alert.kind.shortTitle) "
                                + "cách \(Format.hudDistance(max(0, $0.distance)))" } ?? ""))
    }

    /// Hai nút nhanh kiểu pill dưới thẻ tốc độ: về giữa / tắt âm cảnh báo.
    private var quickPills: some View {
        VStack(alignment: .leading, spacing: 8) {
            pillButton(symbol: "location.fill", title: "Về giữa") {
                model.focusOnUser()
            }
            pillButton(symbol: settings.voiceAlerts ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       title: settings.voiceAlerts ? "Tắt âm cảnh báo" : "Bật âm cảnh báo") {
                settings.voiceAlerts.toggle()
            }
        }
    }

    private func pillButton(symbol: String, title: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(Capsule().fill(Self.hudSurface))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: - Bố cục dọc (không chồng lấn)

    /// Thẻ phía trên: dẫn đường (thẻ chỉ dẫn + làn + cảnh báo) hoặc tìm kiếm.
    @ViewBuilder
    private func topStack(compact: Bool) -> some View {
        if model.isNavigating {
            navigationBanner(compact: compact)
            if !compact {
                laneStrip
            }
            if let alert = model.nextAlert, alert.isImminent {
                alertBanner(alert)
            }
        } else {
            header
            categoryChips
        }
    }

    /// Cụm đáy: (nút nhanh + thẻ tốc độ | cột nút phụ) → thanh tuyến.
    /// Mọi thứ xếp trong VStack nên không bao giờ đè lên nhau.
    @ViewBuilder
    private func bottomCluster(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 10) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    if !model.isNavigating {
                        quickPills
                    }
                    if showsSpeedCard {
                        speedCard(compact: compact)
                    }
                }
                Spacer(minLength: 0)
                sideControls(compact: compact)
            }

            bottomPanel
        }
    }

    /// Hiện thẻ tốc độ khi đang dẫn đường, đã có tuyến, hoặc đã được cấp quyền vị trí.
    private var showsSpeedCard: Bool {
        model.isNavigating || model.hasRoute || location.isAuthorized
    }

    /// Thanh đáy khi đang dẫn đường: còn bao xa / bao lâu / giờ tới + Kết thúc.
    private var navigationBar: some View {
        VStack(spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Format.distance(model.remainingDistance))
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                        Text(Format.remaining(model.remainingTime))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text("Đến")
                            .foregroundStyle(.secondary)
                        Text(model.destination?.name ?? "điểm đến")
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        if let arrival = Format.arrival(after: model.remainingTime) {
                            Text("· \(arrival)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 11.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    model.stopNavigation()
                } label: {
                    Text("Kết thúc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(Capsule().fill(AppTheme.danger))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kết thúc dẫn đường")
            }

            ProgressStripe(fraction: 1 - model.navigationProgress, tint: AppTheme.accent)
        }
        .padding(12)
        .floatingCard()
    }

    // MARK: - Bottom

    @ViewBuilder
    private var bottomPanel: some View {
        if model.isNavigating {
            navigationBar
        } else if let route = model.selectedRoute {
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

    /// Nội dung chia sẻ của tuyến đang chọn (tin nhắn + link Apple Maps).
    private func shareMessage(_ route: RouteOption) -> String? {
        guard let destination = model.destination else { return nil }
        return RouteShare.message(origin: model.origin,
                                  destination: destination,
                                  waypoints: model.waypoints,
                                  route: route,
                                  alerts: model.routeAlerts.count,
                                  mode: route.mode)
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
                if let message = shareMessage(route) {
                    ShareLink(item: message) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .accessibilityLabel("Chia sẻ tuyến")
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

    private func navigationBanner(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 9) {
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

            if !compact {
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
            }

            ProgressStripe(fraction: turnProgress, tint: AppTheme.accent)
        }
        .padding(12)
        .floatingCard()
    }

    /// 1 = còn xa chỗ rẽ, 0 = đã tới chỗ rẽ.
    private var turnProgress: Double {
        guard model.distanceToNextStep > 0 else { return 0 }
        return min(1, model.distanceToNextStep / 400)
    }

    /// Dải gợi ý làn đường — chỉ hiện khi sắp rẽ và chỉ dẫn cho biết rẽ hướng nào.
    @ViewBuilder
    private var laneStrip: some View {
        if let guidance = LaneGuidance.hint(for: model.currentStep,
                                            distance: model.distanceToNextStep) {
            LaneStrip(guidance: guidance)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Băng cảnh báo

    /// Banner cảnh báo kiểu VietMap: nhãn loại + tên + đếm lùi + thanh chạy tới điểm cảnh báo.
    /// Banner cảnh báo kiểu khối tối gọn: icon → nhãn loại + tên điểm → đếm lùi mét.
    private func alertBanner(_ alert: ActiveAlert) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: alert.alert.kind.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(alert.alert.kind.tint)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(alert.alert.kind.tint.opacity(0.18))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(alert.alert.kind.shortTitle.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.7)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    Text(alert.alert.displayName
                         + (alert.alert.speedLimit.map { " · \($0) km/h" } ?? ""))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(max(0, Int(alert.distance.rounded())))")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(alert.levelColor)
                        .lineLimit(1)
                    Text(alert.distance < 0 ? "ĐÃ QUA" : "MÉT")
                        .font(.system(size: 8.5, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .fixedSize()
            }

            ProgressStripe(fraction: alertProgress(alert), tint: alert.levelColor)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Self.hudSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alert.alert.kind.title), \(alert.distanceText)")
    }

    /// 1 = còn xa, 0 = đã tới điểm cảnh báo.
    private func alertProgress(_ alert: ActiveAlert) -> Double {
        guard alert.warnDistance > 0 else { return 0 }
        return max(0, min(1, alert.distance / alert.warnDistance))
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
                .frame(maxWidth: .infinity)
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

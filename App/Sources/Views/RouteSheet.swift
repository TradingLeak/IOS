import SwiftUI
import MapKit

@MainActor
struct RouteSheet: View {
    @ObservedObject var model: MapViewModel
    @ObservedObject var settings: AppSettings
    let onPickOrigin: () -> Void
    let onPickDestination: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showAllSteps = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    endpointsCard
                    modeCard
                    if let route = model.selectedRoute {
                        summaryCard(route)
                        if model.routes.count > 1 { routeOptionsCard }
                        smartAdviceCard
                        if let summary = model.aiSummary { aiCard(summary) }
                        alertsCard
                        stopsCard
                        stepsCard(route)
                    } else if model.isPlanning {
                        planningView
                    } else {
                        EmptyHint(symbol: "arrow.triangle.turn.up.right.diamond",
                                  title: "Chưa có tuyến đường",
                                  message: "Chọn điểm đi và điểm đến, sau đó bấm Tìm tuyến.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Chỉ đường")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.swapEndpoints()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .disabled(model.origin == nil && model.destination == nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Cards

    private var endpointsCard: some View {
        VStack(spacing: 0) {
            endpointRow(symbol: "circle.fill",
                        tint: AppTheme.success,
                        label: "Điểm đi",
                        value: model.origin?.name,
                        action: onPickOrigin)

            Divider().padding(.leading, 44)

            endpointRow(symbol: "flag.fill",
                        tint: AppTheme.danger,
                        label: "Điểm đến",
                        value: model.destination?.name,
                        action: onPickDestination)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .floatingCard()
    }

    private func endpointRow(symbol: String, tint: Color, label: String, value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(tint.opacity(0.12)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(value ?? "Chạm để chọn")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(value == nil ? .secondary : .primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var modeCard: some View {
        TravelModePicker(selection: Binding(
            get: { model.mode },
            set: { model.changeMode($0) }
        ))
        .padding(6)
        .floatingCard()
    }

    private func summaryCard(_ route: RouteOption) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                metric(value: route.formattedDuration, label: "thời gian", symbol: "clock.fill")
                metric(value: route.formattedDistance, label: "quãng đường", symbol: "point.topleft.down.curvedto.point.bottomright.up")
                metric(value: "\(route.steps.count)", label: "bước rẽ", symbol: "arrow.triangle.turn.up.right.diamond")
            }
            HStack(spacing: 8) {
                if let score = model.score(for: route) {
                    ScoreBadge(score: score)
                    Text(score.badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(route.provider.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                if route.isEstimatedProfile {
                    Text("· hồ sơ xe máy ước lượng")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.warning)
                }
                Spacer(minLength: 0)
            }

            if !route.advisoryNotices.isEmpty {
                ForEach(route.advisoryNotices, id: \.self) { notice in
                    InfoBanner(kind: .warning, text: notice)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingCard()
    }

    private func metric(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                Text(value)
                    .font(.system(size: 16, weight: .bold))
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var routeOptionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PHƯƠNG ÁN TUYẾN")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            ForEach(Array(model.routes.enumerated()), id: \.element.id) { _, route in
                Button {
                    model.selectRoute(route)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.selectedRoute?.id == route.id ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(model.selectedRoute?.id == route.id ? AppTheme.accent : Color.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(route.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if model.recommendedScore?.routeID == route.id {
                                    Text("AI đề xuất")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(AppTheme.accentGradient))
                                }
                            }
                            Text("\(route.formattedDistance) · \(route.formattedDuration)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let score = model.score(for: route) {
                            ScoreBadge(score: score)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingCard()
    }

    // MARK: - Gợi ý thông minh

    @ViewBuilder
    private var smartAdviceCard: some View {
        if let advice = model.aiAdvice, !advice.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.accentDeep)
                    Text("AI ĐỀ XUẤT TUYẾN")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if model.aiAdviceThinking {
                        ProgressView().controlSize(.mini)
                    }
                }
                Text(advice)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.primary)

                if let best = model.recommendedScore,
                   let route = model.routes.first(where: { $0.id == best.routeID }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Điểm \(Int(best.total.rounded()))/100 · \(route.formattedDuration) · \(route.formattedDistance)")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(AppTheme.success)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .floatingCard()
        }
    }

    @ViewBuilder
    private var alertsCard: some View {
        if !model.routeAlerts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("CẢNH BÁO TRÊN TUYẾN")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.routeAlerts.count) điểm")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(model.routeAlerts.prefix(6))) { active in
                    HStack(spacing: 9) {
                        Image(systemName: active.alert.kind.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(active.alert.kind.tint)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(active.alert.kind.tint.opacity(0.12)))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(active.alert.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(active.distanceText)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let limit = active.alert.speedLimit {
                            SpeedLimitSignView(limit: limit, size: 26, muted: true)
                        }
                    }
                }

                if model.routeAlerts.count > 6 {
                    Text("… và \(model.routeAlerts.count - 6) điểm khác. Mở nút camera trên bản đồ để xem tất cả.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .floatingCard()
        }
    }

    @ViewBuilder
    private var stopsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ĐIỂM DỪNG DỌC ĐƯỜNG")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await model.suggestStopsAlongRoute() }
                } label: {
                    HStack(spacing: 4) {
                        if model.isLoadingStops {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text("Gợi ý")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }

            if model.suggestedStops.isEmpty {
                Text("Tìm trạm xăng / quán cà phê dọc tuyến để nghỉ giữa đường.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.suggestedStops) { place in
                    Button {
                        model.focus(on: place)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(AppTheme.warning)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(place.displaySubtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingCard()
    }

    private func aiCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                Text("TÓM TẮT BẰNG AI")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if model.aiThinking {
                    ProgressView().controlSize(.mini)
                } else {
                    Button {
                        Task { await model.refreshSummary() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(summary)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !settings.config.isConfigured {
                Text("Đang dùng tóm tắt mặc định. Nhập API key trong Cài đặt để AI viết nhận xét riêng.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingCard()
    }

    private func stepsCard(_ route: RouteOption) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CHỈ DẪN TỪNG BƯỚC")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(route.steps.count) bước")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            let visible = showAllSteps ? route.steps : Array(route.steps.prefix(5))
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: step.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(AppTheme.accent.opacity(0.9)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.instruction)
                            .font(.system(size: 13, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(step.formattedDistance)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }

            if route.steps.count > 5 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAllSteps.toggle() }
                } label: {
                    Text(showAllSteps ? "Thu gọn" : "Xem tất cả \(route.steps.count) bước")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingCard()
    }

    private var planningView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Đang tính tuyến đường…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .floatingCard()
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            PrimaryButton(title: model.selectedRoute == nil ? "Tìm tuyến đường" : "Bắt đầu chỉ đường",
                          symbol: model.selectedRoute == nil ? "magnifyingglass" : "location.north.fill",
                          isLoading: model.isPlanning,
                          isEnabled: model.destination != nil) {
                if model.selectedRoute == nil {
                    Task { await model.planRoute() }
                } else {
                    model.startNavigation()
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }
}

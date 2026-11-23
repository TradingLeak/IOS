import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var store: PartnerStore

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    if let error = store.errorMessage {
                        ErrorStateView(message: error) {
                            Task { await store.refreshAll() }
                        }
                    }

                    tierCard
                    if let commission = store.tierState?.commission, !commission.isEmpty {
                        commissionCard(commission)
                    }
                    kpiGrid
                    chartCard
                    rebateCard
                    recentCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .refreshable { await store.refreshAll() }
            .navigationTitle("Tổng quan")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("EXNESS PARTNER")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(PartnerTheme.accent)

                if let updated = store.lastUpdated {
                    Text("Cập nhật " + Self.timeFormatter.string(from: updated))
                        .font(.system(size: 11))
                        .foregroundStyle(PartnerTheme.textTertiary)
                } else {
                    Text("Chưa có dữ liệu")
                        .font(.system(size: 11))
                        .foregroundStyle(PartnerTheme.textTertiary)
                }
            }

            Spacer()

            Button {
                Task { await store.refreshAll() }
            } label: {
                Group {
                    if store.isLoading {
                        ProgressView().tint(PartnerTheme.accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PartnerTheme.textPrimary)
                    }
                }
                .frame(width: 40, height: 40)
                .background(Circle().fill(PartnerTheme.surface))
                .overlay(Circle().stroke(PartnerTheme.stroke))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Làm mới dữ liệu")
        }
    }

    // MARK: - Cấp bậc

    private var tierCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CẤP BẬC ĐỐI TÁC")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(PartnerTheme.textSecondary)

                    Text(store.tierState?.tierName ?? "Chưa có")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(PartnerTheme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if let group = store.tierState?.tierGroup, !group.isEmpty {
                        Text(group)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PartnerTheme.textSecondary)
                    }

                    if let next = store.tierState?.qualificationTier, let nextName = next.name {
                        Text("Đang hướng tới " + nextName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PartnerTheme.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "medal.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(PartnerTheme.accent.opacity(0.92))
                    .shadow(color: PartnerTheme.accent.opacity(0.35), radius: 14)
            }

            Divider().overlay(PartnerTheme.accent.opacity(0.18))

            HStack(spacing: 0) {
                tierStat("Khách hàng", "\(store.tierState?.clientsCount ?? 0)")
                verticalRule
                tierStat("Volume", Fmt.compactUSD(store.tierState?.usdVolume ?? 0))
                verticalRule
                tierStat("Subpartner", "\(store.tierState?.subpartnersCount ?? 0)")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(PartnerTheme.heroGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PartnerTheme.accent.opacity(0.22), lineWidth: 1)
        )
    }

    private func commissionCard(_ commission: [String: [Int?]]) -> some View {
        PanelCard(title: "Tỷ lệ hoa hồng theo loại tài khoản",
                  symbol: "percent") {
            VStack(spacing: 10) {
                ForEach(commission.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PartnerTheme.textSecondary)
                        Spacer()
                        if let values = commission[key] {
                            let level1 = values.first.flatMap { $0 }.map { "\($0)%" } ?? "—"
                            let level2 = values.count > 1 ? (values[1].map { "\($0)%" } ?? "—") : "—"
                            Text("Cấp 1 \(level1) · Cấp 2 \(level2)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(PartnerTheme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    private var verticalRule: some View {
        Rectangle()
            .fill(PartnerTheme.stroke)
            .frame(width: 1, height: 34)
    }

    private func tierStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(PartnerTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(PartnerTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - KPI

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            KpiCard(title: "Hoa hồng",
                    value: Fmt.usd(store.overviewRewardUSD),
                    caption: "Tổng thưởng trong kỳ",
                    symbol: "dollarsign.circle.fill",
                    tint: PartnerTheme.accent)

            KpiCard(title: "Volume",
                    value: Fmt.lots(store.overviewVolumeLots),
                    caption: "Lots đã giao dịch",
                    symbol: "chart.bar.fill",
                    tint: PartnerTheme.info)

            KpiCard(title: "Khách hàng",
                    value: "\(store.clientCount)",
                    caption: "Khách hàng giới thiệu",
                    symbol: "person.2.fill",
                    tint: PartnerTheme.success)

            KpiCard(title: "Chờ xử lý",
                    value: "\(store.pendingOrders)",
                    caption: Fmt.lots(store.pendingVolumeLots) + " lots đang chờ",
                    symbol: "clock.badge.exclamationmark",
                    tint: PartnerTheme.warning)
        }
    }

    // MARK: - Biểu đồ

    private var chartCard: some View {
        PanelCard(title: "Hoa hồng theo \(aggregateTitle)",
                  subtitle: store.rewardRange.title + " · " + Fmt.usd(store.overviewRewardUSD),
                  symbol: "chart.bar.doc.horizontal.fill") {
            if store.rewardChartPoints.isEmpty {
                EmptyStateView(symbol: "chart.bar",
                               title: "Chưa có dữ liệu",
                               message: "Chưa có hoa hồng nào trong kỳ đã chọn.")
            } else {
                BarChartView(points: store.rewardChartPoints)
            }
        }
    }

    private var aggregateTitle: String {
        switch store.rewardAggregate {
        case .day: return "ngày"
        case .week: return "tuần"
        case .month: return "tháng"
        }
    }

    // MARK: - Rebate

    private var rebateCard: some View {
        PanelCard(title: "Rebate",
                  subtitle: "Hoàn phí đã trả cho khách hàng",
                  symbol: "arrow.counterclockwise.circle.fill") {
            HStack(spacing: 10) {
                rebateStat("Đã trả", Fmt.usd(store.rebateProcessedUSD), PartnerTheme.success)
                rebateStat("Từ chối", Fmt.usd(store.rebateRejectedUSD), PartnerTheme.danger)
                rebateStat("Lỗi", Fmt.usd(store.rebateErrorUSD), PartnerTheme.warning)
            }
        }
    }

    private func rebateStat(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(PartnerTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.07))
        )
    }

    // MARK: - Giao dịch gần nhất

    private var recentCard: some View {
        PanelCard(title: "Hoạt động gần nhất", symbol: "clock.fill") {
            if store.recentRewards.isEmpty {
                EmptyStateView(symbol: "tray",
                               title: "Chưa có giao dịch",
                               message: "Hoa hồng sẽ xuất hiện sau khi lệnh của khách hàng được chốt.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.recentRewards.enumerated()), id: \.offset) { index, row in
                        RewardRowView(row: row)
                        if index < store.recentRewards.count - 1 {
                            PartnerDivider()
                        }
                    }
                }
            }
        }
    }
}

import SwiftUI

struct RewardsView: View {
    @EnvironmentObject var store: PartnerStore

    private var visibleRows: [RewardRow] {
        Array(store.rewardRows.prefix(200))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = store.errorMessage {
                        ErrorStateView(message: error) {
                            Task { await store.loadRewards() }
                        }
                    }

                    filterCard
                    totalsCard
                    chartCard
                    listCard
                    rebateCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .refreshable { await store.loadRewards() }
            .navigationTitle("Hoa hồng")
            .navigationBarTitleDisplayMode(.large)
            .task {
                if store.rewardReport == nil {
                    await store.loadRewards()
                }
                if store.rebateHistory == nil {
                    await store.loadRebates()
                }
            }
            .onChange(of: store.rewardRange) { _ in
                Task { await store.loadRewards() }
            }
            .onChange(of: store.rewardAggregate) { _ in
                Task { await store.loadRewards() }
            }
        }
    }

    // MARK: - Bộ lọc

    private var filterCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Kỳ báo cáo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PartnerTheme.textSecondary)
                Spacer()
                Picker("Kỳ báo cáo", selection: $store.rewardRange) {
                    ForEach(RewardRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .tint(PartnerTheme.accent)
            }

            Picker("Gộp theo", selection: $store.rewardAggregate) {
                ForEach(RewardAggregate.allCases) { aggregate in
                    Text(aggregate.title).tag(aggregate)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .partnerCard(radius: 18)
    }

    // MARK: - Tổng

    private var totalsCard: some View {
        HStack(spacing: 0) {
            totalStat("Hoa hồng", Fmt.usd(store.overviewRewardUSD), PartnerTheme.accent)
            verticalRule
            totalStat("Volume", Fmt.lots(store.overviewVolumeLots), PartnerTheme.info)
            verticalRule
            totalStat("Lệnh", "\(store.overviewOrders)", PartnerTheme.success)
        }
        .padding(18)
        .partnerCard()
    }

    private var verticalRule: some View {
        Rectangle()
            .fill(PartnerTheme.stroke)
            .frame(width: 1, height: 36)
    }

    private func totalStat(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(PartnerTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Biểu đồ

    private var chartCard: some View {
        PanelCard(title: "Xu hướng hoa hồng",
                  subtitle: store.rewardRange.title + " · gộp theo " + store.rewardAggregate.title.lowercased(),
                  symbol: "chart.xyaxis.line") {
            if store.rewardChartPoints.isEmpty {
                EmptyStateView(symbol: "chart.bar",
                               title: "Chưa có dữ liệu",
                               message: "Thử chọn kỳ khác hoặc kiểm tra quyền của API key.")
            } else {
                BarChartView(points: store.rewardChartPoints)
            }
        }
    }

    // MARK: - Danh sách

    private var listCard: some View {
        PanelCard(title: "Chi tiết hoa hồng",
                  subtitle: "\(store.rewardRows.count) dòng",
                  symbol: "list.bullet.rectangle.fill") {
            if store.rewardRows.isEmpty && store.isLoading {
                LoadingCard(title: "Đang tải hoa hồng…")
            } else if store.rewardRows.isEmpty {
                EmptyStateView(symbol: "tray",
                               title: "Không có hoa hồng",
                               message: "Chưa có dòng thưởng nào khớp với bộ lọc hiện tại.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleRows.enumerated()), id: \.offset) { index, row in
                        RewardRowView(row: row)
                        if index < visibleRows.count - 1 {
                            PartnerDivider()
                        }
                    }

                    if store.rewardRows.count > visibleRows.count {
                        Text("Hiển thị \(visibleRows.count)/\(store.rewardRows.count) dòng đầu tiên")
                            .font(.system(size: 10))
                            .foregroundStyle(PartnerTheme.textTertiary)
                            .padding(.top, 8)
                    }
                }
            }
        }
    }

    // MARK: - Rebate

    private var rebateCard: some View {
        PanelCard(title: "Rebate gần nhất",
                  subtitle: "Hoàn phí đã trả cho khách hàng",
                  symbol: "arrow.counterclockwise.circle.fill") {
            if let history = store.rebateHistory, !history.data.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(history.data.prefix(5).enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Fmt.date(row.rewardDate))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(PartnerTheme.textPrimary)
                                Text("••" + String(row.clientAccount.suffix(4)) +
                                     " · " + String(format: "%.0f%%", row.rebatePercent))
                                    .font(.system(size: 10))
                                    .foregroundStyle(PartnerTheme.textTertiary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(Fmt.usd(row.rebateUsd))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(PartnerTheme.accent)
                                StatusPill(text: row.status, color: PartnerStore.statusColor(row.status))
                            }
                        }
                        .padding(.vertical, 8)

                        if index < min(history.data.count, 5) - 1 {
                            PartnerDivider()
                        }
                    }
                }
            } else {
                EmptyStateView(symbol: "arrow.counterclockwise.circle",
                               title: "Chưa có rebate",
                               message: "Chưa có dòng hoàn phí nào được xử lý.")
            }
        }
    }
}

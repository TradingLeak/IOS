import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject var store: PartnerStore

    private var visibleOrders: [OrderRow] {
        Array((store.orderReport?.data ?? []).prefix(200))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = store.errorMessage {
                        ErrorStateView(message: error) {
                            Task { await store.loadTransactions() }
                        }
                    }

                    periodCard
                    pendingCard
                    totalsCard
                    ordersCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .refreshable { await store.loadTransactions() }
            .navigationTitle("Giao dịch")
            .navigationBarTitleDisplayMode(.large)
            .task {
                if store.orderReport == nil {
                    await store.loadTransactions()
                }
            }
            .onChange(of: store.transactionDays) { _ in
                Task { await store.loadTransactions() }
            }
        }
    }

    // MARK: - Kỳ

    private var periodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Khoảng thời gian")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PartnerTheme.textSecondary)
            Picker("Khoảng thời gian", selection: $store.transactionDays) {
                Text("7 ngày").tag(7)
                Text("14 ngày").tag(14)
                Text("30 ngày").tag(30)
            }
            .pickerStyle(.segmented)
            Text("API chỉ cho phép tối đa 32 ngày mỗi lần truy vấn.")
                .font(.system(size: 10))
                .foregroundStyle(PartnerTheme.textTertiary)
        }
        .padding(14)
        .partnerCard(radius: 18)
    }

    // MARK: - Chờ tính

    private var pendingCard: some View {
        PanelCard(title: "Chờ tính hoa hồng",
                  subtitle: "Lệnh đã đóng, chưa ghi nhận thưởng",
                  symbol: "clock.badge.questionmark") {
            if let report = store.pendingReport {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 0) {
                        pendingStat("Lots chờ", Fmt.lots(report.totals.volumeLots), PartnerTheme.warning)
                        verticalRule
                        pendingStat("Lệnh", "\(report.totals.countOrders)", PartnerTheme.warning)
                        verticalRule
                        pendingStat("Tài khoản", "\(report.totals.count)", PartnerTheme.textPrimary)
                    }

                    if !report.data.isEmpty {
                        PartnerDivider()
                        ForEach(Array(report.data.prefix(5).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 10) {
                                Text("••" + String(row.clientAccount.suffix(4)))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(PartnerTheme.textSecondary)
                                Text(row.clientAccountType)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(PartnerTheme.textTertiary)
                                Spacer()
                                Text(Fmt.lots(row.volumeLots) + " lots")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(PartnerTheme.textPrimary)
                                Text("\(row.countOrders) lệnh")
                                    .font(.system(size: 10))
                                    .foregroundStyle(PartnerTheme.textTertiary)
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }
                    } else {
                        Text("Không có lệnh nào đang chờ xử lý.")
                            .font(.system(size: 11))
                            .foregroundStyle(PartnerTheme.textTertiary)
                    }
                }
            } else {
                LoadingCard(title: "Đang tải lệnh chờ…")
            }
        }
    }

    private var verticalRule: some View {
        Rectangle()
            .fill(PartnerTheme.stroke)
            .frame(width: 1, height: 34)
    }

    private func pendingStat(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(PartnerTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tổng

    private var totalsCard: some View {
        HStack(spacing: 0) {
            totalStat("Hoa hồng", Fmt.usd(store.orderReport?.totals.rewardUsd ?? 0), PartnerTheme.accent)
            verticalRule
            totalStat("Volume", Fmt.lots(store.orderReport?.totals.volumeLots ?? 0), PartnerTheme.info)
            verticalRule
            totalStat("Lệnh", "\(store.orderReport?.totals.count ?? 0)", PartnerTheme.success)
        }
        .padding(18)
        .partnerCard()
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

    // MARK: - Lệnh

    private var ordersCard: some View {
        PanelCard(title: "Lệnh đã chốt",
                  subtitle: "\(store.orderReport?.data.count ?? 0) lệnh trong kỳ",
                  symbol: "list.bullet.clipboard.fill") {
            if store.orderReport == nil {
                LoadingCard(title: "Đang tải giao dịch…")
            } else if visibleOrders.isEmpty {
                EmptyStateView(symbol: "line.3.horizontal.decrease.circle",
                               title: "Không có giao dịch",
                               message: "Chưa có lệnh nào được chốt trong khoảng thời gian đã chọn.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleOrders.enumerated()), id: \.offset) { index, order in
                        orderRow(order)
                        if index < visibleOrders.count - 1 {
                            PartnerDivider()
                        }
                    }

                    if (store.orderReport?.data.count ?? 0) > visibleOrders.count {
                        Text("Hiển thị \(visibleOrders.count)/\(store.orderReport?.data.count ?? 0) lệnh đầu tiên")
                            .font(.system(size: 10))
                            .foregroundStyle(PartnerTheme.textTertiary)
                            .padding(.top, 8)
                    }
                }
            }
        }
    }

    private func orderRow(_ order: OrderRow) -> some View {
        HStack(spacing: 10) {
            Text(order.symbol)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(PartnerTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(PartnerTheme.accent.opacity(0.12))
                )
                .frame(minWidth: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(Fmt.dateTime(order.closeDate))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PartnerTheme.textPrimary)
                Text("••" + String(order.clientAccount.suffix(4)) + " · " + order.clientAccountType)
                    .font(.system(size: 9))
                    .foregroundStyle(PartnerTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.usd(order.rewardUsd))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PartnerTheme.accent)
                Text(Fmt.lots(order.volumeLots) + " lots")
                    .font(.system(size: 9))
                    .foregroundStyle(PartnerTheme.textSecondary)
            }
        }
        .padding(.vertical, 9)
    }
}

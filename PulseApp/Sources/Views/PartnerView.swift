import SwiftUI

/// Tóm tắt hoa hồng đối tác (Partnership API) — mở từ Tổng quan.
struct PartnerView: View {
    @EnvironmentObject var store: PulseStore
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !store.isPartnerConfigured {
                    notConfigured
                } else if let summary = store.partnerSummary {
                    tierCard(summary)
                    kpiRow(summary)
                    rewardsCard
                    clientsCard
                } else if store.isLoadingPartner {
                    PulseLoading(title: "Đang tải dữ liệu đối tác")
                } else if let error = store.partnerError {
                    PulseErrorState(message: error) {
                        Task { await store.loadPartner() }
                    }
                } else {
                    PulseEmptyState(symbol: "person.2", title: "Chưa có dữ liệu", message: "Kéo để tải lại.")
                }

                Text("Dữ liệu từ Partnership API · hoa hồng tính theo USD · cập nhật " +
                     (store.partnerSummary == nil ? "—" : PulseFormat.clock(Date()) + " " + PulseFormat.shortDate(Date())))
                    .font(.system(size: 10))
                    .foregroundStyle(PulseTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(PulseTheme.background)
        .navigationTitle("Đối tác")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(PulseTheme.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .task {
            if store.partnerSummary == nil, store.isPartnerConfigured {
                await store.loadPartner()
            }
        }
        .refreshable {
            if store.isPartnerConfigured {
                await store.loadPartner()
            }
        }
    }

    // MARK: - Chưa cấu hình

    private var notConfigured: some View {
        VStack(spacing: 14) {
            PulseIconBadge(symbol: "person.2.fill", tint: PulseTheme.gold, size: 52)
            Text("Kết nối Partnership API")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(PulseTheme.textPrimary)
            Text("Dùng API key có scope Partnership (Read-only là đủ). Nhập host, key và private key trong Cài đặt — giống cách kết nối app Exness Partner.")
                .font(.system(size: 13))
                .foregroundStyle(PulseTheme.textSecondary)
                .multilineTextAlignment(.center)
            PulsePrimaryButton(title: "Mở Cài đặt", symbol: "key.fill", tint: PulseTheme.gold) {
                showSettings = true
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .pulseGlass()
    }

    // MARK: - Cấp bậc

    private func tierCard(_ summary: PartnerSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PulseStatusPill(text: "Cấp bậc đối tác", color: PulseTheme.gold)
            Text(summary.tierName)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(PulseTheme.textPrimary)
            if let group = summary.tierGroup, !group.isEmpty {
                Text(group)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PulseTheme.gold)
            }
            Text("Volume đối tác: " + Fmt.lots(summary.usdVolume) + " lots")
                .font(.system(size: 12))
                .foregroundStyle(PulseTheme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [PulseTheme.gold.opacity(0.22), PulseTheme.surface],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PulseTheme.gold.opacity(0.35), lineWidth: 1))
        )
    }

    // MARK: - KPI

    private func kpiRow(_ summary: PartnerSummary) -> some View {
        HStack(spacing: 10) {
            partnerKpi("Hoa hồng 30 ngày", summary.rewards30d.map { Fmt.usd($0) } ?? "—", PulseTheme.gold)
            partnerKpi("Khách hàng", "\(summary.clientsCount)", PulseTheme.teal)
            partnerKpi("Volume KH", Fmt.lots(summary.clientsVolumeLots), PulseTheme.violet)
        }
    }

    private func partnerKpi(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(PulseTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.035)))
    }

    // MARK: - Hoa hồng gần đây

    private var rewardsCard: some View {
        PulsePanelCard(title: "Hoa hồng 30 ngày gần nhất",
                       subtitle: store.partnerRewards.isEmpty ? nil : "\(store.partnerRewards.count) dòng",
                       symbol: "chart.bar.fill",
                       tint: PulseTheme.gold) {
            if store.partnerRewards.isEmpty {
                Text("Chưa có khoản hoa hồng nào trong 30 ngày qua.")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseTheme.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.partnerRewards.prefix(30).enumerated()), id: \.element.id) { index, row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Fmt.date(row.rewardDate))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(PulseTheme.textPrimary)
                                Text([row.clientAccount.map { "#" + $0 }, row.country].compactMap { $0 }.joined(separator: " · ") +
                                     (row.ordersCount > 0 ? " · \(row.ordersCount) lệnh" : ""))
                                    .font(.system(size: 10))
                                    .foregroundStyle(PulseTheme.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(Fmt.usd(row.rewardUsdDecimal))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(PulseTheme.gold)
                        }
                        .padding(.vertical, 8)
                        if index < min(store.partnerRewards.count, 30) - 1 {
                            Divider().overlay(PulseTheme.stroke)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Khách hàng

    private var clientsCard: some View {
        PulsePanelCard(title: "Khách hàng",
                       subtitle: store.partnerClients.isEmpty ? nil : "Top theo hoa hồng",
                       symbol: "person.3.fill",
                       tint: PulseTheme.teal) {
            if store.partnerClients.isEmpty {
                Text("Chưa có dữ liệu khách hàng.")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseTheme.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.partnerClients.prefix(10).enumerated()), id: \.element.id) { index, client in
                        HStack {
                            Text(PulseSymbol.flag(forCurrency: client.clientCountry))
                                .font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("#" + client.clientUid)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(PulseTheme.textPrimary)
                                    .lineLimit(1)
                                Text(client.clientCountry + " · " + Fmt.lots(client.volumeLots) + " lots" +
                                     (client.clientStatus.map { " · " + $0 } ?? ""))
                                    .font(.system(size: 10))
                                    .foregroundStyle(PulseTheme.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(Fmt.usd(client.rewardUsd))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(PulseTheme.teal)
                        }
                        .padding(.vertical, 8)
                        if index < min(store.partnerClients.count, 10) - 1 {
                            Divider().overlay(PulseTheme.stroke)
                        }
                    }
                }
            }
        }
    }
}

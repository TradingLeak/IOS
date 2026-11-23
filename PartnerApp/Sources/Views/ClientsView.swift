import SwiftUI

struct ClientsView: View {
    @EnvironmentObject var store: PartnerStore

    private var visibleRows: [ClientRow] {
        Array(store.filteredClients.prefix(300))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = store.errorMessage {
                        ErrorStateView(message: error) {
                            Task { await store.loadClients() }
                        }
                    }

                    summaryCard
                    sortCard

                    if store.clientReport == nil {
                        PanelCard(title: "Danh sách khách hàng", symbol: "person.2.fill") {
                            LoadingCard(title: "Đang tải khách hàng…")
                        }
                    } else if store.filteredClients.isEmpty {
                        PanelCard(title: "Danh sách khách hàng", symbol: "person.2.fill") {
                            EmptyStateView(symbol: "person.crop.circle.badge.questionmark",
                                           title: "Không tìm thấy khách hàng",
                                           message: "Thử từ khoá khác hoặc kéo để làm mới dữ liệu.")
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(visibleRows.enumerated()), id: \.offset) { index, row in
                                clientRow(row)
                                if index < visibleRows.count - 1 {
                                    PartnerDivider().padding(.leading, 52)
                                }
                            }
                        }
                        .partnerCard(radius: 18)

                        if store.filteredClients.count > visibleRows.count {
                            Text("Hiển thị \(visibleRows.count)/\(store.filteredClients.count) khách hàng")
                                .font(.system(size: 10))
                                .foregroundStyle(PartnerTheme.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .refreshable { await store.loadClients() }
            .searchable(text: $store.clientQuery,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Tìm UID, quốc gia, trạng thái")
            .navigationTitle("Khách hàng")
            .navigationBarTitleDisplayMode(.large)
            .task {
                if store.clientReport == nil {
                    await store.loadClients()
                }
            }
        }
    }

    // MARK: - Tổng quan

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryStat("Khách hàng", "\(store.clientCount)", PartnerTheme.success)
            verticalRule
            summaryStat("Hoa hồng", Fmt.usd(store.clientReport?.totals.rewardUsd ?? "0"), PartnerTheme.accent)
            verticalRule
            summaryStat("Volume", Fmt.lots(store.clientReport?.totals.volumeLots ?? 0), PartnerTheme.info)
        }
        .padding(18)
        .partnerCard()
    }

    private var verticalRule: some View {
        Rectangle()
            .fill(PartnerTheme.stroke)
            .frame(width: 1, height: 36)
    }

    private func summaryStat(_ title: String, _ value: String, _ tint: Color) -> some View {
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

    private var sortCard: some View {
        HStack {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PartnerTheme.textSecondary)
            Picker("Sắp xếp", selection: $store.clientSort) {
                ForEach(ClientSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .partnerCard(radius: 16)
    }

    // MARK: - Dòng khách hàng

    private func clientRow(_ row: ClientRow) -> some View {
        HStack(spacing: 12) {
            Text(flag(for: row.clientCountry))
                .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 3) {
                Text(maskedUID(row.clientUid))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PartnerTheme.textPrimary)

                Text("Đăng ký " + Fmt.date(row.regDate) + " · " + row.clientCountry)
                    .font(.system(size: 10))
                    .foregroundStyle(PartnerTheme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if row.kycPassed == true {
                        MiniBadge(text: "KYC", tint: PartnerTheme.success)
                    }
                    if row.ftdReceived == true {
                        MiniBadge(text: "FTD", tint: PartnerTheme.info)
                    }
                    if row.fttMade == true {
                        MiniBadge(text: "FTT", tint: PartnerTheme.accent)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.usd(row.rewardUsdDecimal))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(PartnerTheme.accent)
                Text(Fmt.lots(row.volumeLots) + " lots")
                    .font(.system(size: 10))
                    .foregroundStyle(PartnerTheme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Helper

    private func maskedUID(_ uid: String) -> String {
        guard uid.count > 8 else { return uid }
        return String(uid.prefix(8)) + "…"
    }

    private func flag(for country: String) -> String {
        let upper = country.uppercased()
        guard upper.count == 2,
              upper.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else {
            return "🌍"
        }
        var result = ""
        for scalar in upper.unicodeScalars {
            if let regional = UnicodeScalar(127_397 + scalar.value) {
                result.append(String(regional))
            }
        }
        return result.isEmpty ? "🌍" : result
    }
}

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: PulseStore
    @State private var showSettings = false
    @State private var showSymbolPicker = false
    @State private var newsURL: URL?

    private var symbolsToShow: [String] {
        let list = store.streamSymbols
        return list.isEmpty ? Array(store.watchlist.prefix(6)) : Array(list.prefix(6))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !store.isConfigured {
                        guestBanner
                    }

                    statusRow

                    accountCard
                    watchlistCard
                    alertsCard
                    calendarCard
                    newsCard
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(PulseTheme.background)
            .navigationTitle("Pulse")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink(value: "partner") {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(PulseTheme.gold)
                    }
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(PulseTheme.textSecondary)
                    }
                }
            }
            .navigationDestination(for: String.self) { route in
                if route == "partner" {
                    PartnerView()
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .sheet(isPresented: $showSymbolPicker) {
                SymbolPickerView(instruments: store.instruments, watchlist: $store.watchlist)
                    .environmentObject(store)
                    .onChange(of: store.watchlist) { _ in
                        store.watchlistChanged()
                    }
            }
            .sheet(item: $newsURL) { url in
                SafariView(url: url)
                    .ignoresSafeArea()
            }
            .refreshable { await store.refreshDashboard() }
            .task {
                if store.sparklines.isEmpty, store.isTradingConfigured {
                    await store.loadSparklines()
                }
            }
        }
    }

    // MARK: - Trạng thái

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.streamStatus.isActive ? PulseTheme.success : PulseTheme.textTertiary)
                .frame(width: 8, height: 8)
            Text(store.isTradingConfigured ? store.streamStatus.title : "Chưa kết nối Trader API")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PulseTheme.textSecondary)
            Spacer()
            if store.isLoadingNews || store.isLoadingCalendar || store.isLoadingAccount {
                ProgressView().tint(PulseTheme.teal).scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 4)
    }

    private var guestBanner: some View {
        HStack(spacing: 12) {
            PulseIconBadge(symbol: "eye.fill", tint: PulseTheme.info, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Chế độ chỉ xem")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PulseTheme.textPrimary)
                Text("Lịch kinh tế & tin tức hoạt động đầy đủ. Kết nối API để xem giá, giao dịch và hoa hồng.")
                    .font(.system(size: 11))
                    .foregroundStyle(PulseTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Button("Kết nối") { showSettings = true }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(PulseTheme.teal))
                .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PulseTheme.info.opacity(0.10))
        )
    }

    // MARK: - Tài khoản

    @ViewBuilder
    private var accountCard: some View {
        if store.isTradingConfigured {
            let equity = store.accountState?.equityDecimal
            let balance = store.accountState?.balanceDecimal
            let margin = store.accountState?.usedMarginDecimal
            let currency = store.tradingAccount?.currency ?? "USD"
            PulsePanelCard(title: "Tài khoản giao dịch",
                           subtitle: accountSubtitle(currency: currency),
                           symbol: "creditcard.fill",
                           tint: PulseTheme.violet,
                           trailing: AnyView(
                               PulseStatusPill(text: store.tradingAccount?.accountStatus ?? "—",
                                               color: PulseTheme.success)
                           )) {
                HStack(spacing: 10) {
                    kpi("Equity", PulseFormat.money(equity, currency: currency), tint: PulseTheme.violet)
                    kpi("Số dư", PulseFormat.money(balance, currency: currency), tint: PulseTheme.teal)
                    kpi("Margin", PulseFormat.money(margin, currency: currency), tint: PulseTheme.warning)
                }
                if !store.positions.isEmpty {
                    Divider().overlay(PulseTheme.stroke)
                    Text("Đang mở \(store.positions.count) lệnh · " +
                         store.positions.compactMap(\.instrument).prefix(4).joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(PulseTheme.textSecondary)
                        .lineLimit(1)
                }
                if let error = store.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(PulseTheme.danger)
                }
            }
        } else {
            PulsePanelCard(title: "Tài khoản giao dịch",
                           subtitle: "Equity, số dư, margin và lệnh đang mở",
                           symbol: "creditcard.fill",
                           tint: PulseTheme.violet) {
                Text("Kết nối Trader API (API key có scope Trading + account ID) để xem tài khoản và nhận giá trực tiếp.")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseTheme.textSecondary)
                PulseSecondaryButton(title: "Cấu hình Trader API", symbol: "key.fill", tint: PulseTheme.violet) {
                    showSettings = true
                }
            }
        }
    }

    private func accountSubtitle(currency: String) -> String {
        let account = store.credentials?.accountId ?? ""
        var text = "#" + account + " · " + currency
        if let mode = store.tradingAccount?.tradeMode, !mode.isEmpty {
            text += " · " + mode
        }
        return text
    }

    private func kpi(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(PulseTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Danh sách theo dõi

    private var watchlistCard: some View {
        PulsePanelCard(title: "Giá trực tiếp",
                       subtitle: store.isTradingConfigured
                           ? "WebSocket ticks · mid price · thay đổi theo phiên"
                           : "Cần Trader API để nhận báo giá",
                       symbol: "chart.line.uptrend.xyaxis",
                       tint: PulseTheme.teal,
                       trailing: AnyView(
                           HStack(spacing: 10) {
                               if store.isTradingConfigured {
                                   PulseStatusPill(text: store.streamStatus.title,
                                                   color: store.streamStatus.isActive ? PulseTheme.success : PulseTheme.warning)
                               }
                               Button {
                                   showSymbolPicker = true
                               } label: {
                                   Image(systemName: "plus.circle.fill")
                                       .foregroundStyle(PulseTheme.teal)
                               }
                               .buttonStyle(.plain)
                           }
                       )) {
            if store.isTradingConfigured {
                VStack(spacing: 6) {
                    ForEach(symbolsToShow, id: \.self) { symbol in
                        QuoteRowView(symbol: symbol,
                                     quote: store.quotes[symbol],
                                     change: store.sessionChanges[symbol],
                                     sparkline: store.sparklines[symbol] ?? []) {
                            store.selectedSymbol = symbol
                            store.selectedTab = .market
                        }
                    }
                    if symbolsToShow.isEmpty {
                        PulseEmptyState(symbol: "chart.line.downtrend.xyaxis",
                                        title: "Danh sách theo dõi trống",
                                        message: "Nhấn + để thêm mã.")
                    }
                }
                Text("Giá mid = trung bình bid/ask từ ticks. Sparkline: nến M5 (40 nến).")
                    .font(.system(size: 10))
                    .foregroundStyle(PulseTheme.textTertiary)
            } else {
                VStack(spacing: 10) {
                    ForEach(symbolsToShow, id: \.self) { symbol in
                        HStack {
                            PulseIconBadge(symbol: PulseSymbol.category(for: symbol).symbol,
                                           tint: PulseTheme.categoryTint(PulseSymbol.category(for: symbol)), size: 30)
                            Text(PulseSymbol.displayName(symbol))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(PulseTheme.textPrimary)
                            Spacer()
                            Text("—")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(PulseTheme.textTertiary)
                        }
                    }
                }
                .opacity(0.7)
            }
        }
    }

    // MARK: - Cảnh báo

    private var alertsCard: some View {
        PulsePanelCard(title: "Cảnh báo giá",
                       subtitle: store.alerts.isEmpty ? "Chưa có cảnh báo nào" : "\(store.activeAlertCount) đang bật · \(store.alerts.count) tổng",
                       symbol: "bell.badge.fill",
                       tint: PulseTheme.warning,
                       trailing: AnyView(
                           Button("Xem tất cả") { store.selectedTab = .alerts }
                               .font(.system(size: 12, weight: .semibold))
                               .foregroundStyle(PulseTheme.teal)
                               .buttonStyle(.plain)
                       )) {
            if store.alerts.isEmpty {
                HStack(spacing: 12) {
                    Text("Đặt mức giá hoặc biên độ % cho bất kỳ mã nào. App kiểm tra theo từng tick và gửi thông báo hệ thống.")
                        .font(.system(size: 12))
                        .foregroundStyle(PulseTheme.textSecondary)
                    Spacer(minLength: 0)
                    Button {
                        store.selectedTab = .alerts
                    } label: {
                        Text("Tạo cảnh báo")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(PulseTheme.warning))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(store.alerts.prefix(3)) { alert in
                        HStack(spacing: 10) {
                            Image(systemName: alert.condition.icon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(alert.enabled ? PulseTheme.warning : PulseTheme.textTertiary)
                            Text(PulseSymbol.displayName(alert.symbol))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(PulseTheme.textPrimary)
                            Text(alert.conditionText)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(PulseTheme.textSecondary)
                            Spacer()
                            Text(store.quotes[alert.symbol].map { PulseFormat.price($0.mid, symbol: alert.symbol) } ?? "")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(PulseTheme.teal)
                        }
                        .padding(.vertical, 2)
                    }
                    if store.alerts.count > 3 {
                        Text("+\(store.alerts.count - 3) cảnh báo khác")
                            .font(.system(size: 11))
                            .foregroundStyle(PulseTheme.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Lịch kinh tế

    private var calendarCard: some View {
        PulsePanelCard(title: "Lịch kinh tế",
                       subtitle: "Sự kiện cao ảnh hưởng sắp tới",
                       symbol: "calendar",
                       tint: PulseTheme.danger,
                       trailing: AnyView(
                           Button("Xem tất cả") { store.selectedTab = .calendar }
                               .font(.system(size: 12, weight: .semibold))
                               .foregroundStyle(PulseTheme.teal)
                               .buttonStyle(.plain)
                       )) {
            if let error = store.calendarError, store.events.isEmpty {
                PulseErrorState(message: error) {
                    Task { await store.loadCalendar(force: true) }
                }
            } else if store.isLoadingCalendar && store.events.isEmpty {
                PulseLoading(title: "Đang tải lịch kinh tế")
            } else if let next = store.upcomingHighImpact.first {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(next.flag + " " + next.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(PulseTheme.textPrimary)
                            .lineLimit(2)
                        Spacer()
                        Text(PulseFormat.countdown(to: next.date))
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(PulseTheme.danger)
                    }
                    Text("\(next.currencyName) · " + PulseFormat.dayTitle(next.date) + " · " + PulseFormat.clock(next.date) +
                         (next.forecast.isEmpty ? "" : " · Dự báo " + next.forecast))
                        .font(.system(size: 11))
                        .foregroundStyle(PulseTheme.textSecondary)
                    ForEach(store.upcomingHighImpact.dropFirst().prefix(2)) { event in
                        HStack(spacing: 8) {
                            Text(PulseFormat.clock(event.date))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(PulseTheme.textSecondary)
                            Text(event.flag)
                            Text(event.title)
                                .font(.system(size: 12))
                                .foregroundStyle(PulseTheme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }
            } else {
                PulseEmptyState(symbol: "calendar.badge.exclamationmark",
                                title: "Không có sự kiện cao ảnh hưởng sắp tới")
            }
        }
    }

    // MARK: - Tin tức

    private var newsCard: some View {
        PulsePanelCard(title: "Tin tức",
                       subtitle: "\(store.news.count) tin · " + NewsSources.enabledFeeds().map(\.title).joined(separator: ", "),
                       symbol: "newspaper.fill",
                       tint: PulseTheme.violet,
                       trailing: AnyView(
                           Button("Xem tất cả") { store.selectedTab = .news }
                               .font(.system(size: 12, weight: .semibold))
                               .foregroundStyle(PulseTheme.teal)
                               .buttonStyle(.plain)
                       )) {
            if let error = store.newsError, store.news.isEmpty {
                PulseErrorState(message: error) {
                    Task { await store.loadNews(force: true) }
                }
            } else if store.isLoadingNews && store.news.isEmpty {
                PulseLoading(title: "Đang tải tin tức")
            } else {
                VStack(spacing: 8) {
                    ForEach(store.visibleNews.prefix(3)) { item in
                        Button {
                            if let url = URL(string: item.link) { newsURL = url }
                        } label: {
                            NewsRowView(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// `URL` không tuân `Identifiable` — bọc để dùng với `.sheet(item:)`.
extension URL: Identifiable {
    public var id: String { absoluteString }
}

import SwiftUI
import UIKit

enum PulseTab: Hashable {
    case dashboard, market, calendar, news, alerts
}

/// Trạng thái trung tâm của Pulse: thông tin đăng nhập, giá trực tiếp, nến,
/// cảnh báo, lịch kinh tế, tin tức và tóm tắt đối tác.
@MainActor
final class PulseStore: ObservableObject {
    static let watchlistKey = "pulse.watchlist"
    static let guestKey = "pulse.guestMode"

    // MARK: - Đăng nhập

    @Published var credentials: PulseCredentials?
    @Published var selectedTab: PulseTab = .dashboard
    @Published var errorMessage: String?
    @Published var isTesting = false
    /// Chế độ chỉ xem (lịch + tin tức) khi chưa có API key.
    @Published var guestMode = UserDefaults.standard.bool(forKey: "pulse.guestMode")

    // MARK: - Giao dịch

    @Published var tradingAccount: TradingAccountInfo?
    @Published var accountState: AccountState?
    @Published var positions: [TradingPosition] = []
    @Published var instruments: [String] = []
    @Published var isLoadingAccount = false
    @Published var quotes: [String: Quote] = [:]
    @Published var watchlist: [String] = ["XAUUSD", "EURUSD", "GBPUSD", "USDJPY", "BTCUSD"]
    @Published var streamStatus: TickStream.Status = .idle

    // MARK: - Biểu đồ

    @Published var selectedSymbol: String = "XAUUSD"
    @Published var timeframe: Timeframe = .M15
    @Published var candles: [Candle] = []
    @Published var isLoadingCandles = false
    @Published var candleError: String?
    @Published var sparklines: [String: [Double]] = [:]
    @Published var sessionChanges: [String: Double] = [:]

    // MARK: - Cảnh báo giá

    @Published var alerts: [PriceAlert] = []
    @Published var alertHistory: [AlertEvent] = []
    /// Cảnh báo vừa kích hoạt → toast trên màn hình. Rỗng = không có gì.
    @Published var toast: AlertEvent?

    // MARK: - Lịch kinh tế

    @Published var events: [EconomicEvent] = []
    @Published var isLoadingCalendar = false
    @Published var calendarError: String?
    @Published var calendarUpdatedAt: Date?
    @Published var impactFilter: ImpactFilter = .mediumAndHigh
    @Published var currencyFilter: String?

    // MARK: - Tin tức

    @Published var news: [NewsItem] = []
    @Published var isLoadingNews = false
    @Published var newsError: String?
    @Published var newsCategory: NewsCategory?
    @Published var newsQuery = ""

    // MARK: - Đối tác

    @Published var partnerSummary: PartnerSummary?
    @Published var partnerRewards: [PartnerRewardRow] = []
    @Published var partnerClients: [PartnerClientRow] = []
    @Published var partnerError: String?
    @Published var isLoadingPartner = false

    private let keychain = PulseKeychain()
    private let stream = TickStream()
    private var cachedPartnerClient: ExnessClient?
    private var cachedTradingClient: TradingClient?

    var isConfigured: Bool { credentials?.isConfigured ?? false }

    /// Được vào màn hình chính khi đã có key hoặc đang dùng chế độ chỉ xem.
    var canBrowse: Bool { isConfigured || guestMode }

    var activeAlertCount: Int { alerts.filter { $0.enabled }.count }
    var isTradingConfigured: Bool { credentials?.isTradingConfigured ?? false }
    var isPartnerConfigured: Bool { credentials?.isPartnerConfigured ?? false }

    init() {
        if let stored = keychain.load() {
            credentials = stored
        }
        alerts = PriceAlertStore.load()
        alertHistory = AlertHistoryStore.load()
        events = EconomicCalendarService.loadCache()
        news = NewsService.loadCache()
        if let saved = UserDefaults.standard.stringArray(forKey: Self.watchlistKey), !saved.isEmpty {
            watchlist = saved
        }
        stream.onTick = { [weak self] quote in
            self?.handle(quote)
        }
        stream.onStatus = { [weak self] status in
            self?.streamStatus = status
        }
    }

    // MARK: - Clients

    var partnerClient: ExnessClient? {
        if let cachedPartnerClient { return cachedPartnerClient }
        guard let created = credentials?.partnerClient else { return nil }
        cachedPartnerClient = created
        return created
    }

    /// REST của tài khoản đi qua access point (nếu đã phát hiện), discovery đi qua gateway.
    var tradingClient: TradingClient? {
        if let cachedTradingClient { return cachedTradingClient }
        guard let credentials,
              let gateway = credentials.tradingGatewayCredentials,
              let account = credentials.tradingCredentials else { return nil }
        let created = TradingClient(discovery: ExnessClient(credentials: gateway),
                                    account: ExnessClient(credentials: account),
                                    accountId: credentials.accountId)
        cachedTradingClient = created
        return created
    }

    /// Mã thực sự gửi lên WebSocket: lọc theo danh sách mã của tài khoản để tránh
    /// server đóng kết nối (1008) khi có mã không tồn tại.
    var streamSymbols: [String] {
        instruments.isEmpty ? watchlist : watchlist.filter { instruments.contains($0) }
    }

    // MARK: - Lưu / xoá thông tin đăng nhập

    func save(_ newCredentials: PulseCredentials) throws {
        try keychain.save(newCredentials)
        credentials = newCredentials
        leaveGuestMode()
        cachedPartnerClient = nil
        cachedTradingClient = nil
        refreshStream()
    }

    func enterGuestMode() {
        guestMode = true
        UserDefaults.standard.set(true, forKey: Self.guestKey)
    }

    func leaveGuestMode() {
        guestMode = false
        UserDefaults.standard.set(false, forKey: Self.guestKey)
    }

    func signOut() {
        keychain.delete()
        credentials = nil
        leaveGuestMode()
        cachedPartnerClient = nil
        cachedTradingClient = nil
        tradingAccount = nil
        accountState = nil
        positions = []
        instruments = []
        quotes = [:]
        sparklines = [:]
        sessionChanges = [:]
        candles = []
        partnerSummary = nil
        partnerRewards = []
        partnerClients = []
        partnerError = nil
        errorMessage = nil
        stream.stop()
    }

    // MARK: - Kiểm tra kết nối

    /// Kiểm tra từng API đã cấu hình, lưu access point nếu phát hiện được. Trả về báo cáo nhiều dòng.
    func testConnection() async -> String {
        isTesting = true
        defer { isTesting = false }
        guard let current = credentials else { return "Chưa có thông tin đăng nhập." }

        var lines: [String] = []
        if let client = current.partnerClient {
            do {
                let link = try await client.get(PartnerDefaultLink.self,
                                                 path: "/v1/partnership/partner/default-link")
                lines.append("✓ Partnership API" + (link.fullDefaultLink.isEmpty ? "" : " · " + link.fullDefaultLink))
            } catch {
                lines.append("✗ Partnership API · " + ExnessClient.message(for: error))
            }
        }
        if let trading = current.tradingCredentials {
            // Discovery luôn đi qua gateway (host DNS widget), không qua access point cũ.
            let gateway = current.tradingGatewayCredentials ?? trading
            let client = TradingClient(discovery: ExnessClient(credentials: gateway),
                                       account: ExnessClient(credentials: trading),
                                       accountId: current.accountId)
            do {
                let point = try await client.accessPoint()
                var updated = current
                updated.accessPoint = point
                try? keychain.save(updated)
                credentials = updated
                cachedTradingClient = nil
                refreshStream()
                lines.append("✓ Trader API · access point " + point)
            } catch {
                lines.append("✗ Trader API · " + ExnessClient.message(for: error))
            }
        }
        if lines.isEmpty { lines.append("Chưa nhập đủ host/key để kiểm tra.") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Nạp dữ liệu khi mở app

    func bootstrap() async {
        async let calendarTask: Void = loadCalendar()
        async let newsTask: Void = loadNews()
        guard let current = credentials else {
            _ = await (calendarTask, newsTask)
            return
        }
        if current.isTradingConfigured {
            if current.accessPoint == nil, let client = tradingClient,
               let point = try? await client.accessPoint() {
                var updated = current
                updated.accessPoint = point
                try? keychain.save(updated)
                credentials = updated
                cachedTradingClient = nil
            }
            refreshStream()
            await loadAccount()
        }
        _ = await (calendarTask, newsTask)
        if current.isPartnerConfigured {
            await loadPartner()
        }
    }

    func refreshDashboard() async {
        async let accountTask: Void = loadAccount()
        async let sparkTask: Void = loadSparklines()
        async let calendarTask: Void = loadCalendar()
        async let newsTask: Void = loadNews()
        _ = await (accountTask, sparkTask, calendarTask, newsTask)
    }

    // MARK: - Tài khoản giao dịch

    func loadAccount() async {
        guard let client = tradingClient else { return }
        isLoadingAccount = true
        errorMessage = nil
        defer { isLoadingAccount = false }

        do {
            tradingAccount = try await client.account()
            let snapshot = try await client.snapshot()
            accountState = snapshot.accountState
            positions = snapshot.positions ?? []
            if instruments.isEmpty {
                instruments = try await client.instruments()
                refreshStream()
            }
        } catch {
            errorMessage = ExnessClient.message(for: error)
        }
    }

    // MARK: - WebSocket ticks

    func refreshStream() {
        guard let credentials, let url = credentials.ticksURL() else {
            stream.configure(url: nil, symbols: [])
            return
        }
        // Handshake WebSocket phải ký như GET với path đúng bằng path kết nối (không có query).
        let path = "/v1/server-events/accounts/\(credentials.accountId)/ws/ticks"
        stream.configure(url: url, symbols: streamSymbols) {
            guard let trading = credentials.tradingCredentials else { return [:] }
            return (try? ExnessSigner.signedHeaders(credentials: trading,
                                                     method: "GET",
                                                     pathAndQuery: path)) ?? [:]
        }
    }

    func handle(_ quote: Quote) {
        quotes[quote.symbol] = quote
        evaluateAlerts(symbol: quote.symbol, price: quote.mid)
    }

    // MARK: - Danh sách theo dõi

    func addToWatchlist(_ symbol: String) {
        let normalized = symbol.uppercased()
        guard !watchlist.contains(normalized) else { return }
        watchlist.append(normalized)
        UserDefaults.standard.set(watchlist, forKey: Self.watchlistKey)
        refreshStream()
    }

    func removeFromWatchlist(_ symbol: String) {
        watchlist.removeAll { $0 == symbol }
        UserDefaults.standard.set(watchlist, forKey: Self.watchlistKey)
        refreshStream()
    }

    /// Gọi sau khi `watchlist` thay đổi qua binding (SymbolPickerView).
    func watchlistChanged() {
        watchlist = Array(Set(watchlist)).sorted()
        UserDefaults.standard.set(watchlist, forKey: Self.watchlistKey)
        refreshStream()
    }

    // MARK: - Nến giá & sparkline

    func loadCandles() async {
        guard let client = tradingClient else {
            candles = []
            candleError = "Chưa cấu hình Trader API (host + account ID)."
            return
        }
        isLoadingCandles = true
        candleError = nil
        defer { isLoadingCandles = false }
        do {
            let list = try await client.candles(symbol: selectedSymbol, timeframe: timeframe)
            candles = list
        } catch {
            candles = []
            candleError = ExnessClient.message(for: error)
        }
    }

    func loadSparklines() async {
        guard let client = tradingClient else { return }
        let symbols = Array(streamSymbols.prefix(8))
        guard !symbols.isEmpty else { return }
        await withTaskGroup(of: (String, [Double]).self) { group in
            for symbol in symbols {
                group.addTask {
                    let list = (try? await client.candles(symbol: symbol, timeframe: .M5, count: 40)) ?? []
                    return (symbol, list.map(\.close))
                }
            }
            for await (symbol, closes) in group {
                guard closes.count >= 2, let first = closes.first, let last = closes.last, first > 0 else { continue }
                sparklines[symbol] = closes
                sessionChanges[symbol] = (last - first) / first * 100
            }
        }
    }

    // MARK: - Cảnh báo giá

    func evaluateAlerts(symbol: String, price: Double) {
        var updated = alerts
        var changed = false
        for index in updated.indices where updated[index].symbol == symbol {
            if let fired = AlertEvaluator.fire(updated[index], price: price) {
                updated[index] = fired
                changed = true
                recordFire(fired, price: price)
            }
        }
        if changed {
            alerts = updated
            PriceAlertStore.save(updated)
        }
    }

    private func recordFire(_ alert: PriceAlert, price: Double) {
        let event = AlertEvent(alertId: alert.id,
                               symbol: alert.symbol,
                               title: "Cảnh báo giá · " + PulseSymbol.displayName(alert.symbol),
                               message: alert.notificationBody(price: price),
                               price: price,
                               date: Date())
        alertHistory.insert(event, at: 0)
        if alertHistory.count > AlertHistoryStore.limit {
            alertHistory = Array(alertHistory.prefix(AlertHistoryStore.limit))
        }
        AlertHistoryStore.save(alertHistory)
        toast = event
        // App không ở foreground → gửi luôn thông báo hệ thống; ở foreground toast đã đủ rõ.
        if UIApplication.shared.applicationState != .active {
            AlertNotifier.shared.notify(alert: alert, price: price)
        }
    }

    func addAlert(_ alert: PriceAlert) {
        alerts.removeAll { $0.id == alert.id }
        alerts.insert(alert, at: 0)
        PriceAlertStore.save(alerts)
    }

    func toggleAlert(_ alert: PriceAlert) {
        guard let index = alerts.firstIndex(where: { $0.id == alert.id }) else { return }
        alerts[index].enabled.toggle()
        PriceAlertStore.save(alerts)
    }

    func deleteAlert(_ alert: PriceAlert) {
        alerts.removeAll { $0.id == alert.id }
        PriceAlertStore.save(alerts)
    }

    func dismissToast() {
        toast = nil
    }

    /// Mở tab Cảnh báo khi bấm toast / thông báo hệ thống.
    func openAlerts() {
        selectedTab = .alerts
        toast = nil
    }

    // MARK: - Lịch kinh tế

    func loadCalendar(force: Bool = false) async {
        if !force,
           let updated = calendarUpdatedAt,
           Date().timeIntervalSince(updated) < 600,
           !events.isEmpty {
            return
        }
        isLoadingCalendar = true
        calendarError = nil
        defer { isLoadingCalendar = false }
        do {
            let list = try await EconomicCalendarService.fetch()
            events = list
            calendarUpdatedAt = Date()
            EconomicCalendarService.saveCache(list)
        } catch {
            if events.isEmpty {
                calendarError = "Không tải được lịch kinh tế. Kiểm tra kết nối mạng rồi thử lại."
            }
        }
    }

    var filteredEvents: [EconomicEvent] {
        events.filter { event in
            impactFilter.includes(event.impact) &&
            (currencyFilter == nil || event.country == currencyFilter)
        }
    }

    var calendarDays: [CalendarDay] {
        EconomicCalendarService.groupByDay(filteredEvents)
    }

    var currencies: [String] {
        Array(Set(events.map(\.country))).sorted()
    }

    /// Sự kiện cao ảnh hưởng sắp tới (dùng cho Tổng quan + đếm ngược).
    var upcomingHighImpact: [EconomicEvent] {
        Array(events.filter { $0.date > Date() && $0.impact == .high }.prefix(5))
    }

    /// Bật/tắt nhắc trước `minutes` phút cho sự kiện.
    func toggleReminder(for event: EconomicEvent, minutes: Int = 15) {
        if CalendarReminderStore.minutes(for: event.id) != nil {
            AlertNotifier.shared.cancelEventReminder(eventId: event.id)
            CalendarReminderStore.set(minutes: nil, for: event.id)
        } else {
            if AlertNotifier.shared.scheduleEventReminder(event: event, minutesBefore: minutes) {
                CalendarReminderStore.set(minutes: minutes, for: event.id)
            }
        }
        objectWillChange.send()
    }

    // MARK: - Tin tức

    func loadNews(force: Bool = false) async {
        if isLoadingNews { return }
        isLoadingNews = true
        newsError = nil
        defer { isLoadingNews = false }

        let feeds = NewsSources.enabledFeeds()
        guard !feeds.isEmpty else {
            news = []
            newsError = "Chưa bật nguồn tin nào. Vào Cài đặt → Nguồn tin tức để bật."
            return
        }
        let items = await NewsService.fetch(feeds: feeds)
        if items.isEmpty {
            if news.isEmpty {
                newsError = "Không tải được tin tức. Kiểm tra kết nối mạng rồi thử lại."
            }
        } else {
            news = items
            NewsService.saveCache(items)
        }
    }

    var visibleNews: [NewsItem] {
        let scoped = newsCategory.map { category in news.filter { $0.category == category } } ?? news
        return NewsService.search(scoped, query: newsQuery)
    }

    // MARK: - Đối tác

    func loadPartner() async {
        guard let client = partnerClient else { return }
        isLoadingPartner = true
        partnerError = nil
        defer { isLoadingPartner = false }

        do {
            let tier = try await client.get(PartnerTierState.self,
                                            path: "/v1/partnership/partner-tier/partner-state")
            var summary = PartnerSummary(tierName: tier.tierName,
                                         tierGroup: tier.tierGroup,
                                         clientsCount: tier.clientsCount,
                                         clientsVolumeLots: 0,
                                         usdVolume: tier.usdVolume,
                                         rewards30d: nil,
                                         rewardRows: 0,
                                         lastRewardDate: nil)

            let from = Fmt.apiDateString(Date().addingTimeInterval(-30 * 86_400))
            let to = Fmt.apiDateString(Date())
            if let rewards = try? await client.get(PartnerRewardReport.self,
                                                   path: "/v1/partnership/reports/rewards",
                                                   query: [("limit", "1000"), ("offset", "0"), ("aggregate_by", "day"),
                                                           ("ordering", "-reward_date"),
                                                           ("reward_date_from", from), ("reward_date_to", to)]) {
                summary.rewards30d = rewards.totals.rewardUsdDecimal
                summary.rewardRows = rewards.data.count
                summary.lastRewardDate = rewards.data.first?.rewardDate
                partnerRewards = rewards.data
            }
            if let clients = try? await client.get(PartnerClientReport.self,
                                                   path: "/v1/partnership/reports/clients",
                                                   query: [("limit", "1000"), ("offset", "0"), ("ordering", "-reward_usd")]) {
                summary.clientsCount = clients.totals.count
                summary.clientsVolumeLots = clients.totals.volumeLots
                partnerClients = Array(clients.data.prefix(20))
            }
            partnerSummary = summary
        } catch {
            partnerError = ExnessClient.message(for: error)
        }
    }
}

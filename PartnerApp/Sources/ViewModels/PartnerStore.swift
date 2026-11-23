import SwiftUI
import Combine
import UIKit

// MARK: - Lịch UTC dùng chung

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}()

// MARK: - Bộ lọc

enum RewardRange: String, CaseIterable, Identifiable {
    case last7Days
    case last30Days
    case thisMonth
    case lastMonth
    case thisYear
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last7Days: return "7 ngày"
        case .last30Days: return "30 ngày"
        case .thisMonth: return "Tháng này"
        case .lastMonth: return "Tháng trước"
        case .thisYear: return "Năm nay"
        case .allTime: return "Tất cả"
        }
    }

    /// Khoảng ngày gửi lên API (UTC). `nil` = không lọc ngày.
    var fromTo: (from: String, to: String)? {
        let calendar = utcCalendar
        let now = Date()
        let today = calendar.startOfDay(for: now)

        func format(_ date: Date) -> String { Fmt.apiDateString(date) }

        switch self {
        case .last7Days:
            guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return nil }
            return (from: format(start), to: format(today))
        case .last30Days:
            guard let start = calendar.date(byAdding: .day, value: -29, to: today) else { return nil }
            return (from: format(start), to: format(today))
        case .thisMonth:
            let components = calendar.dateComponents([.year, .month], from: now)
            guard let start = calendar.date(from: components) else { return nil }
            return (from: format(start), to: format(today))
        case .lastMonth:
            let components = calendar.dateComponents([.year, .month], from: now)
            guard let startThisMonth = calendar.date(from: components),
                  let startLastMonth = calendar.date(byAdding: .month, value: -1, to: startThisMonth),
                  let endLastMonth = calendar.date(byAdding: .day, value: -1, to: startThisMonth) else {
                return nil
            }
            return (from: format(startLastMonth), to: format(endLastMonth))
        case .thisYear:
            let components = calendar.dateComponents([.year], from: now)
            guard let start = calendar.date(from: components) else { return nil }
            return (from: format(start), to: format(today))
        case .allTime:
            return nil
        }
    }
}

enum RewardAggregate: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Ngày"
        case .week: return "Tuần"
        case .month: return "Tháng"
        }
    }
}

enum ClientSort: String, CaseIterable, Identifiable {
    case reward
    case volume
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reward: return "Hoa hồng"
        case .volume: return "Volume"
        case .newest: return "Mới nhất"
        }
    }
}

// MARK: - Store

/// Trạng thái trung tâm của app: thông tin đăng nhập + dữ liệu API.
@MainActor
final class PartnerStore: ObservableObject {
    @Published var credentials: ExnessCredentials?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    @Published var rewardReport: RewardReport?
    @Published var clientReport: ClientReport?
    @Published var orderReport: OrderReport?
    @Published var pendingReport: PendingReport?
    @Published var tierState: TierState?
    @Published var rebateHistory: RebateHistoryReport?
    @Published var rebatePayments: RebatePaymentsReport?
    @Published var defaultLink: DefaultLink?

    @Published var rewardRange: RewardRange = .last30Days
    @Published var rewardAggregate: RewardAggregate = .day
    @Published var transactionDays: Int = 7
    @Published var clientQuery = ""
    @Published var clientSort: ClientSort = .reward

    /// Tab đang chọn (để pop-up thanh toán có thể điều hướng sang tab Hoa hồng).
    @Published var selectedTab: AppTab = .overview
    /// Khoản thanh toán mới phát hiện → hiện pop-up. Rỗng = không có gì.
    @Published var paymentEvents: [PaymentEvent] = []
    @Published var lastPaymentCheck: Date?

    private let keychain = CredentialKeychain()
    private var cachedClient: ExnessClient?

        var isConfigured: Bool { credentials != nil }

    private var client: ExnessClient? {
        if let cachedClient { return cachedClient }
        guard let credentials else { return nil }
        let created = ExnessClient(credentials: credentials)
        cachedClient = created
        return created
    }

    init() {
        if let stored = keychain.load() {
            credentials = stored
            cachedClient = ExnessClient(credentials: stored)
        }
    }

    // MARK: - Thông tin đăng nhập

    func save(_ newCredentials: ExnessCredentials) throws {
        // Đổi sang tài khoản/host khác → bỏ dấu vết cũ để không báo nhầm khoản "mới".
        if let old = credentials,
           old.apiKey != newCredentials.apiKey || old.baseURL != newCredentials.baseURL {
            PaymentWatcher.clearSnapshot()
            paymentEvents = []
            lastPaymentCheck = nil
        }
        try keychain.save(newCredentials)
        credentials = newCredentials
        cachedClient = ExnessClient(credentials: newCredentials)
    }

    func signOut() {
        keychain.delete()
        credentials = nil
        cachedClient = nil
        rewardReport = nil
        clientReport = nil
        orderReport = nil
        pendingReport = nil
        tierState = nil
        rebateHistory = nil
        rebatePayments = nil
        defaultLink = nil
        errorMessage = nil
        lastUpdated = nil
        paymentEvents = []
        lastPaymentCheck = nil
        PaymentWatcher.clearSnapshot()
    }

    /// Kiểm tra kết nối bằng endpoint nhẹ nhất: lấy link giới thiệu mặc định.
    func testConnection(with credentials: ExnessCredentials) async throws -> DefaultLink {
        let temporaryClient = ExnessClient(credentials: credentials)
        return try await temporaryClient.get(DefaultLink.self,
                                             path: "/v1/partnership/partner/default-link")
    }

    // MARK: - Nạp dữ liệu

    func refreshAll() async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Mỗi endpoint độc lập: một endpoint lỗi không chặn các báo cáo còn lại.
        var firstError: String?

        do {
            tierState = try await client.get(TierState.self,
                                             path: "/v1/partnership/partner-tier/partner-state")
        } catch {
            firstError = firstError ?? Self.message(for: error)
        }

        do {
            pendingReport = try await client.get(PendingReport.self,
                                                 path: "/v1/partnership/reports/orders/pending",
                                                 query: [("limit", "1000"), ("offset", "0")])
        } catch {
            firstError = firstError ?? Self.message(for: error)
        }

        do {
            clientReport = try await client.get(ClientReport.self,
                                                path: "/v1/partnership/reports/clients",
                                                query: [("limit", "1000"), ("offset", "0"), ("ordering", "-reward_usd")])
        } catch {
            firstError = firstError ?? Self.message(for: error)
        }

        do {
            rewardReport = try await client.get(RewardReport.self,
                                                path: "/v1/partnership/reports/rewards",
                                                query: rewardQuery())
        } catch {
            firstError = firstError ?? Self.message(for: error)
        }

        do {
            rebateHistory = try await client.get(RebateHistoryReport.self,
                                                 path: "/v1/partnership/autorebates/history",
                                                 query: [("limit", "200"), ("offset", "0"), ("ordering", "-reward_date")])
        } catch {
            firstError = firstError ?? Self.message(for: error)
        }

        do {
            rebatePayments = try await client.get(RebatePaymentsReport.self,
                                                  path: "/v1/partnership/autorebates/payments",
                                                  query: [("limit", "200"), ("offset", "0"), ("ordering", "-processed_date")])
        } catch {
            firstError = firstError ?? Self.message(for: error)
        }

        errorMessage = firstError
        lastUpdated = Date()

        if defaultLink == nil {
            await loadDefaultLink()
        }

        // Tác vụ phụ: không chặn UI khi lỗi.
        await checkForPayments()
    }

    // MARK: - Thông báo thanh toán

    /// So sánh với lần kiểm tra trước để tìm khoản MỚI (hoa hồng theo ngày + hoàn phí).
    /// Lần đầu chỉ ghi nhận baseline. Trả về các khoản mới để view báo kết quả.
    @discardableResult
    func checkForPayments() async -> [PaymentEvent] {
        guard let client else { return [] }
        do {
            let events = try await PaymentWatcher.check(using: client)
            lastPaymentCheck = Date()
            guard !events.isEmpty else { return [] }
            paymentEvents = events
            if UIApplication.shared.applicationState != .active {
                PaymentNotifier.shared.notify(events: events)
            }
            return events
        } catch {
            return []
        }
    }

    /// Chạm vào pop-up / thông báo hệ thống → mở tab Hoa hồng.
    func openPayments() {
        selectedTab = .rewards
        paymentEvents = []
    }

    func loadRewards() async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            rewardReport = try await client.get(RewardReport.self,
                                                path: "/v1/partnership/reports/rewards",
                                                query: rewardQuery())
            lastUpdated = Date()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func loadClients() async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            clientReport = try await client.get(ClientReport.self,
                                                path: "/v1/partnership/reports/clients",
                                                query: [("limit", "1000"), ("offset", "0"), ("ordering", "-reward_usd")])
            lastUpdated = Date()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func loadTransactions() async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let today = utcCalendar.startOfDay(for: Date())
        guard let from = utcCalendar.date(byAdding: .day, value: -(transactionDays - 1), to: today) else {
            return
        }

        do {
            orderReport = try await client.get(OrderReport.self,
                                               path: "/v1/partnership/reports/orders",
                                               query: [
                                                   ("date_from", Fmt.apiDateString(from)),
                                                   ("date_to", Fmt.apiDateString(today)),
                                                   ("limit", "1000"),
                                                   ("offset", "0"),
                                                   ("ordering", "-close_date")
                                               ])
            pendingReport = try await client.get(PendingReport.self,
                                                 path: "/v1/partnership/reports/orders/pending",
                                                 query: [("limit", "1000"), ("offset", "0")])
            lastUpdated = Date()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func loadRebates() async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            rebateHistory = try await client.get(RebateHistoryReport.self,
                                                 path: "/v1/partnership/autorebates/history",
                                                 query: [("limit", "200"), ("offset", "0"), ("ordering", "-reward_date")])
            rebatePayments = try await client.get(RebatePaymentsReport.self,
                                                  path: "/v1/partnership/autorebates/payments",
                                                  query: [("limit", "200"), ("offset", "0"), ("ordering", "-processed_date")])
            lastUpdated = Date()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func loadDefaultLink() async {
        guard let client else { return }
        do {
            defaultLink = try await client.get(DefaultLink.self,
                                               path: "/v1/partnership/partner/default-link")
        } catch {
            // Không chặn màn hình chính nếu endpoint này lỗi.
        }
    }

    private func rewardQuery() -> [(String, String?)] {
        var query: [(String, String?)] = [
            ("limit", "1000"),
            ("offset", "0"),
            ("aggregate_by", rewardAggregate.rawValue),
            ("ordering", "-reward_date")
        ]
        if let range = rewardRange.fromTo {
            query.append(("reward_date_from", range.from))
            query.append(("reward_date_to", range.to))
        }
        return query
    }

    // MARK: - Dữ liệu dẫn xuất

    var rewardRows: [RewardRow] { rewardReport?.data ?? [] }

    var recentRewards: [RewardRow] {
        Array(rewardRows.sorted { $0.rewardDate > $1.rewardDate }.prefix(5))
    }

    var rewardChartPoints: [ChartPoint] {
        guard !rewardRows.isEmpty else { return [] }

        var buckets: [String: (sortKey: String, total: Decimal)] = [:]
        for row in rewardRows {
            guard let date = Fmt.parseDate(row.rewardDate) else { continue }
            let key = Self.bucketLabel(for: date, aggregate: rewardAggregate)
            let sortKey = Self.bucketSortKey(for: date, aggregate: rewardAggregate)
            let value = row.rewardUsdDecimal
            if let existing = buckets[key] {
                buckets[key] = (existing.sortKey, existing.total + value)
            } else {
                buckets[key] = (sortKey, value)
            }
        }

        return buckets
            .map { key, bucket in
                ChartPoint(label: key,
                           sortKey: bucket.sortKey,
                           value: bucket.total.doubleValue,
                           detail: Fmt.usd(bucket.total))
            }
            .sorted { $0.sortKey < $1.sortKey }
    }

    var filteredClients: [ClientRow] {
        let rows = clientReport?.data ?? []
        let query = clientQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var result = query.isEmpty ? rows : rows.filter { row in
            if row.clientUid.lowercased().contains(query) { return true }
            if row.clientCountry.lowercased().contains(query) { return true }
            if (row.clientStatus ?? "").lowercased().contains(query) { return true }
            return false
        }

        switch clientSort {
        case .reward:
            result.sort { $0.rewardUsdDecimal > $1.rewardUsdDecimal }
        case .volume:
            result.sort { $0.volumeLots > $1.volumeLots }
        case .newest:
            result.sort { $0.regDate > $1.regDate }
        }
        return result
    }

    var overviewRewardUSD: Decimal {
        rewardReport?.totals.rewardUsdDecimal ?? 0
    }

    var overviewVolumeLots: Double {
        rewardReport?.totals.volumeLots ?? 0
    }

    var overviewOrders: Int {
        rewardReport?.totals.ordersCount ?? 0
    }

    var clientCount: Int {
        clientReport?.totals.count ?? 0
    }

    var pendingVolumeLots: Double {
        pendingReport?.totals.volumeLots ?? 0
    }

    var pendingOrders: Int {
        pendingReport?.totals.countOrders ?? 0
    }

    var rebateProcessedUSD: Double {
        rebatePayments?.totals.processedRebateUsd ?? 0
    }

    var rebateRejectedUSD: Double {
        rebatePayments?.totals.rejectedRebateUsd ?? 0
    }

    var rebateErrorUSD: Double {
        rebatePayments?.totals.errorRebateUsd ?? 0
    }

    // MARK: - Nhãn biểu đồ

    private static let dayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "dd/MM"
        return formatter
    }()

    private static let daySortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "MM/yy"
        return formatter
    }()

    private static let monthSortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    static func bucketLabel(for date: Date, aggregate: RewardAggregate) -> String {
        switch aggregate {
        case .day:
            return dayLabelFormatter.string(from: date)
        case .week:
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = utcCalendar.timeZone
            let components = calendar.dateComponents([.weekOfYear], from: date)
            return "W" + String(format: "%02d", components.weekOfYear ?? 0)
        case .month:
            return monthLabelFormatter.string(from: date)
        }
    }

    static func bucketSortKey(for date: Date, aggregate: RewardAggregate) -> String {
        switch aggregate {
        case .day:
            return daySortFormatter.string(from: date)
        case .week:
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = utcCalendar.timeZone
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return String(format: "%04d-W%02d",
                          components.yearForWeekOfYear ?? 0,
                          components.weekOfYear ?? 0)
        case .month:
            return monthSortFormatter.string(from: date)
        }
    }

    // MARK: - Trạng thái rebate

    static func statusColor(_ status: String?) -> Color {
        switch (status ?? "").uppercased() {
        case "PROCESSED":
            return PartnerTheme.success
        case "REJECTED", "ERROR":
            return PartnerTheme.danger
        case "PROCESSING", "APPROVED", "PENDING":
            return PartnerTheme.warning
        default:
            return PartnerTheme.textSecondary
        }
    }

    // MARK: - Helper

    nonisolated static func message(for error: Error) -> String {
        if let apiError = error as? ExnessAPIError {
            return apiError.localizedMessage
        }
        if let localized = error as? LocalizedError, let text = localized.errorDescription {
            return text
        }
        return error.localizedDescription
    }
}

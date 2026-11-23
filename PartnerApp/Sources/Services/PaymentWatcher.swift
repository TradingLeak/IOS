import Foundation

/// Theo dõi khoản thanh toán hoa hồng: so sánh dữ liệu API với lần kiểm tra trước
/// để phát hiện khoản MỚI. `diff` là hàm thuần (có unit test), không gọi API.
enum PaymentWatcher {
    static let snapshotKey = "partnerhub.paymentSnapshot"
    static let rewardsPath = "/v1/partnership/reports/rewards"
    static let rebatePaymentsPath = "/v1/partnership/autorebates/payments"

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    // MARK: - Snapshot (UserDefaults — không chứa bí mật)

    static func loadSnapshot() -> PaymentSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(PaymentSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: PaymentSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }

    static func clearSnapshot() {
        UserDefaults.standard.removeObject(forKey: snapshotKey)
    }

    // MARK: - Query (độc lập với bộ lọc trên màn hình Hoa hồng)

    /// Lấy các ngày từ lần kiểm tra trước (lùi 1 ngày cho an toàn), tối đa 30 ngày gần nhất.
    static func rewardQuery(lastChecked: Date?, now: Date = Date()) -> [(String, String?)] {
        let today = utcCalendar.startOfDay(for: now)
        var start = utcCalendar.date(byAdding: .day, value: -29, to: today) ?? today
        if let lastChecked {
            let lastDay = utcCalendar.startOfDay(for: lastChecked)
            if let dayBefore = utcCalendar.date(byAdding: .day, value: -1, to: lastDay), dayBefore > start {
                start = dayBefore
            }
        }
        return [
            ("limit", "100"),
            ("offset", "0"),
            ("aggregate_by", "day"),
            ("ordering", "-reward_date"),
            ("reward_date_from", Fmt.apiDateString(start)),
            ("reward_date_to", Fmt.apiDateString(today))
        ]
    }

    static let rebateQuery: [(String, String?)] = [
        ("limit", "50"),
        ("offset", "0"),
        ("ordering", "-processed_date")
    ]

    // MARK: - Kiểm tra qua API

    /// Tải rewards + rebate payments, so với snapshot, lưu snapshot mới.
    /// Trả về các khoản MỚI; lần đầu chạy chỉ ghi nhận baseline nên trả về rỗng.
    /// Hai endpoint độc lập: một bên lỗi vẫn xử lý được bên kia.
    static func check(using client: ExnessClient) async throws -> [PaymentEvent] {
        let previous = loadSnapshot()

        var rewardRows: [RewardRow] = []
        var rebateRows: [RebatePaymentRow] = []
        var rewardLoaded = false
        var rebateLoaded = false
        var firstError: Error?

        do {
            rewardRows = try await client.get(RewardReport.self,
                                              path: rewardsPath,
                                              query: rewardQuery(lastChecked: previous?.lastChecked)).data
            rewardLoaded = true
        } catch {
            firstError = error
        }

        do {
            rebateRows = try await client.get(RebatePaymentsReport.self,
                                              path: rebatePaymentsPath,
                                              query: rebateQuery).data
            rebateLoaded = true
        } catch {
            firstError = firstError ?? error
        }

        guard rewardLoaded || rebateLoaded else {
            throw firstError ?? URLError(.badServerResponse)
        }

        let result = diff(previous: previous,
                          rewards: rewardRows,
                          rebatePayments: rebateRows)
        saveSnapshot(result.snapshot)
        return result.events
    }

    // MARK: - So sánh (thuần)

    static func diff(previous: PaymentSnapshot?,
                     rewards: [RewardRow],
                     rebatePayments: [RebatePaymentRow],
                     now: Date = Date()) -> (events: [PaymentEvent], snapshot: PaymentSnapshot) {
        var snapshot = previous ?? PaymentSnapshot(lastChecked: now)
        snapshot.lastChecked = now
        var events: [PaymentEvent] = []

        // 1) Hoa hồng theo ngày — nhiều dòng cùng ngày (nhiều tài khoản đối tác) thì cộng dồn.
        var amounts: [String: Decimal] = [:]
        var dates: [String: Date] = [:]
        for row in rewards {
            amounts[row.rewardDate, default: 0] += row.rewardUsdDecimal
            if dates[row.rewardDate] == nil {
                dates[row.rewardDate] = Fmt.parseDate(row.rewardDate)
            }
        }
        if previous != nil {
            for (rawDate, amount) in amounts where !snapshot.rewardDates.contains(rawDate) {
                let shown = Fmt.date(rawDate)
                events.append(PaymentEvent(id: "reward:" + rawDate,
                                           kind: .reward,
                                           amountUSD: amount,
                                           dateText: shown,
                                           detail: "",
                                           sortDate: dates[rawDate] ?? nil))
            }
        }
        snapshot.rewardDates.formUnion(amounts.keys)

        // 2) Thanh toán hoàn phí — mỗi dòng có `id` riêng, chỉ báo trạng thái đã biết.
        for row in rebatePayments {
            let isNew = previous != nil && !snapshot.rebatePaymentIDs.contains(row.id)
            snapshot.rebatePaymentIDs.insert(row.id)
            guard isNew, let paymentKind = kind(forRebateStatus: row.status) else { continue }

            var detail = "KH ••" + String(row.clientAccount.suffix(4))
            if let processed = row.processedDate, !processed.isEmpty {
                let clock = Fmt.time(processed)
                if !clock.isEmpty { detail += " · " + clock }
            }
            if !paymentKind.isPositive, let code = row.errorCode, !code.isEmpty {
                detail += " · " + code
            }

            events.append(PaymentEvent(id: "rebate:" + String(row.id),
                                       kind: paymentKind,
                                       amountUSD: Decimal(row.rebateUsd),
                                       dateText: Fmt.date(row.processedDate ?? ""),
                                       detail: detail,
                                       sortDate: Fmt.parseDate(row.processedDate ?? "")))
        }

        events.sort { ($0.sortDate ?? .distantPast) > ($1.sortDate ?? .distantPast) }
        return (events, snapshot)
    }

    static func kind(forRebateStatus status: String) -> PaymentKind? {
        switch status.uppercased() {
        case "PROCESSED": return .rebateProcessed
        case "REJECTED": return .rebateRejected
        case "ERROR": return .rebateError
        default: return nil
        }
    }

    // MARK: - Nội dung thông báo hệ thống

    static func summary(of events: [PaymentEvent]) -> (title: String, body: String) {
        guard let first = events.first else {
            return ("PartnerHub", "Có khoản thanh toán mới.")
        }
        guard events.count > 1 else {
            return (first.kind.title, first.notificationBody)
        }
        let total = events.filter { $0.kind.isPositive }.reduce(Decimal(0)) { $0 + $1.amountUSD }
        return ("\(events.count) khoản thanh toán mới",
                "Tổng " + Fmt.usd(total) + " · gần nhất: " + first.notificationBody)
    }
}

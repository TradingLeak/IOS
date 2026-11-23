import Foundation

/// Một cảnh báo giá do người dùng tạo cho một mã hiệu.
struct PriceAlert: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var symbol: String
    var condition: Condition
    var direction: Direction
    /// Mức mục tiêu: giá (mid) khi `.price`, hoặc phần trăm khi `.percentChange`.
    var targetValue: Double
    /// Giá tham chiếu lúc tạo cảnh báo (mid price): dùng cho `%` và cho hướng "chạm mức".
    var basePrice: Double?
    var note: String
    var createdAt: Date
    var enabled: Bool
    var lastTriggeredAt: Date?
    var triggerCount: Int

    enum Condition: String, Codable, CaseIterable, Identifiable {
        case price, percentChange

        var id: String { rawValue }

        var title: String {
            switch self {
            case .price: return "Giá chạm mức"
            case .percentChange: return "Biên độ %"
            }
        }

        var detail: String {
            switch self {
            case .price: return "Khi mid price (trung bình bid/ask) đi qua mức bạn đặt."
            case .percentChange: return "Khi giá biến động đủ X% so với giá tham chiếu lúc tạo cảnh báo."
            }
        }

        var icon: String {
            switch self {
            case .price: return "scope"
            case .percentChange: return "percent"
            }
        }
    }

    /// Chỉ áp dụng cho điều kiện `.price`.
    enum Direction: String, Codable, CaseIterable, Identifiable {
        case above, below, cross

        var id: String { rawValue }

        var title: String {
            switch self {
            case .above: return "Vượt lên"
            case .below: return "Rơi xuống"
            case .cross: return "Chạm mức"
            }
        }

        var symbol: String {
            switch self {
            case .above: return "arrow.up.right"
            case .below: return "arrow.down.right"
            case .cross: return "arrow.left.arrow.right"
            }
        }
    }

    init(id: UUID = UUID(),
         symbol: String,
         condition: Condition,
         direction: Direction = .cross,
         targetValue: Double,
         basePrice: Double? = nil,
         note: String = "",
         createdAt: Date = Date(),
         enabled: Bool = true,
         lastTriggeredAt: Date? = nil,
         triggerCount: Int = 0) {
        self.id = id
        self.symbol = symbol
        self.condition = condition
        self.direction = direction
        self.targetValue = targetValue
        self.basePrice = basePrice
        self.note = note
        self.createdAt = createdAt
        self.enabled = enabled
        self.lastTriggeredAt = lastTriggeredAt
        self.triggerCount = triggerCount
    }

    /// True nếu giá hiện tại thoả điều kiện (chưa xét cooldown).
    func isTriggered(by price: Double) -> Bool {
        switch condition {
        case .price:
            switch direction {
            case .above:
                return price >= targetValue
            case .below:
                return price <= targetValue
            case .cross:
                guard let basePrice else { return price >= targetValue }
                if basePrice < targetValue { return price >= targetValue }
                if basePrice > targetValue { return price <= targetValue }
                return true
            }
        case .percentChange:
            guard let basePrice, basePrice > 0 else { return false }
            let change = (price - basePrice) / basePrice * 100
            return abs(change) >= targetValue
        }
    }

    /// Mô tả ngắn điều kiện, dùng cho card và thông báo.
    var conditionText: String {
        let digits = PulseSymbol.digits(for: symbol)
        switch condition {
        case .price:
            switch direction {
            case .above: return "≥ " + PulseFormat.price(targetValue, digits: digits)
            case .below: return "≤ " + PulseFormat.price(targetValue, digits: digits)
            case .cross:
                let base = basePrice.map { PulseFormat.price($0, digits: digits) } ?? "—"
                return "Từ \(base) chạm " + PulseFormat.price(targetValue, digits: digits)
            }
        case .percentChange:
            return "±" + PulseFormat.price(targetValue, digits: 2) + "%"
        }
    }

    var displayTarget: String {
        switch condition {
        case .price: return PulseFormat.price(targetValue, symbol: symbol)
        case .percentChange: return "±" + PulseFormat.price(targetValue, digits: 2) + "%"
        }
    }

    /// Nội dung thông báo khi kích hoạt.
    func notificationBody(price: Double) -> String {
        let now = PulseFormat.price(price, symbol: symbol)
        let direction = price >= targetValue ? "lên" : "xuống"
        switch condition {
        case .price:
            return "\(PulseSymbol.displayName(symbol)) đi \(direction) \(now) — mức cảnh báo \(displayTarget)."
        case .percentChange:
            guard let basePrice, basePrice > 0 else { return "\(PulseSymbol.displayName(symbol)) hiện \(now)." }
            let change = (price - basePrice) / basePrice * 100
            return "\(PulseSymbol.displayName(symbol)) biến động \(PulseFormat.signedPrice(change, digits: 2))%, hiện \(now)."
        }
    }
}

/// Lưu trữ cảnh báo trong UserDefaults (mã hoá JSON).
enum PriceAlertStore {
    static let key = "pulse.priceAlerts"

    static func load() -> [PriceAlert] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PriceAlert].self, from: data)) ?? []
    }

    static func save(_ alerts: [PriceAlert]) {
        if let data = try? JSONEncoder().encode(alerts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Đánh giá cảnh báo (dùng chung cho app và Background App Refresh).
enum AlertEvaluator {
    /// Thời gian chờ tối thiểu giữa hai lần kích hoạt cùng một cảnh báo (biên độ %).
    static let cooldown: TimeInterval = 60 * 60

    /// Trả về bản cảnh báo đã cập nhật nếu kích hoạt ngay lúc này, ngược lại `nil`.
    /// Cảnh báo theo mức giá là một lần (tự tắt sau khi kích hoạt); cảnh báo theo %
    /// giữ bật nhưng bị giới hạn bởi cooldown.
    static func fire(_ alert: PriceAlert, price: Double, now: Date = Date()) -> PriceAlert? {
        guard alert.enabled, alert.isTriggered(by: price) else { return nil }
        if let last = alert.lastTriggeredAt, now.timeIntervalSince(last) < cooldown { return nil }
        var updated = alert
        updated.lastTriggeredAt = now
        updated.triggerCount += 1
        if alert.condition == .price {
            updated.enabled = false
        }
        return updated
    }
}

/// Một lần cảnh báo đã kích hoạt (lịch sử).
struct AlertEvent: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    let alertId: UUID
    let symbol: String
    let title: String
    let message: String
    let price: Double
    let date: Date

    init(id: UUID = UUID(), alertId: UUID, symbol: String, title: String, message: String, price: Double, date: Date) {
        self.id = id
        self.alertId = alertId
        self.symbol = symbol
        self.title = title
        self.message = message
        self.price = price
        self.date = date
    }
}

enum AlertHistoryStore {
    static let key = "pulse.alertHistory"
    static let limit = 50

    static func load() -> [AlertEvent] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([AlertEvent].self, from: data)) ?? []
    }

    static func save(_ events: [AlertEvent]) {
        let trimmed = Array(events.prefix(limit))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Nhắc sự kiện kinh tế bằng local notification (số phút trước giờ phát hành).
enum CalendarReminderStore {
    static let key = "pulse.calendar.reminders"

    static func load() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    static func minutes(for eventId: String) -> Int? {
        load()[eventId]
    }

    static func set(minutes: Int?, for eventId: String) {
        var all = load()
        if let minutes {
            all[eventId] = minutes
        } else {
            all.removeValue(forKey: eventId)
        }
        UserDefaults.standard.set(all, forKey: key)
    }

    /// Id thông báo hệ thống tương ứng với một sự kiện.
    static func notificationId(for eventId: String) -> String {
        "pulse.event." + eventId.replacingOccurrences(of: "|", with: "_")
    }
}

import Foundation

// MARK: - Trading API (Exness Trader API) — mô hình giải mã

/// `GET /v1/trading/access-point?account_id=…` trên Gateway (host trong DNS widget).
struct AccessPointResponse: Decodable {
    let accessPoint: String
}

/// `GET /v1/configuration/accounts/{id}/account`
struct TradingAccountInfo: Decodable {
    let currency: String?
    let leverage: String?
    let marginCallLevel: String?
    let stopOutLevel: String?
    let tradeMode: String?
    let accountStatus: String?
    let type: String?
    let name: String?
}

/// `GET /v1/market-data/accounts/{id}/candles?price_type=bid` — giá là JSON number.
struct Candle: Decodable, Equatable {
    let time: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double?
}

struct CandleHistory: Decodable {
    let candles: [Candle]
}

/// Tin nhắn WebSocket `/ws/ticks`.
struct Tick: Decodable, Equatable {
    let instrument: String
    let bid: Double
    let ask: Double
    let timestamp: String?
}

/// Báo giá hiện tại của một mã.
struct Quote: Equatable {
    let symbol: String
    let bid: Double
    let ask: Double
    let timestamp: Date?

    var mid: Double { (bid + ask) / 2 }
    var spread: Double { ask - bid }
}

/// `GET /v1/trading/accounts/{id}/snapshot`
struct TradingSnapshot: Decodable {
    let orders: [TradingOrder]?
    let positions: [TradingPosition]?
    let accountState: AccountState?
}

struct AccountState: Decodable, Equatable {
    let balance: String?
    let equity: String?
    let usedMargin: String?
    let leverage: String?

    var balanceDecimal: Decimal? { balance.flatMap { Decimal(apiString: $0) } }
    var equityDecimal: Decimal? { equity.flatMap { Decimal(apiString: $0) } }
    var usedMarginDecimal: Decimal? { usedMargin.flatMap { Decimal(apiString: $0) } }
}

struct TradingPosition: Decodable, Identifiable {
    let positionId: String?
    let instrument: String?
    let direction: String?
    let volume: String?
    let openPrice: String?
    let state: String?
    let createTime: String?

    var id: String { positionId ?? UUID().uuidString }
}

struct TradingOrder: Decodable, Identifiable {
    let orderId: String?
    let instrument: String?
    let orderType: String?
    let state: String?
    let direction: String?
    let volume: String?
    let price: String?

    var id: String { orderId ?? UUID().uuidString }
}

// MARK: - Khung thời gian nến

enum Timeframe: String, CaseIterable, Identifiable {
    case M1, M5, M15, M30, H1, H4, D1

    var id: String { rawValue }

    var title: String {
        switch self {
        case .M1: return "1 phút"
        case .M5: return "5 phút"
        case .M15: return "15 phút"
        case .M30: return "30 phút"
        case .H1: return "1 giờ"
        case .H4: return "4 giờ"
        case .D1: return "1 ngày"
        }
    }

    /// Số nến tải mặc định cho biểu đồ.
    var defaultCount: Int {
        switch self {
        case .M1: return 90
        case .M5, .M15, .M30: return 120
        case .H1: return 120
        case .H4: return 150
        case .D1: return 180
        }
    }

    /// Độ dài một nến tính bằng giây (để tính `from`/`to` cho API).
    var seconds: Int {
        switch self {
        case .M1: return 60
        case .M5: return 300
        case .M15: return 900
        case .M30: return 1_800
        case .H1: return 3_600
        case .H4: return 14_400
        case .D1: return 86_400
        }
    }
}

// MARK: - Phân loại mã & định dạng giá

enum SymbolCategory: String, CaseIterable, Identifiable {
    case forex, metals, crypto, energy, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forex: return "Forex"
        case .metals: return "Vàng & Kim loại"
        case .crypto: return "Tiền mã hoá"
        case .energy: return "Năng lượng"
        case .other: return "Khác"
        }
    }

    var symbol: String {
        switch self {
        case .forex: return "dollarsign.arrow.circlepath"
        case .metals: return "sparkles"
        case .crypto: return "bitcoinsign.circle"
        case .energy: return "fuelpump"
        case .other: return "chart.line.uptrend.xyaxis"
        }
    }
}

enum PulseSymbol {
    private static let cryptoPrefixes = ["BTC", "ETH", "XRP", "SOL", "DOGE", "LTC", "ADA", "BNB", "DOT", "AVAX", "LINK", "UNI", "MATIC", "TRX", "SHIB", "PEPE", "SUI", "TON", "HBAR", "XLM"]
    private static let energyTokens = ["OIL", "GAS", "NGAS", "BRENT", "WTI", "XTI", "XBR", "UKGAS", "NATGAS"]
    private static let metalTokens = ["XAU", "XAG", "GOLD", "SILVER", "XPT", "XPD", "PLAT", "PALL"]
    private static let knownDigits: [String: Int] = ["XAUUSD": 2, "XAGUSD": 3, "BTCUSD": 2, "ETHUSD": 2, "USOIL": 2, "UKOIL": 2, "NGAS": 3, "XPTUSD": 2, "XPDUSD": 2]
    private static let fiatCodes: Set<String> = ["USD", "EUR", "GBP", "JPY", "AUD", "CAD", "CHF", "NZD", "CNY", "SGD", "HKD", "MXN", "ZAR", "TRY", "PLN", "NOK", "SEK", "DKK", "HUF", "CZK", "CNH", "ILS", "THB"]

    /// Số chữ số thập phân hiển thị theo loại mã (heuristic, không gọi API).
    static func digits(for symbol: String) -> Int {
        let s = symbol.uppercased()
        if let known = knownDigits[s] { return known }
        if s.contains("JPY") { return 3 }
        if category(for: s) == .metals { return 2 }
        if category(for: s) == .crypto { return 2 }
        if category(for: s) == .energy { return 2 }
        return 5
    }

    static func category(for symbol: String) -> SymbolCategory {
        let s = symbol.uppercased()
        if metalTokens.contains(where: { s.contains($0) }) { return .metals }
        if cryptoPrefixes.contains(where: { s.hasPrefix($0) }) { return .crypto }
        if energyTokens.contains(where: { s.contains($0) }) { return .energy }
        if s.count >= 6 {
            let base = s.count == 6 || s.dropFirst(6).allSatisfy({ $0.isNumber || $0 == "m" || $0 == "c" }) ? String(s.prefix(6)) : s
            let a = String(base.prefix(3))
            let b = String(base.suffix(3))
            if fiatCodes.contains(a), fiatCodes.contains(b), a != b { return .forex }
        }
        return .other
    }

    /// Tên hiển thị thân thiện: `XAUUSD` → "XAU/USD".
    static func displayName(_ symbol: String) -> String {
        let s = symbol.uppercased()
        let kind = category(for: s)
        if s.count == 6, kind == .forex || kind == .metals || kind == .crypto {
            return String(s.prefix(3)) + "/" + String(s.suffix(3))
        }
        return s
    }

    /// Cờ (emoji) cho mã tiền tệ trong lịch kinh tế.
    static func flag(forCurrency code: String) -> String {
        switch code.uppercased() {
        case "USD": return "🇺🇸"
        case "EUR": return "🇪🇺"
        case "GBP": return "🇬🇧"
        case "JPY": return "🇯🇵"
        case "AUD": return "🇦🇺"
        case "CAD": return "🇨🇦"
        case "CHF": return "🇨🇭"
        case "CNY": return "🇨🇳"
        case "NZD": return "🇳🇿"
        default: return "🌍"
        }
    }
}

/// Định dạng riêng của Pulse: giá theo chuẩn trader (dấu chấm thập phân), thời gian tương đối.
enum PulseFormat {
    static func price(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }

    static func price(_ value: Double, symbol: String) -> String {
        price(value, digits: PulseSymbol.digits(for: symbol))
    }

    static func signedPrice(_ value: Double, digits: Int) -> String {
        let text = price(value, digits: digits)
        return value > 0 ? "+" + text : text
    }

    static func money(_ value: Decimal?, currency: String?) -> String {
        guard let value else { return "—" }
        let code = currency ?? "USD"
        if code.uppercased() == "USD" { return Fmt.usd(value) }
        return Fmt.decimal(value.doubleValue) + " " + code
    }

    /// "5 phút trước" / "2 giờ trước" / "Hôm qua" / "3 ngày trước".
    static func relativeTime(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 0 {
            let left = -seconds
            if left < 3600 { return "còn \(max(left / 60, 1)) phút" }
            if left < 86_400 { return "còn \(left / 3600) giờ" }
            return "còn \(left / 86_400) ngày"
        }
        if seconds < 60 { return "vừa xong" }
        if seconds < 3600 { return "\(seconds / 60) phút trước" }
        if seconds < 86_400 { return "\(seconds / 3600) giờ trước" }
        if seconds < 2 * 86_400 { return "Hôm qua" }
        return "\(seconds / 86_400) ngày trước"
    }

    /// Đếm ngược tới một mốc: "2g 15p", "3 ngày 4h".
    static func countdown(to date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds <= 0 { return "đang diễn ra" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days) ngày \(hours)g" }
        if hours > 0 { return "\(hours)g \(minutes)p" }
        return "\(max(minutes, 1))p"
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM"
        return formatter.string(from: date)
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func dayTitle(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        let text: String
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "'Hôm nay ·' dd/MM"
            text = formatter.string(from: date)
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(date, inSameDayAs: tomorrow) {
            formatter.dateFormat = "'Ngày mai ·' dd/MM"
            text = formatter.string(from: date)
        } else {
            formatter.dateFormat = "EEEE · dd/MM"
            text = formatter.string(from: date)
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

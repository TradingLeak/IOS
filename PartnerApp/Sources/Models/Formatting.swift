import Foundation

/// Định dạng số/tiền/ngày theo tiếng Việt, dùng chung cho toàn app.
/// Tiền tệ từ API là chuỗi thập phân ("123.45") nên parse bằng Decimal
/// để tránh sai số dấu phẩy động.
enum Fmt {
    private static let displayLocale = Locale(identifier: "vi_VN")
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    private static let twoDigits = makeDecimalFormatter(fractionDigits: 2)
    private static let oneDigit = makeDecimalFormatter(fractionDigits: 1)
    private static let zeroDigits = makeDecimalFormatter(fractionDigits: 0)

    private static func makeDecimalFormatter(fractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = displayLocale
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.usesGroupingSeparator = true
        formatter.alwaysShowsDecimalSeparator = false
        return formatter
    }

    // MARK: - Số

    static func decimal(_ value: Double, fractionDigits: Int = 2) -> String {
        let formatter: NumberFormatter
        switch fractionDigits {
        case 0: formatter = zeroDigits
        case 1: formatter = oneDigit
        default: formatter = twoDigits
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func usd(_ value: Decimal) -> String {
        "$" + decimal(value.doubleValue)
    }

    static func usd(_ value: Double) -> String {
        "$" + decimal(value)
    }

    static func usd(_ raw: String?) -> String {
        guard let raw, let value = Decimal(apiString: raw) else { return "—" }
        return usd(value)
    }

    static func compactUSD(_ value: Double) -> String {
        let magnitude = Swift.abs(value)
        if magnitude >= 1_000_000 {
            return "$" + decimal(value / 1_000_000) + "M"
        }
        if magnitude >= 1_000 {
            return "$" + decimal(value / 1_000) + "K"
        }
        return "$" + decimal(value)
    }

    static func lots(_ value: Double) -> String {
        if Swift.abs(value) >= 1_000 {
            return decimal(value, fractionDigits: 1)
        }
        return decimal(value, fractionDigits: 2)
    }

    static func percent(_ value: Double) -> String {
        decimal(value) + "%"
    }

    // MARK: - Ngày giờ

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// API trả ngày dạng `yyyy-MM-dd` (đã là UTC) hoặc ISO-8601 có `Z`.
    private static let apiDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    private static let displayShortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.dateFormat = "dd/MM"
        return formatter
    }()

    private static let displayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func parseDate(_ raw: String) -> Date? {
        if let date = isoFractional.date(from: raw) { return date }
        if let date = isoPlain.date(from: raw) { return date }
        if let date = apiDayFormatter.date(from: raw) { return date }
        return nil
    }

    static func date(_ raw: String) -> String {
        guard let date = parseDate(raw) else { return raw }
        return displayDateFormatter.string(from: date)
    }

    static func shortDate(_ raw: String) -> String {
        guard let date = parseDate(raw) else { return raw }
        return displayShortDateFormatter.string(from: date)
    }

    /// Chỉ giờ (HH:mm) của một mốc thời gian API; rỗng nếu không parse được.
    static func time(_ raw: String) -> String {
        guard let date = parseDate(raw) else { return "" }
        return displayTimeFormatter.string(from: date)
    }

    static func dateTime(_ raw: String) -> String {
        guard let date = parseDate(raw) else { return raw }
        return displayTimeFormatter.string(from: date) + " · " + displayShortDateFormatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        displayTimeFormatter.string(from: date) + " · " + displayDateFormatter.string(from: date)
    }

    /// Chuỗi ngày gửi lên API, luôn theo UTC.
    static func apiDateString(_ date: Date) -> String {
        apiDayFormatter.string(from: date)
    }
}

extension Decimal {
    /// Parse chuỗi thập phân từ API ("123.45", "-0.5").
    init?(apiString: String) {
        self.init(string: apiString, locale: Locale(identifier: "en_US_POSIX"))
    }

    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

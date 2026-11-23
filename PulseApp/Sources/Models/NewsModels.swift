import Foundation
import SwiftUI

/// Nhóm nguồn tin. Nguồn mặc định đều là RSS công khai, không cần API key.
enum NewsCategory: String, Codable, CaseIterable, Identifiable {
    case forex, breaking, crypto, centralBank, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forex: return "Forex & Hàng hoá"
        case .breaking: return "Tin nhanh"
        case .crypto: return "Tiền mã hoá"
        case .centralBank: return "Ngân hàng trung ương"
        case .custom: return "Nguồn khác"
        }
    }

    var symbol: String {
        switch self {
        case .forex: return "chart.line.uptrend.xyaxis"
        case .breaking: return "bolt.fill"
        case .crypto: return "bitcoinsign.circle"
        case .centralBank: return "building.columns"
        case .custom: return "rss"
        }
    }

    var tint: Color {
        switch self {
        case .forex: return PulseTheme.teal
        case .breaking: return PulseTheme.warning
        case .crypto: return PulseTheme.violet
        case .centralBank: return PulseTheme.accent
        case .custom: return PulseTheme.info
        }
    }
}

struct NewsFeed: Codable, Identifiable, Hashable {
    let url: String
    let title: String
    let category: NewsCategory
    var id: String { url }
}

struct NewsItem: Codable, Identifiable, Hashable {
    let title: String
    let link: String
    let summary: String
    let date: Date?
    let source: String
    let category: NewsCategory
    var id: String { link }
}

enum NewsSources {
    static let builtIn: [NewsFeed] = [
        NewsFeed(url: "https://www.fxstreet.com/rss/news", title: "FXStreet", category: .forex),
        NewsFeed(url: "https://investinglive.com/feed/news", title: "InvestingLive", category: .breaking),
        NewsFeed(url: "https://www.coindesk.com/arc/outboundfeeds/rss/", title: "CoinDesk", category: .crypto),
        NewsFeed(url: "https://www.federalreserve.gov/feeds/press_all.xml", title: "Federal Reserve", category: .centralBank)
    ]

    static let disabledKey = "pulse.news.disabledCategories"
    static let customKey = "pulse.news.customFeeds"

    static func disabledCategories() -> Set<NewsCategory> {
        Set(UserDefaults.standard.stringArray(forKey: disabledKey) ?? [])
    }

    static func setDisabledCategories(_ set: Set<NewsCategory>) {
        UserDefaults.standard.set(Array(set.map(\.rawValue)).sorted(), forKey: disabledKey)
    }

    static func customFeeds() -> [NewsFeed] {
        guard let data = UserDefaults.standard.data(forKey: customKey) else { return [] }
        return (try? JSONDecoder().decode([NewsFeed].self, from: data)) ?? []
    }

    static func setCustomFeeds(_ feeds: [NewsFeed]) {
        if let data = try? JSONEncoder().encode(feeds) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
    }

    static func enabledFeeds() -> [NewsFeed] {
        let disabled = disabledCategories()
        return (builtIn + customFeeds()).filter { !disabled.contains($0.category) }
    }
}

// MARK: - RSS / Atom parser

/// Parser RSS 2.0 + Atom cơ bản, chỉ lấy title/link/pubDate/description.
final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [NewsItem] = []
    private var currentText = ""
    private var inItem = false
    private var itemTitle = ""
    private var itemLink = ""
    private var itemDescription = ""
    private var itemDate: Date?
    private var channelTitle = ""
    private let category: NewsCategory
    private let sourceHint: String

    private init(category: NewsCategory, sourceHint: String) {
        self.category = category
        self.sourceHint = sourceHint
    }

    static func parse(_ data: Data, category: NewsCategory, sourceHint: String) -> [NewsItem] {
        let delegate = RSSParser(category: category, sourceHint: sourceHint)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        if parser.parse() {
            return delegate.items
        }
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        let name = qualifiedName ?? elementName
        if name == "item" || name == "entry" {
            inItem = true
            itemTitle = ""
            itemLink = ""
            itemDescription = ""
            itemDate = nil
        }
        if inItem && name == "link", let href = attributeDict["href"], !href.isEmpty {
            itemLink = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let name = qualifiedName ?? elementName
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "item", "entry":
            let title = itemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !itemLink.isEmpty {
                items.append(NewsItem(title: HTMLText.plain(title),
                                      link: itemLink.trimmingCharacters(in: .whitespacesAndNewlines),
                                      summary: HTMLText.summary(itemDescription),
                                      date: itemDate,
                                      source: channelTitle.isEmpty ? sourceHint : channelTitle,
                                      category: category))
            }
            inItem = false
        case "title":
            if inItem { itemTitle = text } else if channelTitle.isEmpty { channelTitle = HTMLText.plain(text) }
        case "link":
            if inItem && itemLink.isEmpty { itemLink = text }
        case "description", "summary", "content":
            if inItem { itemDescription += text }
        case "pubDate", "published", "updated", "dc:date":
            if inItem { itemDate = FeedDate.parse(text) ?? itemDate }
        default:
            break
        }
        currentText = ""
    }
}

enum FeedDate {
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

    private static let rfc822: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private static let rfc822Short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    private static let rfc822NoZone: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss"
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if let date = isoFractional.date(from: text) { return date }
        if let date = isoPlain.date(from: text) { return date }
        if let date = rfc822.date(from: text) { return date }
        if let date = rfc822Short.date(from: text) { return date }
        if let date = rfc822NoZone.date(from: text) { return date }
        return nil
    }
}

enum HTMLText {
    /// Bỏ thẻ HTML, giải mã entity phổ biến, gộp khoảng trắng.
    static func plain(_ html: String) -> String {
        var text = html
        let pattern = "<[^>]+>"
        text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        text = decodeEntities(text)
        return collapse(text)
    }

    /// Tóm tắt ngắn (≤ 240 ký tự) cho card tin.
    static func summary(_ html: String) -> String {
        let text = plain(html)
        if text.count > 240 {
            let index = text.index(text.startIndex, offsetBy: 240)
            return String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return text
    }

    static func decodeEntities(_ text: String) -> String {
        var value = text
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#8217;", "'"), ("&#8216;", "'"), ("&#8220;", "\""), ("&#8221;", "\""),
            ("&#8211;", "-"), ("&#8212;", "—"), ("&#8230;", "…"), ("&#039;", "'"), ("&rsquo;", "'"),
            ("&ldquo;", "\""), ("&rdquo;", "\""), ("&hellip;", "…"), ("&mdash;", "—"), ("&ndash;", "-")
        ]
        for (entity, replacement) in entities {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value
    }

    static func collapse(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

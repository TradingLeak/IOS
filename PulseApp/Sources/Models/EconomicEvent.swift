import Foundation

/// Mức độ ảnh hưởng của sự kiện kinh tế (theo Forex Factory: Low/Medium/High/Holiday).
enum EventImpact: String, Codable, CaseIterable, Identifiable {
    case low, medium, high, holiday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: return "Cao"
        case .medium: return "Trung bình"
        case .low: return "Thấp"
        case .holiday: return "Nghỉ lễ"
        }
    }

    static func parse(_ raw: String) -> EventImpact {
        switch raw.lowercased() {
        case "high": return .high
        case "medium": return .medium
        case "holiday": return .holiday
        default: return .low
        }
    }
}

/// Bộ lọc mức ảnh hưởng hiển thị trong lịch.
enum ImpactFilter: String, Codable, CaseIterable, Identifiable {
    case all, mediumAndHigh, highOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Tất cả"
        case .mediumAndHigh: return "Trung bình + Cao"
        case .highOnly: return "Chỉ Cao"
        }
    }

    func includes(_ impact: EventImpact) -> Bool {
        switch self {
        case .all: return true
        case .mediumAndHigh: return impact == .medium || impact == .high
        case .highOnly: return impact == .high
        }
    }
}

struct EconomicEvent: Identifiable, Codable, Equatable, Hashable {
    var id: String
    let title: String
    let country: String
    let date: Date
    let impact: EventImpact
    let forecast: String
    let previous: String

    var isPast: Bool { date < Date() }
    var flag: String { PulseSymbol.flag(forCurrency: country) }
    var currencyName: String { country.uppercased() }

    /// Thời điểm cần báo trước sự kiện.
    func alertDate(minutesBefore: Int) -> Date {
        date.addingTimeInterval(-Double(minutesBefore) * 60)
    }
}

struct CalendarDay: Identifiable {
    let day: Date
    let events: [EconomicEvent]
    var id: Date { day }
}

/// Lịch kinh tế miễn phí (Forex Factory JSON, không cần API key) —
/// `https://nfs.faireconomy.media/ff_calendar_thisweek.json`.
enum EconomicCalendarService {
    static let thisWeekURL = URL(string: "https://nfs.faireconomy.media/ff_calendar_thisweek.json")!
    static let nextWeekURL = URL(string: "https://nfs.faireconomy.media/ff_calendar_nextweek.json")!
    static let cacheKey = "pulse.calendar.cache"

    private struct RawEvent: Decodable {
        let title: String
        let country: String
        let date: Date
        let impact: String
        let forecast: String?
        let previous: String?
    }

    private static let decoder: JSONDecoder = {
        let jsonDecoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        jsonDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = iso.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ngày không hợp lệ: \(raw)")
        }
        return jsonDecoder
    }()

    static func parse(_ data: Data) throws -> [EconomicEvent] {
        let raw = try decoder.decode([RawEvent].self, from: data)
        return raw.map { item in
            EconomicEvent(id: "\(item.country)|\(item.title)|\(Int(item.date.timeIntervalSince1970))",
                          title: item.title,
                          country: item.country.uppercased(),
                          date: item.date,
                          impact: EventImpact.parse(item.impact),
                          forecast: item.forecast ?? "",
                          previous: item.previous ?? "")
        }
    }

    /// Tải tuần này + tuần sau, gộp và loại trùng.
    static func fetch(session: URLSession = .shared) async throws -> [EconomicEvent] {
        var result: [EconomicEvent] = []
        var seen = Set<String>()
        for url in [thisWeekURL, nextWeekURL] {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                continue
            }
            for event in try parse(data) where !seen.contains(event.id) {
                seen.insert(event.id)
                result.append(event)
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Gom sự kiện theo ngày (giờ địa phương), ngày tăng dần.
    static func groupByDay(_ events: [EconomicEvent], calendar: Calendar = .current) -> [CalendarDay] {
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { CalendarDay(day: $0.key, events: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.day < $1.day }
    }

    static func loadCache() -> [EconomicEvent] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return [] }
        return (try? JSONDecoder().decode([EconomicEvent].self, from: data)) ?? []
    }

    static func saveCache(_ events: [EconomicEvent]) {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}

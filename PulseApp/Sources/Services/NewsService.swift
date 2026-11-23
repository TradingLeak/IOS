import Foundation

/// Tải tin tức từ nhiều nguồn RSS/Atom song song, gộp và sắp xếp mới nhất trước.
enum NewsService {
    static let cacheKey = "pulse.news.cache"
    static let maxItems = 300

    static func fetch(feeds: [NewsFeed], session: URLSession = .shared) async -> [NewsItem] {
        await withTaskGroup(of: [NewsItem].self) { group in
            for feed in feeds {
                group.addTask {
                    await fetchFeed(feed, session: session)
                }
            }
            var all: [NewsItem] = []
            for await items in group {
                all.append(contentsOf: items)
            }
            return merge(all)
        }
    }

    static func fetchFeed(_ feed: NewsFeed, session: URLSession) async -> [NewsItem] {
        guard let url = URL(string: feed.url) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
                         forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; PulseHub/1.0)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            return RSSParser.parse(data, category: feed.category, sourceHint: feed.title)
        } catch {
            return []
        }
    }

    /// Bỏ trùng link, sắp xếp mới nhất trước, giới hạn số lượng.
    static func merge(_ items: [NewsItem]) -> [NewsItem] {
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.link).inserted }
        let sorted = unique.sorted { first, second in
            let firstDate = first.date ?? .distantPast
            let secondDate = second.date ?? .distantPast
            if firstDate != secondDate { return firstDate > secondDate }
            return first.title < second.title
        }
        return Array(sorted.prefix(maxItems))
    }

    /// Tìm kiếm không phân biệt hoa thường trong tiêu đề và tóm tắt.
    static func search(_ items: [NewsItem], query: String) -> [NewsItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
            $0.summary.localizedCaseInsensitiveContains(trimmed)
        }
    }

    static func loadCache() -> [NewsItem] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return [] }
        return (try? JSONDecoder().decode([NewsItem].self, from: data)) ?? []
    }

    static func saveCache(_ items: [NewsItem]) {
        if let data = try? JSONEncoder().encode(Array(items.prefix(maxItems))) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}

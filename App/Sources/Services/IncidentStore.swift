import Foundation

/// Lưu báo cáo sự cố do người lái tạo — tệp JSON trong Documents, **không** ghi vào bundle
/// và không gửi lên máy chủ nào (app không có máy chủ).
enum IncidentStore {

    static let fileName = "user-incidents.json"
    /// Giữ tối đa 200 báo cáo gần nhất để tệp không phình ra.
    static let limit = 200

    static var url: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName)
    }

    static func load() -> [IncidentReport] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let reports = try? decoder.decode([IncidentReport].self, from: data) else { return [] }
        return reports.filter { !$0.isExpired }
    }

    @discardableResult
    static func save(_ reports: [IncidentReport]) -> [IncidentReport] {
        let alive = reports
            .filter { !$0.isExpired }
            .sorted { $0.createdAt > $1.createdAt }
        let trimmed = Array(alive.prefix(limit))
        guard let url else { return trimmed }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? encoder.encode(trimmed) {
            try? data.write(to: url, options: .atomic)
        }
        return trimmed
    }

    static func clear() {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

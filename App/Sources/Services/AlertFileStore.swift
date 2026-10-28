import Foundation

/// Lưu bộ cảnh báo do người dùng nhập (JSON) hoặc tải từ OpenStreetMap
/// vào thư mục Documents của app — không bao giờ ghi vào bundle.
enum AlertFileStore {

    static let importedFileName = "imported-alerts.json"

    static var directory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    static var importedURL: URL? {
        directory?.appendingPathComponent(importedFileName)
    }

    static func loadImported() -> [RoadAlert] {
        guard let url = importedURL,
              let data = try? Data(contentsOf: url),
              let dataset = try? AlertDatabase.decode(data) else { return [] }
        return dataset.alerts.filter(\.hasValidCoordinate)
    }

    static func saveImported(_ alerts: [RoadAlert]) throws {
        guard let url = importedURL else { return }
        let dataset = AlertDataset(version: "user",
                                   generatedAt: ISO8601DateFormatter().string(from: Date()),
                                   sources: [AlertSource(id: "user",
                                                         name: "Dữ liệu người dùng nhập / OpenStreetMap",
                                                         license: "Theo nguồn gốc")],
                                   alerts: alerts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(dataset)
        try data.write(to: url, options: .atomic)
    }

    static func clearImported() throws {
        guard let url = importedURL, FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Ghi bộ dữ liệu đầy đủ ra tệp tạm để chia sẻ (AirDrop, Files...).
    static func writeExport(alerts: [RoadAlert], sources: [AlertSource]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vietmap-alerts.json")
        let dataset = AlertDataset(schema: 2,
                                   version: "2.0.0",
                                   generatedAt: ISO8601DateFormatter().string(from: Date()),
                                   sources: sources,
                                   counts: nil,
                                   alerts: alerts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(dataset)
        try data.write(to: url, options: .atomic)
        return url
    }
}

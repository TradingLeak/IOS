import Foundation

struct OfflineMapManifest: Codable, Equatable {
    let schemaVersion: Int
    let countryCode: String
    let version: String
    let downloadURL: URL
    let byteCount: Int64
    let sha256: String
    let format: String
    /// west, south, east, north. Nhà xuất bản phải clip nội dung theo ranh giới VN.
    let bounds: [Double]
    let minZoom: Int
    let maxZoom: Int
    let attribution: String

    func validate() throws {
        guard schemaVersion == 1, countryCode == "VN", !version.isEmpty,
              version.count <= 100, byteCount > 0, byteCount <= 50_000_000_000,
              format == "png", sha256.count == 64,
              sha256.allSatisfy({ $0.isHexDigit && $0.isASCII }),
              (0...19).contains(minZoom), (minZoom...19).contains(maxZoom),
              Self.validVietnamBounds(bounds),
              !attribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.isDownloadURL(downloadURL) else {
            throw OfflineMapError.invalidManifest
        }
    }

    static func isDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              !host.isEmpty, url.user == nil, url.password == nil else { return false }
        // Tuyệt đối không dùng máy chủ tile công cộng OSM để tải vùng offline.
        return host != "openstreetmap.org" && !host.hasSuffix(".openstreetmap.org")
    }

    static func validVietnamBounds(_ bounds: [Double]) -> Bool {
        guard bounds.count == 4, bounds.allSatisfy(\.isFinite) else { return false }
        // Envelope kiểm tra sơ bộ, KHÔNG phải polygon ranh giới hành chính.
        return bounds[0] >= 102 && bounds[2] <= 118 && bounds[1] >= 6 && bounds[3] <= 24
            && bounds[0] < bounds[2] && bounds[1] < bounds[3]
    }
}

enum OfflineMapError: LocalizedError {
    case invalidManifest
    case invalidDatabase(String)
    case checksum
    case size
    case noSpace
    case network
    case missingTile

    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "Manifest không hợp lệ. Cần gói PNG MBTiles Việt Nam (VN), URL HTTPS và SHA-256."
        case .invalidDatabase(let reason): return "Gói bản đồ không hợp lệ: \(reason)"
        case .checksum: return "SHA-256 không khớp. Gói tải về chưa được cài."
        case .size: return "Dung lượng tải về không khớp manifest."
        case .noSpace: return "Không đủ dung lượng trống để tải và cài gói bản đồ."
        case .network: return "Không tải được dữ liệu. Kiểm tra mạng và nguồn tải."
        case .missingTile: return "Không có tile trong gói Việt Nam tại vị trí hoặc mức zoom này."
        }
    }
}

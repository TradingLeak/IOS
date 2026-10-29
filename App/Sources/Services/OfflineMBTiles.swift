import Foundation
import SQLite3
import CryptoKit
import CoreGraphics
import ImageIO

/// SQLite chỉ đọc, tất cả truy vấn tile tuần tự; không giữ cả MBTiles trong RAM.
final class OfflineMBTiles {
    let id = UUID()
    let manifest: OfflineMapManifest
    private let tileCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 16 * 1024 * 1024
        cache.countLimit = 128
        return cache
    }()
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "vietmap.osm.mbtiles", qos: .userInitiated)

    init(url: URL, manifest: OfflineMapManifest) throws {
        self.manifest = manifest
        try manifest.validate()
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            db = nil
            throw OfflineMapError.invalidDatabase("không mở được SQLite")
        }
        do {
            guard try metadata("format") == "png",
                  try metadata("country_code") == "VN",
                  try metadata("scheme") == "tms",
                  try metadata("minzoom") == String(manifest.minZoom),
                  try metadata("maxzoom") == String(manifest.maxZoom),
                  let rawBounds = try metadata("bounds") else {
                throw OfflineMapError.invalidDatabase("metadata phải có format=png, country_code=VN, scheme=tms và zoom đúng")
            }
            let parts = rawBounds.split(separator: ",", omittingEmptySubsequences: false)
            let bounds = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 4, bounds.count == 4, Self.sameBounds(bounds, manifest.bounds) else {
                throw OfflineMapError.invalidDatabase("bounds khác manifest")
            }
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, "SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles LIMIT 1", -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW,
                  Self.isPNG(Self.blob(statement, column: 3)) else {
                throw OfflineMapError.invalidDatabase("thiếu bảng tiles hoặc tile PNG")
            }
        } catch {
            if let db { sqlite3_close(db) }
            db = nil
            throw error
        }
    }

    deinit { if let db { sqlite3_close_v2(db) } }

    static func sameBounds(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        lhs.count == 4 && rhs.count == 4 && zip(lhs, rhs).allSatisfy { pair in abs(pair.0 - pair.1) < 0.000001 }
    }

    private func metadata(_ name: String) throws -> String? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        // Chỉ truyền tên khoá nội bộ, không có SQL từ manifest.
        guard sqlite3_prepare_v2(db, "SELECT value FROM metadata WHERE name = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK else {
            throw OfflineMapError.invalidDatabase("thiếu bảng metadata")
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, name, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }

    /// MapKit dùng XYZ gốc trên-trái; MBTiles TMS gốc dưới-trái.
    static func tmsRow(y: Int, z: Int) -> Int? {
        guard (0...19).contains(z), y >= 0, y < (1 << z) else { return nil }
        return (1 << z) - 1 - y
    }

    static func tileIntersectsBounds(x: Int, y: Int, z: Int, bounds: [Double]) -> Bool {
        guard bounds.count == 4, (0...19).contains(z),
              x >= 0, y >= 0, x < (1 << z), y < (1 << z) else { return false }
        let count = Double(1 << z)
        let west = Double(x) / count * 360 - 180
        let east = Double(x + 1) / count * 360 - 180
        let north = atan(sinh(.pi * (1 - 2 * Double(y) / count))) * 180 / .pi
        let south = atan(sinh(.pi * (1 - 2 * Double(y + 1) / count))) * 180 / .pi
        return east > bounds[0] && west < bounds[2] && north > bounds[1] && south < bounds[3]
    }

    /// Phóng ảnh tile gốc khi vượt native zoom; không tạo thêm chi tiết hoặc tải qua mạng.
    static func sourceTile(x: Int, y: Int, z: Int, maximumNativeZoom: Int)
        -> (x: Int, y: Int, z: Int, offsetX: Int, offsetY: Int, scale: Int)? {
        guard (0...19).contains(maximumNativeZoom), (0...19).contains(z),
              x >= 0, y >= 0, x < (1 << z), y < (1 << z) else { return nil }
        let shift = max(0, z - maximumNativeZoom)
        let scale = 1 << shift
        return (x / scale, y / scale, min(z, maximumNativeZoom), x % scale, y % scale, scale)
    }

    func tile(x: Int, y: Int, z: Int, completion: @escaping (Data?, Error?) -> Void) {
        guard z >= manifest.minZoom,
              let source = Self.sourceTile(x: x, y: y, z: z, maximumNativeZoom: manifest.maxZoom),
              let row = Self.tmsRow(y: source.y, z: source.z),
              Self.tileIntersectsBounds(x: x, y: y, z: z, bounds: manifest.bounds) else {
            completion(nil, OfflineMapError.missingTile)
            return
        }
        queue.async { [self] in
            let key = "\(z)/\(x)/\(y)" as NSString
            if let cached = tileCache.object(forKey: key) { completion(cached as Data, nil); return }
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ? LIMIT 1"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                completion(nil, OfflineMapError.invalidDatabase("không đọc được tile")); return
            }
            sqlite3_bind_int(statement, 1, Int32(source.z))
            sqlite3_bind_int(statement, 2, Int32(source.x))
            sqlite3_bind_int(statement, 3, Int32(row))
            guard sqlite3_step(statement) == SQLITE_ROW else {
                completion(nil, OfflineMapError.missingTile); return
            }
            let raw = Self.blob(statement, column: 0)
            guard Self.isPNG(raw) else {
                completion(nil, OfflineMapError.invalidDatabase("tile không phải PNG")); return
            }
            let data: Data
            if source.scale > 1 {
                guard let resized = Self.enlargePNG(raw, offsetX: source.offsetX, offsetY: source.offsetY, scale: source.scale) else {
                    completion(nil, OfflineMapError.invalidDatabase("không phóng được tile PNG")); return
                }
                data = resized
            } else { data = raw }
            tileCache.setObject(data as NSData, forKey: key, cost: data.count)
            completion(data, nil)
        }
    }

    private static func enlargePNG(_ data: Data, offsetX: Int, offsetY: Int, scale: Int) -> Data? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }
        let width = Double(image.width) / Double(scale)
        let height = Double(image.height) / Double(scale)
        guard let cropped = image.cropping(to: CGRect(x: Double(offsetX) * width, y: Double(offsetY) * height,
                                                      width: width, height: height)),
              let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8,
                                      bytesPerRow: 256 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 256, height: 256))
        guard let enlarged = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, enlarged, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func blob(_ statement: OpaquePointer?, column: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, count <= 16 * 1024 * 1024,
              let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    private static func isPNG(_ data: Data) -> Bool {
        data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
    }

    static func verifyFile(_ url: URL, manifest: OfflineMapManifest) throws {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard size?.int64Value == manifest.byteCount else { throw OfflineMapError.size }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hash.update(data: chunk)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == manifest.sha256.lowercased() else { throw OfflineMapError.checksum }
    }
}

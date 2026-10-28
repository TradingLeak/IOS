import Foundation
import CoreLocation

// MARK: - Lỗi

enum SpeedmapError: LocalizedError {
    case missingFile(String)
    case badMagic(file: String, found: String)
    case unsupportedVersion(Int)
    case sizeMismatch(file: String, expected: Int, actual: Int)
    case crcMismatch(file: String)
    case truncated(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let name):
            return "Thiếu file speedmap: \(name)"
        case .badMagic(let file, let found):
            return "Sai magic của \(file): \(found)"
        case .unsupportedVersion(let v):
            return "Phiên bản speedmap không được hỗ trợ: v\(v)"
        case .sizeMismatch(let file, let expected, let actual):
            return "Kích thước \(file) không khớp: cần \(expected) B, thực tế \(actual) B"
        case .crcMismatch(let file):
            return "CRC32 của \(file) không khớp metadata (dữ liệu hỏng)"
        case .truncated(let what):
            return "Dữ liệu speedmap bị cắt ngắn: \(what)"
        }
    }
}

// MARK: - ByteCursor đọc little-endian, có kiểm tra biên
//
// Mọi file speedmap đều được pack bằng Python `struct` với tiền tố `<`
// (little-endian, không padding) — xem VietHUD `src/map/SpeedMapFormat.h`.
// Đọc thủ công từng byte thay vì `load(as:)` để không phụ thuộc alignment
// của `Data` slice.

struct ByteCursor {
    private let buf: UnsafeRawBufferPointer
    private(set) var offset: Int

    init(_ buf: UnsafeRawBufferPointer, at offset: Int = 0) {
        self.buf = buf
        self.offset = offset
    }

    var remaining: Int { buf.count - offset }

    mutating func take(_ n: Int) throws -> UnsafeRawBufferPointer {
        guard n >= 0, offset + n <= buf.count else {
            throw SpeedmapError.truncated("cần \(n) B tại offset \(offset), còn \(remaining)")
        }
        defer { offset += n }
        guard n > 0 else { return UnsafeRawBufferPointer(start: nil, count: 0) }
        guard let base = buf.baseAddress else {
            throw SpeedmapError.truncated("buffer rỗng")
        }
        return UnsafeRawBufferPointer(start: base.advanced(by: offset), count: n)
    }

    mutating func bytes(_ n: Int) throws -> Data {
        let s = try take(n)
        guard let base = s.baseAddress else { return Data() }
        return Data(bytes: base, count: s.count)
    }

    /// Chuỗi cố định (đệm NUL) — region, mapVersion, attribution…
    mutating func fixedString(_ n: Int) throws -> String {
        let raw = try bytes(n)
        let cut = raw.firstIndex(of: 0) ?? raw.endIndex
        return String(decoding: raw[..<cut], as: UTF8.self)
    }

    mutating func u8() throws -> UInt8 {
        let s = try take(1)
        return s[0]
    }

    mutating func u16() throws -> UInt16 {
        let s = try take(2)
        return UInt16(s[0]) | (UInt16(s[1]) << 8)
    }

    mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }

    mutating func u32() throws -> UInt32 {
        let s = try take(4)
        return UInt32(s[0]) | (UInt32(s[1]) << 8) | (UInt32(s[2]) << 16) | (UInt32(s[3]) << 24)
    }

    mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }

    mutating func u64() throws -> UInt64 {
        let lo = UInt64(try u32())
        let hi = UInt64(try u32())
        return lo | (hi << 32)
    }

    mutating func f32() throws -> Float { Float(bitPattern: try u32()) }
}

// MARK: - CRC32 (chuẩn IEEE, dùng cho index.bin)

enum SpeedmapCRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func compute(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - metadata.bin

struct SpeedmapMetadata {
    static let encodedSize = 140

    let formatVersion: Int
    let region: String
    let mapVersion: String
    let buildTimestamp: Date
    let tileCount: Int
    let segmentCount: Int
    let tileSizeDeg: Double
    let testCoordinate: CLLocationCoordinate2D?
    let testHeadingDeg: Int
    let testRoadId: UInt32
    let attribution: String
    let indexCRC32: UInt32
}

// MARK: - index.bin

/// 28 B — một dòng trong `TileIndexEntry[]`, sắp xếp tăng dần theo tileId.
struct TileIndexEntry {
    static let encodedSize = 28

    let tileId: UInt32
    let minLatE7: Int32
    let maxLatE7: Int32
    let minLonE7: Int32
    let maxLonE7: Int32
    let fileOffset: UInt32
    let fileSize: UInt32

    var minLat: Double { Double(minLatE7) / 1e7 }
    var maxLat: Double { Double(maxLatE7) / 1e7 }
    var minLon: Double { Double(minLonE7) / 1e7 }
    var maxLon: Double { Double(maxLonE7) / 1e7 }

    func intersects(_ box: SpeedmapBBox) -> Bool {
        !(box.maxLat < minLat || box.minLat > maxLat
            || box.maxLon < minLon || box.minLon > maxLon)
    }

    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        c.latitude >= minLat && c.latitude <= maxLat
            && c.longitude >= minLon && c.longitude <= maxLon
    }
}

/// BBox dùng nội bộ cho truy vấn (đơn vị độ).
struct SpeedmapBBox {
    var minLat: Double
    var maxLat: Double
    var minLon: Double
    var maxLon: Double

    init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }

    /// Mở rộng theo bán kính mét (xấp xỉ, đủ cho quét tile).
    func expanded(meters: Double) -> SpeedmapBBox {
        let dLat = meters / 110_540.0
        let midLat = (minLat + maxLat) / 2
        let dLon = meters / (111_320.0 * max(cos(midLat * .pi / 180), 0.05))
        return SpeedmapBBox(minLat: minLat - dLat, maxLat: maxLat + dLat,
                            minLon: minLon - dLon, maxLon: maxLon + dLon)
    }
}

// MARK: - tiles.bin

enum RoadDirection: UInt8 {
    case bidirectional = 0
    case forward = 1
    case backward = 2
    case unknown = 3
}

/// Bit flags của RoadSegment.flags
enum SegmentFlag {
    static let conditional: UInt8 = 0x01
    static let oneway: UInt8 = 0x02
    static let bridge: UInt8 = 0x04
    static let tunnel: UInt8 = 0x08
    static let link: UInt8 = 0x10
    static let noVehicle: UInt8 = 0x20
}

/// 28 B — một đoạn đường thẳng giữa 2 node OSM liền kề.
struct RoadSegment {
    static let encodedSize = 28

    let id: UInt32
    let startLatE7: Int32
    let startLonE7: Int32
    let endLatE7: Int32
    let endLonE7: Int32
    let headingDeg: UInt16
    let roadClass: UInt8
    let direction: RoadDirection
    let speedLimitKmh: Int16
    let speedSource: UInt8
    let flags: UInt8

    var start: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: Double(startLatE7) / 1e7,
                               longitude: Double(startLonE7) / 1e7)
    }

    var end: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: Double(endLatE7) / 1e7,
                               longitude: Double(endLonE7) / 1e7)
    }

    var isOneway: Bool { flags & SegmentFlag.oneway != 0 }
    var isVehicleRoad: Bool { flags & SegmentFlag.noVehicle == 0 }
    /// -1 = không rõ giới hạn
    var hasSpeedLimit: Bool { speedLimitKmh > 0 }

    /// Heading cho chiều đang đi (forward = heading gốc, backward = +180°).
    func heading(for direction: RoadDirection) -> Double {
        switch direction {
        case .backward: return Double((headingDeg + 180) % 360)
        default: return Double(headingDeg)
        }
    }
}

// MARK: - cameras.bin

/// 20 B — phẳng, không header (nạp cả file vào RAM).
struct CameraPoint {
    static let encodedSize = 20

    let osmId: UInt64
    let latE7: Int32
    let lonE7: Int32
    let speedLimitKmh: Int16   // -1 = không gắn nhãn → lấy limit của đoạn đường
    let directionDeg: UInt16   // 0xFFFF = hai chiều

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: Double(latE7) / 1e7,
                               longitude: Double(lonE7) / 1e7)
    }

    var isOmnidirectional: Bool { directionDeg == 0xFFFF }
}

// MARK: - signs.bin (VNSG)

enum TrafficSignType: UInt8 {
    case unknown = 0
    case speedLimit = 1        // P.127
    case residentArea = 2      // R.420/R.421
    case noOvertaking = 3      // P.125/DP.133
    case camera = 4            // trùng lặp với cameras.bin → bỏ khi load
    case tollBooth = 5         // P.135
    case trafficLight = 6
    case dangerOther = 10
}

/// 20 B header.
struct TrafficSignHeader {
    static let encodedSize = 20
    static let magic = "VNSG"

    let version: Int
    let signCount: Int
    let crc32: UInt32
    let timestamp: Date
}

/// 20 B — một điểm cảnh báo.
struct TrafficSign: Identifiable {
    static let encodedSize = 20

    let id: UInt32
    let latE7: Int32
    let lonE7: Int32
    let directionDeg: UInt16
    let signType: UInt8
    let speedLimitKmh: UInt8
    let subType: UInt8         // 0 = bắt đầu/có hiệu lực, 1 = kết thúc
    let flags: UInt8

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: Double(latE7) / 1e7,
                               longitude: Double(lonE7) / 1e7)
    }

    var isOmnidirectional: Bool { directionDeg == 0xFFFF }
    var type: TrafficSignType { TrafficSignType(rawValue: signType) ?? .unknown }
    var isEndOfRestriction: Bool { subType == 1 }
}

// MARK: - names.bin (VNNM) + seg_names.bin

/// 16 B header V2 (nameCount là u32 — bản toàn quốc).
struct RoadNamesHeader {
    static let encodedSize = 16
    static let magic = "VNNM"

    let version: Int
    let nameCount: Int
    let poolBytes: Int
}

// MARK: - Toạ độ E7 → Double

func e7(_ value: Int32) -> Double { Double(value) / 1e7 }

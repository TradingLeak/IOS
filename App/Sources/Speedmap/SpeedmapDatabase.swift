import Foundation
import CoreLocation

// MARK: - Kết quả map-matching

/// Đường xe đang đi (từ speedmap), kèm khoảng cách tới điểm GPS và tên phố.
struct RoadMatch: Equatable {
    let segment: RoadSegment
    let distanceM: Double
    let name: String?

    static func == (lhs: RoadMatch, rhs: RoadMatch) -> Bool {
        lhs.segment.id == rhs.segment.id
            && abs(lhs.distanceM - rhs.distanceM) < 0.01
            && lhs.name == rhs.name
    }
}

// MARK: - SpeedmapDatabase
//
// Nạp + tra cứu 7 file `speedmap/*.bin` (format VietHUD — xem
// `SpeedMapFormat.h` trong repo 911273/VietHUD và docs/NAV-PRO-DESIGN.md §4).
// Mọi số đều little-endian, pack(1), tọa độ Int32 (độ × 1e7).
//
// Bộ nhớ: index (3.437×28B) + signs (100.917×20B ≈ 2MB) + names pool (141KB)
// + seg_ids (729KB) + tiles Data (5MB) + LRU tile cache — tổng ≈ 12MB, ổn định
// suốt đời app, không phát sinh khi đang lái.

final class SpeedmapDatabase {
    // MARK: Nạp

    let metadata: SpeedmapMetadata
    /// Thư mục các file được nạp từ đó (chẩn đoán hiển thị trong Settings).
    let sourceDirectory: URL
    private let index: [TileIndexEntry]
    private let tilesData: Data
    private let cameras: [CameraPoint]
    private let signs: [TrafficSign]        // đã sort theo latE7 tăng dần
    private let nameOffsets: [UInt32]
    private let namePool: Data
    private let segNameIds: [UInt32]        // index = segId (1-based), [0] không dùng

    private var tileCache: [UInt32: [RoadSegment]] = [:]
    private let tileCacheLimit = 256

    private init(metadata: SpeedmapMetadata,
                 sourceDirectory: URL,
                 index: [TileIndexEntry],
                 tilesData: Data,
                 cameras: [CameraPoint],
                 signs: [TrafficSign],
                 nameOffsets: [UInt32],
                 namePool: Data,
                 segNameIds: [UInt32]) {
        self.metadata = metadata
        self.sourceDirectory = sourceDirectory
        self.index = index
        self.tilesData = tilesData
        self.cameras = cameras
        self.signs = signs
        self.nameOffsets = nameOffsets
        self.namePool = namePool
        self.segNameIds = segNameIds
    }

    /// Tìm thư mục chứa speedmap trong bundle (xcodegen có thể phẳng hoá
    /// resource về gốc bundle — thử cả hai, sau đó quét *.bin còn lại).
    static func defaultDirectory(bundle: Bundle = .main) -> URL? {
        if let url = bundle.url(forResource: "metadata", withExtension: "bin", subdirectory: "speedmap") {
            return url.deletingLastPathComponent()
        }
        if let url = bundle.url(forResource: "metadata", withExtension: "bin") {
            return url.deletingLastPathComponent()
        }
        // Fallback: bất kỳ *.bin nào trong bundle (layout lạ vẫn nạp được).
        if let all = bundle.urls(forResourcesWithExtension: "bin", subdirectory: nil),
           let first = all.first(where: { $0.lastPathComponent == "metadata.bin" }) ?? all.first {
            return first.deletingLastPathComponent()
        }
        return nil
    }

    static func load(directory: URL) throws -> SpeedmapDatabase {
        let metadata = try loadMetadata(at: directory.appendingPathComponent("metadata.bin"))
        let indexData = try read(directory, "index.bin")

        // CRC32 của index.bin phải khớp metadata (0 = bỏ qua, cho fixture test)
        if metadata.indexCRC32 != 0, SpeedmapCRC32.compute(indexData) != metadata.indexCRC32 {
            throw SpeedmapError.crcMismatch(file: "index.bin")
        }
        let expectedIndex = metadata.tileCount * TileIndexEntry.encodedSize
        guard indexData.count == expectedIndex else {
            throw SpeedmapError.sizeMismatch(file: "index.bin", expected: expectedIndex, actual: indexData.count)
        }
        let index = try parseIndex(indexData, expectedCount: metadata.tileCount)

        let tilesData = try read(directory, "tiles.bin")
        let expectedTiles = index.reduce(0) { $0 + Int($1.fileSize) }
        guard tilesData.count == expectedTiles else {
            throw SpeedmapError.sizeMismatch(file: "tiles.bin", expected: expectedTiles, actual: tilesData.count)
        }

        // cameras.bin / signs.bin là phần tăng cường: thiếu vẫn tải được (khớp firmware).
        let cameras = try loadCameras(at: directory.appendingPathComponent("cameras.bin"))
        let signs = try loadSigns(at: directory.appendingPathComponent("signs.bin"))

        let (nameOffsets, namePool) = try loadNames(at: directory.appendingPathComponent("names.bin"))
        let segNameIds = try loadSegNames(at: directory.appendingPathComponent("seg_names.bin"),
                                          minimumCount: metadata.segmentCount + 1)

        return SpeedmapDatabase(metadata: metadata,
                                sourceDirectory: directory,
                                index: index,
                                tilesData: tilesData,
                                cameras: cameras,
                                signs: signs,
                                nameOffsets: nameOffsets,
                                namePool: namePool,
                                segNameIds: segNameIds)
    }

    // MARK: - Loaders riêng lẻ

    private static func read(_ dir: URL, _ name: String) throws -> Data {
        let url = dir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw SpeedmapError.missingFile(name)
        }
        return data
    }

    private static func loadMetadata(at url: URL) throws -> SpeedmapMetadata {
        guard let data = try? Data(contentsOf: url) else {
            throw SpeedmapError.missingFile("metadata.bin")
        }
        return try data.withUnsafeBytes { raw -> SpeedmapMetadata in
            var c = ByteCursor(raw)
            guard let magic = try? c.fixedString(4), magic == "SLMP" else {
                throw SpeedmapError.badMagic(file: "metadata.bin", found: String(decoding: data.prefix(4), as: UTF8.self))
            }
            let version = Int(try c.u16())
            guard version == 2 else { throw SpeedmapError.unsupportedVersion(version) }
            let region = try c.fixedString(16)
            let mapVersion = try c.fixedString(16)
            let ts = TimeInterval(try c.u64())
            let tileCount = Int(try c.u32())
            let segmentCount = Int(try c.u32())
            let tileSize = Double(try c.f32())
            let testLat = try c.i32()
            let testLon = try c.i32()
            let testHeading = Int(try c.i16())
            let testRoadId = try c.u32()
            let attribution = try c.fixedString(64)
            let crc = try c.u32()

            let testCoord = testRoadId == 0
                ? nil
                : CLLocationCoordinate2D(latitude: e7(testLat), longitude: e7(testLon))
            return SpeedmapMetadata(formatVersion: version,
                                    region: region,
                                    mapVersion: mapVersion,
                                    buildTimestamp: Date(timeIntervalSince1970: ts),
                                    tileCount: tileCount,
                                    segmentCount: segmentCount,
                                    tileSizeDeg: tileSize,
                                    testCoordinate: testCoord,
                                    testHeadingDeg: testHeading,
                                    testRoadId: testRoadId,
                                    attribution: attribution,
                                    indexCRC32: crc)
        }
    }

    private static func parseIndex(_ data: Data, expectedCount: Int) throws -> [TileIndexEntry] {
        try data.withUnsafeBytes { raw -> [TileIndexEntry] in
            var c = ByteCursor(raw)
            var entries: [TileIndexEntry] = []
            entries.reserveCapacity(expectedCount)
            for _ in 0..<expectedCount {
                entries.append(TileIndexEntry(tileId: try c.u32(),
                                              minLatE7: try c.i32(),
                                              maxLatE7: try c.i32(),
                                              minLonE7: try c.i32(),
                                              maxLonE7: try c.i32(),
                                              fileOffset: try c.u32(),
                                              fileSize: try c.u32()))
            }
            return entries
        }
    }

    private static func loadCameras(at url: URL) throws -> [CameraPoint] {
        guard let data = try? Data(contentsOf: url) else { return [] }  // file tăng cường
        guard data.count % CameraPoint.encodedSize == 0 else {
            throw SpeedmapError.sizeMismatch(file: "cameras.bin",
                                             expected: data.count / CameraPoint.encodedSize * CameraPoint.encodedSize,
                                             actual: data.count)
        }
        return try data.withUnsafeBytes { raw -> [CameraPoint] in
            var c = ByteCursor(raw)
            var out: [CameraPoint] = []
            out.reserveCapacity(data.count / CameraPoint.encodedSize)
            while c.remaining >= CameraPoint.encodedSize {
                let osmId = try c.u64()
                let lat = try c.i32()
                let lon = try c.i32()
                let limit = try c.i16()
                let dir = try c.u16()
                // Limit ngoài khoảng hợp lệ → coi như không rõ (như firmware).
                let validLimit: Int16 = (limit >= 5 && limit <= 130) ? limit : -1
                out.append(CameraPoint(osmId: osmId, latE7: lat, lonE7: lon,
                                       speedLimitKmh: validLimit, directionDeg: dir))
            }
            return out
        }
    }

    private static func loadSigns(at url: URL) throws -> [TrafficSign] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard data.count >= TrafficSignHeader.encodedSize else {
            throw SpeedmapError.truncated("signs.bin < 20 B")
        }
        let signs: [TrafficSign] = try data.withUnsafeBytes { raw in
            var c = ByteCursor(raw)
            guard try c.fixedString(4) == TrafficSignHeader.magic else {
                throw SpeedmapError.badMagic(file: "signs.bin", found: "?")
            }
            let version = Int(try c.u16())
            guard version == 1 else { throw SpeedmapError.unsupportedVersion(version) }
            let count = Int(try c.u32())
            _ = try c.u16()          // reserved
            _ = try c.u32()          // crc32 (firmware cũng không verify mục này khi load)
            _ = try c.u32()          // timestamp

            let expected = TrafficSignHeader.encodedSize + count * TrafficSign.encodedSize
            guard data.count == expected else {
                throw SpeedmapError.sizeMismatch(file: "signs.bin", expected: expected, actual: data.count)
            }
            var out: [TrafficSign] = []
            out.reserveCapacity(count)
            for _ in 0..<count {
                let id = try c.u32()
                let lat = try c.i32()
                let lon = try c.i32()
                let dir = try c.u16()
                let type = try c.u8()
                let limit = try c.u8()
                let sub = try c.u8()
                let flags = try c.u8()
                _ = try c.u16()      // reserved
                // Dòng type=4 (camera) trùng lặp cameras.bin → loại bỏ ngay lúc load.
                if type != TrafficSignType.camera.rawValue {
                    out.append(TrafficSign(id: id, latE7: lat, lonE7: lon, directionDeg: dir,
                                           signType: type, speedLimitKmh: limit, subType: sub,
                                           flags: flags))
                }
            }
            return out
        }
        // Sort theo vĩ độ để truy vấn dải (band) về sau là binary search.
        return signs.sorted { $0.latE7 < $1.latE7 }
    }

    private static func loadNames(at url: URL) throws -> (offsets: [UInt32], pool: Data) {
        guard let data = try? Data(contentsOf: url) else {
            throw SpeedmapError.missingFile("names.bin")
        }
        return try data.withUnsafeBytes { raw -> (offsets: [UInt32], pool: Data) in
            var c = ByteCursor(raw)
            guard try c.fixedString(4) == RoadNamesHeader.magic else {
                throw SpeedmapError.badMagic(file: "names.bin", found: "?")
            }
            let version = Int(try c.u16())
            guard version == 1 || version == 2 else {
                throw SpeedmapError.unsupportedVersion(version)
            }
            let count: Int
            let poolBytes: Int
            if version == 2 {
                count = Int(try c.u32())
                poolBytes = Int(try c.u32())
                _ = try c.u16()   // reserved
            } else {
                count = Int(try c.u16())
                poolBytes = Int(try c.u32())
                _ = try c.u32()   // reserved
            }
            let expected = RoadNamesHeader.encodedSize + count * 4 + poolBytes
            guard data.count == expected else {
                throw SpeedmapError.sizeMismatch(file: "names.bin", expected: expected, actual: data.count)
            }
            var offsets: [UInt32] = []
            offsets.reserveCapacity(count)
            for _ in 0..<count {
                offsets.append(try c.u32())
            }
            let pool = try c.bytes(poolBytes)
            return (offsets, pool)
        }
    }

    private static func loadSegNames(at url: URL, minimumCount: Int) throws -> [UInt32] {
        guard let data = try? Data(contentsOf: url) else {
            throw SpeedmapError.missingFile("seg_names.bin")
        }
        guard data.count % 4 == 0 else {
            throw SpeedmapError.sizeMismatch(file: "seg_names.bin",
                                             expected: data.count / 4 * 4, actual: data.count)
        }
        let count = data.count / 4
        guard count >= minimumCount else {
            throw SpeedmapError.sizeMismatch(file: "seg_names.bin", expected: minimumCount * 4, actual: data.count)
        }
        return try data.withUnsafeBytes { raw -> [UInt32] in
            var c = ByteCursor(raw)
            var out: [UInt32] = []
            out.reserveCapacity(count)
            for _ in 0..<count {
                out.append(try c.u32())
            }
            return out
        }
    }

    // MARK: - Tiles

    private func segments(in entry: TileIndexEntry) throws -> [RoadSegment] {
        if let cached = tileCache[entry.tileId] { return cached }
        let off = Int(entry.fileOffset)
        let size = Int(entry.fileSize)
        guard off >= 0, size >= 0, off + size <= tilesData.count,
              size % RoadSegment.encodedSize == 0 else {
            throw SpeedmapError.truncated("tile \(entry.tileId) vượt tiles.bin")
        }
        let slice = tilesData.subdata(in: off..<(off + size))
        let parsed: [RoadSegment] = try slice.withUnsafeBytes { raw in
            var c = ByteCursor(raw)
            var out: [RoadSegment] = []
            out.reserveCapacity(size / RoadSegment.encodedSize)
            while c.remaining >= RoadSegment.encodedSize {
                out.append(RoadSegment(id: try c.u32(),
                                       startLatE7: try c.i32(),
                                       startLonE7: try c.i32(),
                                       endLatE7: try c.i32(),
                                       endLonE7: try c.i32(),
                                       headingDeg: try c.u16(),
                                       roadClass: try c.u8(),
                                       direction: RoadDirection(rawValue: try c.u8()) ?? .unknown,
                                       speedLimitKmh: try c.i16(),
                                       speedSource: try c.u8(),
                                       flags: try c.u8()))
            }
            return out
        }
        if tileCache.count >= tileCacheLimit {
            // Đơn giản: bỏ toàn bộ (re-parse tile gần như tức thì ~1.5KB).
            tileCache.removeAll(keepingCapacity: true)
        }
        tileCache[entry.tileId] = parsed
        return parsed
    }

    /// Các tile giao với bbox (mở rộng theo bán kính).
    func tileEntries(near coordinate: CLLocationCoordinate2D, radiusM: Double) -> [TileIndexEntry] {
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let dLat = radiusM / 110_540.0
        let dLon = radiusM / (111_320.0 * max(cos(lat * .pi / 180), 0.05))
        let box = SpeedmapBBox(minLat: lat - dLat, maxLat: lat + dLat,
                               minLon: lon - dLon, maxLon: lon + dLon)
        return index.filter { $0.intersects(box) }
    }

    /// Mọi đoạn đường trong bán kính quanh điểm (dùng cho vẽ nền / kiểm thử).
    func segments(near coordinate: CLLocationCoordinate2D, radiusM: Double) -> [RoadSegment] {
        var out: [RoadSegment] = []
        for entry in tileEntries(near: coordinate, radiusM: radiusM) {
            guard let tile = try? segments(in: entry) else { continue }
            for seg in tile {
                let d = SpeedmapMath.pointToSegmentM(coordinate, seg.start, seg.end)
                if d <= radiusM { out.append(seg) }
            }
        }
        return out
    }

    // MARK: - Map-matching

    /// Tìm đoạn đường gần nhất + hợp lý với heading hiện tại.
    /// - Parameters:
    ///   - headingDeg: course của GPS (nil nếu không tin cậy — đi bộ/đứng yên)
    ///   - previousSegmentId: segment đã match lần trước (hysteresis ±4m)
    func matchRoad(at coordinate: CLLocationCoordinate2D,
                   headingDeg: Double?,
                   previousSegmentId: UInt32? = nil,
                   searchRadiusM: Double = 40) -> RoadMatch? {
        var best: (segment: RoadSegment, distance: Double, score: Double)?
        var previous: (segment: RoadSegment, distance: Double, score: Double)?

        for entry in tileEntries(near: coordinate, radiusM: searchRadiusM) {
            guard let tile = try? segments(in: entry) else { continue }
            for seg in tile {
                let distance = SpeedmapMath.pointToSegmentM(coordinate, seg.start, seg.end)
                guard distance <= searchRadiusM else { continue }

                var score = distance
                if let heading = headingDeg {
                    let error = headingError(for: seg, course: heading)
                    // Một chiều mà đang đi ngược > 90° → loại thẳng.
                    if seg.isOneway && error > 90 { continue }
                    score += min(error, 90) * 0.35
                }

                let candidate = (segment: seg, distance: distance, score: score)
                if seg.id == previousSegmentId {
                    if previous == nil || candidate.score < previous!.score { previous = candidate }
                }
                if best == nil || candidate.score < best!.score { best = candidate }
            }
        }

        // Hysteresis: giữ đường cũ nếu không thua quá 4m — tránh nhảy số giữa
        // 2 đường song song khi GPS nhiễu.
        if let previous, let best, previous.score <= best.score + 4 {
            return RoadMatch(segment: previous.segment, distanceM: previous.distance,
                             name: roadName(segmentId: previous.segment.id))
        }
        guard let best else { return nil }
        return RoadMatch(segment: best.segment, distanceM: best.distance,
                         name: roadName(segmentId: best.segment.id))
    }

    /// Sai số heading (0–180) với hướng hợp lệ của segment.
    func headingError(for seg: RoadSegment, course: Double) -> Double {
        switch seg.direction {
        case .forward:
            return SpeedmapMath.angularDiff(course, Double(seg.headingDeg))
        case .backward:
            return SpeedmapMath.angularDiff(course, Double((seg.headingDeg + 180) % 360))
        case .bidirectional, .unknown:
            let f = SpeedmapMath.angularDiff(course, Double(seg.headingDeg))
            let b = SpeedmapMath.angularDiff(course, Double((seg.headingDeg + 180) % 360))
            return min(f, b)
        }
    }

    // MARK: - Tên đường

    /// Tên phố của đoạn (seg_names → names), nil nếu không có / id ngoài bảng.
    func roadName(segmentId: UInt32) -> String? {
        guard segmentId > 0, Int(segmentId) < segNameIds.count else { return nil }
        let nameId = segNameIds[Int(segmentId)]
        guard nameId > 0, Int(nameId) <= nameOffsets.count else { return nil }
        let start = Int(nameOffsets[Int(nameId) - 1])
        guard start < namePool.count else { return nil }
        let tail = namePool[start...]
        guard let end = tail.firstIndex(of: 0) else { return nil }
        let bytes = namePool[start..<end]
        guard !bytes.isEmpty else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Cameras & Signs (truy vấn dải)

    /// Camera trong bán kính — quét mảng nhỏ (7.753 phần tử) với early-reject toạ độ.
    func cameras(near coordinate: CLLocationCoordinate2D, radiusM: Double) -> [CameraPoint] {
        guard !cameras.isEmpty else { return [] }
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let dLat = radiusM / 110_540.0 + 0.0005
        let dLon = radiusM / (111_320.0 * max(cos(lat * .pi / 180), 0.05)) + 0.0005
        var out: [CameraPoint] = []
        for cam in cameras {
            let cLat = Double(cam.latE7) / 1e7
            let cLon = Double(cam.lonE7) / 1e7
            guard abs(cLat - lat) <= dLat, abs(cLon - lon) <= dLon else { continue }
            if SpeedmapMath.meters(coordinate, cam.coordinate) <= radiusM {
                out.append(cam)
            }
        }
        return out
    }

    /// Biển báo trong bán kính — signs đã sort theo latE7 → binary search dải.
    func signs(near coordinate: CLLocationCoordinate2D, radiusM: Double) -> [TrafficSign] {
        guard !signs.isEmpty else { return [] }
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let dLatE7 = Int32((radiusM / 110_540.0 * 1e7).rounded()) + 100
        let dLonE7 = Int32((radiusM / (111_320.0 * max(cos(lat * .pi / 180), 0.05)) * 1e7).rounded()) + 100
        let latE7 = Int32((lat * 1e7).rounded())
        let lonE7 = Int32((lon * 1e7).rounded())
        let low = latE7 - dLatE7
        let high = latE7 + dLatE7

        // Binary search biên dưới (latE7 >= low)
        var lo = 0, hi = signs.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if signs[mid].latE7 < low { lo = mid + 1 } else { hi = mid }
        }
        var out: [TrafficSign] = []
        var i = lo
        while i < signs.count, signs[i].latE7 <= high {
            let sign = signs[i]
            if abs(sign.lonE7 - lonE7) <= dLonE7,
               SpeedmapMath.meters(coordinate, sign.coordinate) <= radiusM {
                out.append(sign)
            }
            i += 1
        }
        return out
    }
}

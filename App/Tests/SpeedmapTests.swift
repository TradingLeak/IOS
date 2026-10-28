import XCTest
import CoreLocation
import MapKit
@testable import VietMap

// MARK: - Fixture: tự build 7 file speedmap tổng hợp (little-endian, pack(1))

private final class ByteWriter {
    var data = Data()

    func u8(_ v: UInt8) { data.append(v) }
    func u16(_ v: UInt16) {
        data.append(UInt8(v & 0xFF))
        data.append(UInt8((v >> 8) & 0xFF))
    }
    func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    func u32(_ v: UInt32) {
        u8(UInt8(v & 0xFF))
        u8(UInt8((v >> 8) & 0xFF))
        u8(UInt8((v >> 16) & 0xFF))
        u8(UInt8((v >> 24) & 0xFF))
    }
    func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
    func u64(_ v: UInt64) {
        u32(UInt32(v & 0xFFFF_FFFF))
        u32(UInt32(v >> 32))
    }
    func f32(_ v: Float) { u32(v.bitPattern) }
    func fixed(_ s: String, _ n: Int) {
        var bytes = Array(s.utf8)
        if bytes.count > n { bytes = Array(bytes.prefix(n)) }
        bytes.append(contentsOf: Array(repeating: 0, count: n - bytes.count))
        data.append(contentsOf: bytes)
    }
}

enum SpeedmapFixture {
    // Geo — đường dọc qua (21.0000 → 21.0040), lon 105.8000:
    //   seg1 (id 1, limit 60, bắc tiến) 21.0000 → 21.0020
    //   seg2 (id 2, limit 40, bắc tiến) 21.0020 → 21.0040
    //   seg3 (id 3, limit 60, nam tiến) 21.0020 → 21.0000
    static func e7(_ deg: Double) -> Int32 { Int32((deg * 1e7).rounded()) }

    static func make() throws -> (dir: URL, database: SpeedmapDatabase) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("speedmap-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // ── index.bin ─────────────────────────────────────────────
        let indexWriter = ByteWriter()
        indexWriter.u32(1)                       // tileId
        indexWriter.i32(e7(20.99))               // minLat
        indexWriter.i32(e7(21.02))               // maxLat
        indexWriter.i32(e7(105.78))              // minLon
        indexWriter.i32(e7(105.82))              // maxLon
        indexWriter.u32(0)                       // fileOffset
        indexWriter.u32(28 * 3)                  // fileSize
        let indexData = indexWriter.data
        try indexData.write(to: dir.appendingPathComponent("index.bin"))

        // ── tiles.bin ─────────────────────────────────────────────
        let tiles = ByteWriter()
        func segment(id: UInt32, from: (Double, Double), to: (Double, Double),
                     heading: UInt16, limit: Int16) {
            tiles.u32(id)
            tiles.i32(e7(from.0)); tiles.i32(e7(from.1))
            tiles.i32(e7(to.0));   tiles.i32(e7(to.1))
            tiles.u16(heading)
            tiles.u8(1)              // roadClass: major
            tiles.u8(RoadDirection.forward.rawValue)
            tiles.i16(limit)
            tiles.u8(1)              // speedSource: osm
            tiles.u8(0)              // flags
        }
        segment(id: 1, from: (21.0000, 105.8000), to: (21.0020, 105.8000), heading: 0, limit: 60)
        segment(id: 2, from: (21.0020, 105.8000), to: (21.0040, 105.8000), heading: 0, limit: 40)
        segment(id: 3, from: (21.0020, 105.8000), to: (21.0000, 105.8000), heading: 180, limit: 60)
        try tiles.data.write(to: dir.appendingPathComponent("tiles.bin"))

        // ── cameras.bin ───────────────────────────────────────────
        let cams = ByteWriter()
        cams.u64(1001); cams.i32(e7(21.0015)); cams.i32(e7(105.8000)); cams.i16(-1); cams.u16(0xFFFF) // 166m phía trước (bắc)
        cams.u64(1002); cams.i32(e7(20.9990)); cams.i32(e7(105.8000)); cams.i16(50); cams.u16(0xFFFF) // phía sau (nam)
        try cams.data.write(to: dir.appendingPathComponent("cameras.bin"))

        // ── signs.bin (3 dòng, 1 dòng type=4 phải bị loại lúc load) ─
        let signs = ByteWriter()
        signs.fixed("VNSG", 4)
        signs.u16(1)          // version
        signs.u32(3)          // signCount
        signs.u16(0)          // reserved
        signs.u32(0)          // crc32
        signs.u32(0)          // timestamp
        func sign(id: UInt32, lat: Double, type: TrafficSignType,
                  limit: UInt8, sub: UInt8, dir: UInt16 = 0xFFFF) {
            signs.u32(id)
            signs.i32(e7(lat)); signs.i32(e7(105.8000))
            signs.u16(dir)
            signs.u8(type.rawValue)
            signs.u8(limit)
            signs.u8(sub)
            signs.u8(0)       // flags
            signs.u16(0)      // reserved
        }
        sign(id: 1, lat: 21.0010, type: .noOvertaking, limit: 0, sub: 0)   // 111m phía trước
        sign(id: 2, lat: 21.0018, type: .speedLimit, limit: 40, sub: 0)    // 200m phía trước
        sign(id: 3, lat: 21.0012, type: .camera, limit: 0, sub: 0)         // trùng cameras.bin → loại
        try signs.data.write(to: dir.appendingPathComponent("signs.bin"))

        // ── names.bin (VNNM v2: header16 + offsets + pool) ────────
        let poolA = Data("Phố Thí Nghiệm A".utf8)
        let poolB = Data("Phố Thí Nghiệm B".utf8)
        var pool = poolA
        pool.append(0)
        let offsetB = UInt32(pool.count)
        pool.append(poolB)
        pool.append(0)

        let names = ByteWriter()
        names.fixed("VNNM", 4)
        names.u16(2)                       // version
        names.u32(2)                       // nameCount
        names.u32(UInt32(pool.count))      // poolBytes
        names.u16(0)                       // reserved
        names.u32(0)                       // offset của nameId 1
        names.u32(offsetB)                 // offset của nameId 2
        names.data.append(pool)
        try names.data.write(to: dir.appendingPathComponent("names.bin"))

        // ── seg_names.bin (1-based: [0] unused) ───────────────────
        let segNames = ByteWriter()
        segNames.u32(0)   // segId 0 (không dùng)
        segNames.u32(1)   // seg1 → name A
        segNames.u32(2)   // seg2 → name B
        segNames.u32(1)   // seg3 → name A
        try segNames.data.write(to: dir.appendingPathComponent("seg_names.bin"))

        // ── metadata.bin (crc32 tính trên indexData) ───────────────
        let meta = ByteWriter()
        meta.fixed("SLMP", 4)
        meta.u16(2)                          // formatVersion
        meta.fixed("VN-TEST", 16)            // region
        meta.fixed("2026.10-test", 16)       // mapVersion
        meta.u64(1_790_000_000)              // buildTimestamp
        meta.u32(1)                          // tileCount
        meta.u32(3)                          // segmentCount
        meta.f32(0.01)                       // tileSizeDeg
        meta.i32(e7(21.0010))                // testLatE7
        meta.i32(e7(105.8000))               // testLonE7
        meta.i16(0)                          // testHeadingDeg
        meta.u32(1)                          // testRoadId
        meta.fixed("(c) OpenStreetMap contributors, ODbL", 64)
        meta.u32(SpeedmapCRC32.compute(indexData))
        try meta.data.write(to: dir.appendingPathComponent("metadata.bin"))

        let db = try SpeedmapDatabase.load(directory: dir)
        return (dir, db)
    }

    static func location(_ lat: Double, _ lon: Double,
                         course: Double, speedKmh: Double) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                   altitude: 0,
                   horizontalAccuracy: 5,
                   verticalAccuracy: 5,
                   course: course,
                   speed: speedKmh / 3.6,
                   timestamp: Date())
    }
}

// MARK: - Database & math

final class SpeedmapDatabaseTests: XCTestCase {

    func testWarnDistanceFormula() {
        XCTAssertEqual(SpeedmapMath.dynamicWarnDistance(speedKmh: 0), 100)
        XCTAssertEqual(SpeedmapMath.dynamicWarnDistance(speedKmh: 20), 100)   // 90 → clamp 100
        XCTAssertEqual(SpeedmapMath.dynamicWarnDistance(speedKmh: 50), 225)
        XCTAssertEqual(SpeedmapMath.dynamicWarnDistance(speedKmh: 80), 360)
        XCTAssertEqual(SpeedmapMath.dynamicWarnDistance(speedKmh: 120), 400)  // 540 → cap 400
        XCTAssertEqual(SpeedmapMath.dynamicWarnDistance(speedKmh: -5), 100)   // speed không hợp lệ
        XCTAssertEqual(SpeedmapMath.signWarnDistanceM, 350)
    }

    func testGeoMath() {
        let a = CLLocationCoordinate2D(latitude: 21.0, longitude: 105.8)
        let north = CLLocationCoordinate2D(latitude: 21.001, longitude: 105.8)
        let east = CLLocationCoordinate2D(latitude: 21.0, longitude: 105.801)

        // 0.001° vĩ độ ≈ 111 m
        XCTAssertEqual(SpeedmapMath.meters(a, north), 111, accuracy: 2)
        XCTAssertEqual(SpeedmapMath.bearing(from: a, to: north), 0, accuracy: 1)
        XCTAssertEqual(SpeedmapMath.bearing(from: a, to: east), 90, accuracy: 1)

        XCTAssertEqual(SpeedmapMath.angularDiff(350, 10), 20, accuracy: 0.001)
        XCTAssertEqual(SpeedmapMath.angularDiff(0, 180), 180, accuracy: 0.001)
        XCTAssertEqual(SpeedmapMath.angularDiff(45, 90), 45, accuracy: 0.001)

        // Điểm ngoài đoạn → khoảng cách tới đầu gần nhất
        let b = CLLocationCoordinate2D(latitude: 21.002, longitude: 105.8)
        // a nằm ngoài đoạn [north…b] → chiếu vào đầu north ≈ 111m
        XCTAssertEqual(SpeedmapMath.pointToSegmentM(a, north, b),
                       SpeedmapMath.meters(a, north), accuracy: 1)
        let west = CLLocationCoordinate2D(latitude: 21.001, longitude: 105.799)
        XCTAssertEqual(SpeedmapMath.pointToSegmentM(west, north, b), 105, accuracy: 5)
    }

    func testLoadSyntheticDatabase() throws {
        let (dir, db) = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(db.metadata.formatVersion, 2)
        XCTAssertEqual(db.metadata.region, "VN-TEST")
        XCTAssertEqual(db.metadata.mapVersion, "2026.10-test")
        XCTAssertEqual(db.metadata.tileCount, 1)
        XCTAssertEqual(db.metadata.segmentCount, 3)
        XCTAssertEqual(db.metadata.testRoadId, 1)
        XCTAssertNotNil(db.metadata.testCoordinate)

        let center = CLLocationCoordinate2D(latitude: 21.0010, longitude: 105.8000)
        XCTAssertEqual(db.segments(near: center, radiusM: 300).count, 3)
    }

    func testRoadNames() throws {
        let (dir, db) = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(db.roadName(segmentId: 1), "Phố Thí Nghiệm A")
        XCTAssertEqual(db.roadName(segmentId: 2), "Phố Thí Nghiệm B")
        XCTAssertEqual(db.roadName(segmentId: 3), "Phố Thí Nghiệm A")
        XCTAssertNil(db.roadName(segmentId: 0))     // không dùng
        XCTAssertNil(db.roadName(segmentId: 99))    // ngoài bảng
    }

    func testMatchRoadHeadingDisambiguation() throws {
        let (dir, db) = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mid = CLLocationCoordinate2D(latitude: 21.0010, longitude: 105.8000)

        // Heading bắc → seg1 (bắc tiến, limit 60)
        let north = db.matchRoad(at: mid, headingDeg: 0)
        XCTAssertEqual(north?.segment.id, 1)
        XCTAssertEqual(north?.name, "Phố Thí Nghiệm A")
        XCTAssertEqual(north?.segment.speedLimitKmh, 60)

        // Heading nam → seg3 (nam tiến, limit 60)
        let south = db.matchRoad(at: mid, headingDeg: 180)
        XCTAssertEqual(south?.segment.id, 3)

        // Không heading tin cậy → chọn đường gần nhất (cùng khoảng cách, không crash)
        let noHeading = db.matchRoad(at: mid, headingDeg: nil)
        XCTAssertNotNil(noHeading)

        // Ngoài phạm vi → nil
        let far = CLLocationCoordinate2D(latitude: 21.05, longitude: 106.5)
        XCTAssertNil(db.matchRoad(at: far, headingDeg: 0, searchRadiusM: 40))
    }

    func testHysteresisKeepsPreviousSegment() throws {
        let (dir, db) = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Gần node chung (21.0020): không heading → match trước đó phải được giữ
        let node = CLLocationCoordinate2D(latitude: 21.00199, longitude: 105.8000)
        let first = db.matchRoad(at: node, headingDeg: 0)
        XCTAssertEqual(first?.segment.id, 1)
        let second = db.matchRoad(at: node, headingDeg: nil, previousSegmentId: 1)
        XCTAssertEqual(second?.segment.id, 1)
    }

    func testCameraAndSignQueries() throws {
        let (dir, db) = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: dir) }

        let center = CLLocationCoordinate2D(latitude: 21.0010, longitude: 105.8000)
        XCTAssertEqual(db.cameras(near: center, radiusM: 500).count, 2)

        // Dòng type=4 (camera trùng lặp) đã bị loại lúc load
        let signs = db.signs(near: center, radiusM: 500)
        XCTAssertEqual(signs.count, 2)
        XCTAssertEqual(signs.first?.type, .noOvertaking)
        XCTAssertEqual(signs.last?.type, .speedLimit)
    }
}

// MARK: - Alert engine (HUD)

@MainActor
final class SpeedmapControllerTests: XCTestCase {

    func testFrontCameraShownBehindHidden() throws {
        let (dir, db) = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = SpeedmapController(database: db)

        // 80 km/h → D_warn = 360m; cam-1001 cách 166m phía trước (bắc)
        controller.update(with: SpeedmapFixture.location(21.0000, 105.8000, course: 0, speedKmh: 80))
        let ids = controller.alerts.map(\.id)
        XCTAssertTrue(ids.contains("cam-1001"), "camera phía trước phải cảnh báo: \(ids)")
        XCTAssertFalse(ids.contains("cam-1002"), "camera phía sau không được cảnh báo: \(ids)")
        XCTAssertTrue(ids.contains("sgn-1"), "biển cấm vượt 111m phải hiện: \(ids)")

        XCTAssertEqual(controller.speedLimitKmh, 60)
        XCTAssertEqual(controller.road?.name, "Phố Thí Nghiệm A")
        XCTAssertEqual(controller.speedKmh ?? 0, 80, accuracy: 1)
        XCTAssertEqual(controller.alerts.count, 3)   // cap 3 card gần nhất
    }

    func testLowSpeedShorterCameraHorizon() throws {
        let (dir, db) = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = SpeedmapController(database: db)

        // 20 km/h → D_warn = clamp(90,100,400) = 100m → camera 166m KHÔNG hiện,
        // nhưng biển báo vẫn 350m → sgn-1 (111m) vẫn hiện.
        controller.update(with: SpeedmapFixture.location(21.0000, 105.8000, course: 0, speedKmh: 20))
        let ids = controller.alerts.map(\.id)
        XCTAssertFalse(ids.contains("cam-1001"), "camera 166m phải nằm ngoài horizon 100m: \(ids)")
        XCTAssertTrue(ids.contains("sgn-1"), "biển 111m phải hiện trong 350m: \(ids)")
    }

    func testAlertRemovedAfterPassing() throws {
        let (dir, db) = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = SpeedmapController(database: db)

        controller.update(with: SpeedmapFixture.location(21.0000, 105.8000, course: 0, speedKmh: 80))
        XCTAssertTrue(controller.alerts.contains { $0.id == "cam-1001" })

        // Đi qua camera ~444m phía sau → card biến mất (không kẹt card cũ)
        controller.update(with: SpeedmapFixture.location(21.0040, 105.8000, course: 0, speedKmh: 80))
        XCTAssertFalse(controller.alerts.contains { $0.id == "cam-1001" })
        XCTAssertFalse(controller.alerts.contains { $0.id == "sgn-1" })
    }

    func testSpeedLimitChangeLookahead() throws {
        let (dir, db) = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = SpeedmapController(database: db)

        // Đang ở seg2 (limit 40), tiến NAM → sắp vào seg3 (limit 60) sau ~180m
        controller.update(with: SpeedmapFixture.location(21.0035, 105.8000, course: 180, speedKmh: 80))
        XCTAssertEqual(controller.speedLimitKmh, 40)
        XCTAssertTrue(controller.alerts.contains {
            $0.id == "spd-3" && $0.kind == .speedLimitChange && $0.title == "Giới hạn 60 km/h"
        }, "thiếu card lookahead đổi giới hạn: \(controller.alerts.map(\.id))")
    }

    func testSelfTestPoint() throws {
        let (dir, db) = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = SpeedmapController(database: db)
        XCTAssertEqual(controller.runSelfTest(), true)
    }

    func testSignAlertMapping() {
        func makeSign(type: TrafficSignType, sub: UInt8, limit: UInt8) -> TrafficSign {
            TrafficSign(id: 1, latE7: 0, lonE7: 0, directionDeg: 0xFFFF,
                        signType: type.rawValue, speedLimitKmh: limit, subType: sub, flags: 0)
        }
        XCTAssertEqual(SpeedmapController.alert(for: makeSign(type: .noOvertaking, sub: 0, limit: 0), distanceM: 100)?.title,
                       "Cấm vượt")
        XCTAssertEqual(SpeedmapController.alert(for: makeSign(type: .noOvertaking, sub: 1, limit: 0), distanceM: 100)?.title,
                       "Hết cấm vượt")
        XCTAssertEqual(SpeedmapController.alert(for: makeSign(type: .speedLimit, sub: 0, limit: 50), distanceM: 100)?.title,
                       "Giới hạn 50 km/h")
        XCTAssertNil(SpeedmapController.alert(for: makeSign(type: .speedLimit, sub: 0, limit: 0), distanceM: 100))
        XCTAssertNil(SpeedmapController.alert(for: makeSign(type: .camera, sub: 0, limit: 0), distanceM: 100))
    }
}

// MARK: - Dữ liệu bundle thật (7 file VietHUD trong app)

final class SpeedmapRealBundleTests: XCTestCase {

    func testRealBundleLoadAndSelfTest() throws {
        guard let dir = SpeedmapDatabase.defaultDirectory() else {
            throw XCTSkip("Bundle không chứa speedmap/*.bin (chạy trong app host)")
        }
        let db = try SpeedmapDatabase.load(directory: dir)

        // Số liệu bản 2026.09 đã xác minh byte-level
        XCTAssertEqual(db.metadata.formatVersion, 2)
        XCTAssertEqual(db.metadata.tileCount, 3437)
        XCTAssertEqual(db.metadata.segmentCount, 182_242)
        XCTAssertEqual(db.metadata.attribution, "(c) OpenStreetMap contributors, ODbL")

        // Tên đường thật tra được
        let name = db.roadName(segmentId: 1)
        XCTAssertNotNil(name)
        XCTAssertFalse(name!.isEmpty)

        // Điểm self-test trong metadata phải match đúng roadId (hợp đồng của builder)
        guard let test = db.metadata.testCoordinate else {
            throw XCTSkip("metadata không có điểm self-test")
        }
        let match = db.matchRoad(at: test,
                                 headingDeg: Double(db.metadata.testHeadingDeg),
                                 searchRadiusM: 40)
        XCTAssertEqual(match?.segment.id, db.metadata.testRoadId,
                       "self-test mismatch: match=\(String(describing: match?.segment.id))")
    }
}

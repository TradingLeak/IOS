import XCTest
@testable import VietMap

final class RouteIntentParserTests: XCTestCase {

    func testParsesBasicVietnameseRoute() throws {
        let intent = try XCTUnwrap(RouteIntentParser.parse("đi từ Cầu Giấy đến Hồ Tây"))
        XCTAssertEqual(intent.origin, "Cầu Giấy")
        XCTAssertEqual(intent.destination, "Hồ Tây")
        XCTAssertTrue(intent.waypoints.isEmpty)
    }

    func testParsesWalkingMode() throws {
        let intent = try XCTUnwrap(RouteIntentParser.parse("chỉ đường đi bộ từ Hồ Hoàn Kiếm đến Nhà thờ Lớn"))
        XCTAssertEqual(intent.origin, "Hồ Hoàn Kiếm")
        XCTAssertEqual(intent.destination, "Nhà thờ Lớn")
        XCTAssertEqual(intent.travelMode, .walking)
    }

    func testParsesTransitModeAndDropsVehicleWords() throws {
        let intent = try XCTUnwrap(RouteIntentParser.parse("từ Hà Nội tới Đà Nẵng bằng xe buýt"))
        XCTAssertEqual(intent.origin, "Hà Nội")
        XCTAssertEqual(intent.destination, "Đà Nẵng")
        XCTAssertEqual(intent.travelMode, .transit)
    }

    func testParsesMotorcycleMode() throws {
        let intent = try XCTUnwrap(RouteIntentParser.parse("đi xe máy từ Cầu Giấy đến Hồ Tây"))
        XCTAssertEqual(intent.travelMode, .motorcycle)
        XCTAssertEqual(intent.destination, "Hồ Tây")
    }

    func testParsesAvoidClause() throws {
        let intent = try XCTUnwrap(RouteIntentParser.parse("đi từ Cầu Giấy đến Hồ Tây, tránh đường đông"))
        XCTAssertEqual(intent.destination, "Hồ Tây")
        XCTAssertEqual(intent.avoid, ["đường đông"])
    }

    func testParsesWaypoint() throws {
        let intent = try XCTUnwrap(RouteIntentParser.parse("từ Đà Nẵng đến Hội An, ghé Ngũ Hành Sơn"))
        XCTAssertEqual(intent.origin, "Đà Nẵng")
        XCTAssertEqual(intent.destination, "Hội An")
        XCTAssertEqual(intent.waypoints, ["Ngũ Hành Sơn"])
    }

    func testArrowSeparator() throws {
        let intent = try XCTUnwrap(RouteIntentParser.parse("Bến Thành -> Suối Tiên"))
        XCTAssertEqual(intent.origin, "Bến Thành")
        XCTAssertEqual(intent.destination, "Suối Tiên")
    }

    func testReturnsNilForUnrelatedSentence() {
        XCTAssertNil(RouteIntentParser.parse("thời tiết hôm nay thế nào"))
        XCTAssertNil(RouteIntentParser.parse(""))
        XCTAssertNil(RouteIntentParser.parse("   "))
    }

    func testModeDetection() {
        XCTAssertEqual(RouteIntentParser.detectMode("đi xe máy ra chợ"), .motorcycle)
        XCTAssertEqual(RouteIntentParser.detectMode("xe máy từ Cầu Giấy đến Hồ Tây"), .motorcycle)
        XCTAssertEqual(RouteIntentParser.detectMode("đi bộ ra chợ"), .walking)
        XCTAssertEqual(RouteIntentParser.detectMode("đạp xe quanh hồ"), .walking)
        XCTAssertEqual(RouteIntentParser.detectMode("lái xe về quê"), .automobile)
        XCTAssertEqual(RouteIntentParser.detectMode("bắt xe buýt đi làm"), .transit)
        XCTAssertNil(RouteIntentParser.detectMode("đi đâu đó"))
    }

    func testAvoidDetection() {
        XCTAssertEqual(RouteIntentParser.detectAvoid("tránh kẹt xe giờ cao điểm"), ["đường đông"])
        XCTAssertEqual(RouteIntentParser.detectAvoid("tránh cao tốc"), ["cao tốc"])
        XCTAssertTrue(RouteIntentParser.detectAvoid("đi bình thường").isEmpty)
    }

    func testCleanRemovesTrailingClauses() {
        XCTAssertEqual(RouteIntentParser.clean("  Hồ Tây , tránh đường đông"), "Hồ Tây")
        XCTAssertEqual(RouteIntentParser.clean("từ Hà Nội"), "Hà Nội")
    }
}

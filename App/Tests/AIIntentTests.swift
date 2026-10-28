import XCTest
@testable import VietMap

final class AIIntentTests: XCTestCase {

    private func decode(_ json: String) throws -> AIIntent {
        try JSONDecoder().decode(AIIntent.self, from: Data(json.utf8))
    }

    func testDecodesStandardSchema() throws {
        let intent = try decode("""
        {
          "origin": "Cầu Giấy",
          "destination": "Hồ Tây",
          "waypoints": ["Ba Đình"],
          "mode": "walking",
          "avoid": ["đường đông"],
          "explanation": "Đi bộ sẽ nhanh hơn vì quãng đường ngắn."
        }
        """)
        XCTAssertEqual(intent.origin, "Cầu Giấy")
        XCTAssertEqual(intent.destination, "Hồ Tây")
        XCTAssertEqual(intent.waypoints, ["Ba Đình"])
        XCTAssertEqual(intent.mode, "walking")
        XCTAssertEqual(intent.avoid, ["đường đông"])
        XCTAssertEqual(intent.travelMode, .walking)
    }

    func testDecodesAlternativeKeyNames() throws {
        let intent = try decode(#"{"from": "Bến Thành", "to": "Suối Tiên", "transport": "transit"}"#)
        XCTAssertEqual(intent.origin, "Bến Thành")
        XCTAssertEqual(intent.destination, "Suối Tiên")
        XCTAssertEqual(intent.travelMode, .transit)
    }

    func testNullLikeStringsBecomeNil() throws {
        let intent = try decode(#"{"origin": "null", "destination": "Hồ Tây"}"#)
        XCTAssertNil(intent.origin)
        XCTAssertEqual(intent.destination, "Hồ Tây")
    }

    func testMissingFieldsUseSensibleDefaults() throws {
        let intent = try decode(#"{"destination": "Đà Lạt"}"#)
        XCTAssertEqual(intent.destination, "Đà Lạt")
        XCTAssertNil(intent.origin)
        XCTAssertTrue(intent.waypoints.isEmpty)
        XCTAssertTrue(intent.avoid.isEmpty)
        XCTAssertEqual(intent.travelMode, .automobile)
    }

    func testWaypointsAsCommaSeparatedString() throws {
        let intent = try decode(#"{"destination": "Hội An", "waypoints": "Ngũ Hành Sơn, Cửa Đại"}"#)
        XCTAssertEqual(intent.waypoints, ["Ngũ Hành Sơn", "Cửa Đại"])
    }

    func testModeParsing() {
        XCTAssertEqual(TravelMode.parse("automobile"), .automobile)
        XCTAssertEqual(TravelMode.parse("xe máy"), .automobile)
        XCTAssertEqual(TravelMode.parse("walking"), .walking)
        XCTAssertEqual(TravelMode.parse("đi bộ"), .walking)
        XCTAssertEqual(TravelMode.parse("transit"), .transit)
        XCTAssertEqual(TravelMode.parse("xe buýt"), .transit)
        XCTAssertNil(TravelMode.parse("bay"))
        XCTAssertNil(TravelMode.parse(nil))
    }

    func testPlannerDecodesFencedResponse() {
        let content = """
        ```json
        {"origin":"Hà Nội","destination":"Hạ Long","mode":"automobile"}
        ```
        """
        let intent = AIRoutePlanner.decodeIntent(from: content)
        XCTAssertEqual(intent?.destination, "Hạ Long")
        XCTAssertEqual(intent?.travelMode, .automobile)
    }

    func testPlannerReturnsNilForGarbage() {
        XCTAssertNil(AIRoutePlanner.decodeIntent(from: "Xin lỗi, tôi không hiểu."))
    }
}

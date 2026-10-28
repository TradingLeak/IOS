import XCTest
import CoreLocation
@testable import VietMap

final class LaneGuidanceTests: XCTestCase {

    private func step(_ text: String) -> RouteStep {
        RouteStep(instruction: text,
                  distance: 300,
                  endCoordinate: CLLocationCoordinate2D(latitude: 21.03, longitude: 105.85))
    }

    func testNoHintWhenFarAway() {
        XCTAssertNil(LaneGuidance.hint(for: step("Rẽ phải vào Nguyễn Chí Thanh"), distance: 800))
    }

    func testNoHintWhenArrived() {
        XCTAssertNil(LaneGuidance.hint(for: step("Đến nơi"), distance: 40))
    }

    func testLeftTurnHighlightsLeftmostLane() throws {
        let hint = try XCTUnwrap(LaneGuidance.hint(for: step("Rẽ trái vào Đường Láng"), distance: 180))
        XCTAssertEqual(hint.laneCount, 3)
        XCTAssertEqual(hint.highlighted, [0])
        XCTAssertEqual(hint.caption, "Làn trái")
        XCTAssertEqual(hint.symbol(forLane: 0), "arrow.turn.up.left")
        XCTAssertEqual(hint.symbol(forLane: 2), "arrow.up")
    }

    func testRightTurnHighlightsRightmostLane() throws {
        let hint = try XCTUnwrap(LaneGuidance.hint(for: step("Rẽ phải vào Tây Sơn"), distance: 120))
        XCTAssertEqual(hint.highlighted, [2])
        XCTAssertEqual(hint.symbol(forLane: 2), "arrow.turn.up.right")
    }

    func testRoundaboutUsesRightLane() throws {
        let hint = try XCTUnwrap(LaneGuidance.hint(for: step("Đi vào vòng xuyến"), distance: 90))
        XCTAssertEqual(hint.highlighted, [2])
        XCTAssertEqual(hint.caption, "Vào vòng xuyến")
    }

    func testStraightInstructionGivesNoHint() {
        XCTAssertNil(LaneGuidance.hint(for: step("Đi thẳng trên Đại lộ Thăng Long"), distance: 250))
        XCTAssertNil(LaneGuidance.hint(for: nil, distance: 100))
    }

    func testLaneCountIsClampedAndHighlightFiltered() {
        let hint = LaneGuidance(laneCount: 9, highlighted: [0, 7], caption: "Thử")
        XCTAssertEqual(hint.laneCount, 4)
        XCTAssertEqual(hint.highlighted, [0])
    }
}

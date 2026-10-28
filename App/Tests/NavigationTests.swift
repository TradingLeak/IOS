import XCTest
import CoreLocation
import MapKit
@testable import VietMap

/// Hình học tuyến & điều hướng (off-route / reroute) — P1.
final class RouteGeometryTests: XCTestCase {

    private let a = CLLocationCoordinate2D(latitude: 21.00, longitude: 105.80)
    private let b = CLLocationCoordinate2D(latitude: 21.01, longitude: 105.80)

    private var line: [CLLocationCoordinate2D] {
        [a, b]   // đường dọc ~1.111 km
    }

    func testEmptyPolylineReturnsNil() {
        XCTAssertNil(RouteGeometry.minDistance(from: a, to: []))
    }

    func testSinglePointPolyline() {
        let d = RouteGeometry.minDistance(from: a, to: [b])
        XCTAssertEqual(d ?? -1, SpeedmapMath.meters(a, b), accuracy: 1)
    }

    func testPointOnLineHasNearZeroDistance() {
        let mid = CLLocationCoordinate2D(latitude: 21.005, longitude: 105.80)
        let d = RouteGeometry.minDistance(from: mid, to: line) ?? -1
        XCTAssertEqual(d, 0, accuracy: 1)
    }

    func testPointBesideLine() {
        // Cách đường ~0.005° kinh độ ≈ 520m tại vĩ độ 21°
        let side = CLLocationCoordinate2D(latitude: 21.005, longitude: 105.805)
        let d = RouteGeometry.minDistance(from: side, to: line) ?? -1
        XCTAssertEqual(d, 520, accuracy: 15)
    }

    func testOffRouteThreshold() {
        let onLine = CLLocationCoordinate2D(latitude: 21.005, longitude: 105.8001)
        XCTAssertFalse(RouteGeometry.isOffRoute(onLine, from: line, thresholdM: 70))

        let far = CLLocationCoordinate2D(latitude: 21.005, longitude: 105.810)
        XCTAssertTrue(RouteGeometry.isOffRoute(far, from: line, thresholdM: 70))
    }

    func testOffRouteOnEmptyPolylineIsFalse() {
        XCTAssertFalse(RouteGeometry.isOffRoute(a, from: [], thresholdM: 70))
    }

    func testVoiceAlertText() {
        let alert = HazardAlert(id: "cam-1",
                                kind: .camera,
                                title: "Camera phạt nguội",
                                subtitle: nil,
                                distanceM: 165,
                                speedLimitKmh: nil,
                                coordinate: a)
        XCTAssertEqual(VoiceGuide.alertText(alert), "Camera phạt nguội, 165 mét")

        let far = HazardAlert(id: "cam-2",
                              kind: .camera,
                              title: "Camera phạt nguội",
                              subtitle: nil,
                              distanceM: 1500,
                              speedLimitKmh: nil,
                              coordinate: a)
        XCTAssertEqual(VoiceGuide.alertText(far), "Camera phạt nguội, 1.5 ki lô mét")
    }

    func testNavAnnouncementEquatable() {
        XCTAssertEqual(NavAnnouncement.arrived, .arrived)
        XCTAssertNotEqual(NavAnnouncement.arrived, .rerouted)
    }
}

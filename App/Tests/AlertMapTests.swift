import XCTest
import MapKit
@testable import VietMap

/// Mức nguy hiểm dùng để tô màu marker biển báo/camera **ngay trên bản đồ** (2.2).
/// Đây là logic quyết định "xám → màu loại → cam → đỏ", nên phải có test.
@MainActor
final class AlertMapSeverityTests: XCTestCase {

    private func makeAlert(_ kind: AlertKind, limit: Int? = nil) -> RoadAlert {
        RoadAlert(kind: kind,
                  latitude: 21.0278,
                  longitude: 105.8342,
                  speedLimit: limit,
                  road: "Nguyễn Trãi")
    }

    func testCloseIsMostSevere() {
        let alert = makeAlert(.speedCamera)
        XCTAssertEqual(MapViewModel.severity(for: alert, level: .close), 3)
    }

    func testApproachingIsOrange() {
        XCTAssertEqual(MapViewModel.severity(for: makeAlert(.redLightCamera), level: .approaching), 2)
    }

    func testFarKeepsKindColour() {
        // Còn xa: camera an toàn trọng yếu vẫn đáng chú ý, biển phụ thì để xám.
        XCTAssertEqual(MapViewModel.severity(for: makeAlert(.speedCamera), level: .far), 1)
        XCTAssertEqual(MapViewModel.severity(for: makeAlert(.surveillanceCamera), level: .far), 0)
    }

    func testPassedIsMuted() {
        XCTAssertEqual(MapViewModel.severity(for: makeAlert(.hazard), level: .passed), 0)
    }

    func testWithoutRouteSpeedSignOutranksCamera() {
        // Chưa có tuyến: biển giới hạn tốc độ là thông tin cần thấy nhất.
        XCTAssertEqual(MapViewModel.severity(for: makeAlert(.speedSign, limit: 60), level: nil), 2)
        XCTAssertEqual(MapViewModel.severity(for: makeAlert(.speedCamera), level: nil), 1)
        XCTAssertEqual(MapViewModel.severity(for: makeAlert(.tollStation), level: nil), 0)
    }

    func testMapPinCarriesAlertMetadata() {
        let alert = makeAlert(.speedZone, limit: 50)
        let pin = MapPin(id: "alert-1",
                         coordinate: alert.coordinate,
                         title: alert.displayName,
                         subtitle: "còn 320 m",
                         kind: .camera,
                         alertKind: alert.kind,
                         limit: alert.speedLimit,
                         severity: MapViewModel.severity(for: alert, level: .close),
                         distance: 320)
        XCTAssertEqual(pin.alertKind, .speedZone)
        XCTAssertEqual(pin.limit, 50)
        XCTAssertEqual(pin.severity, 3)
        XCTAssertEqual(pin.distance, 320)
    }

    func testPlainPinsDefaultToSafeValues() {
        let pin = MapPin(id: "poi",
                         coordinate: alertCoordinate,
                         title: "Quán cà phê",
                         subtitle: "",
                         kind: .poi)
        XCTAssertNil(pin.alertKind)
        XCTAssertNil(pin.limit)
        XCTAssertEqual(pin.severity, 0)
        XCTAssertNil(pin.distance)
    }

    private var alertCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 21.0278, longitude: 105.8342)
    }
}

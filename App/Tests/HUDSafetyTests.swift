import XCTest
import CoreLocation
@testable import VietMap

final class HUDSafetyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fix(age: TimeInterval = 0, accuracy: Double = 5, speed: Double = 10) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105.8),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5,
                   course: 0, speed: speed, timestamp: now.addingTimeInterval(-age))
    }

    func testValidSpeedConvertedToKmh() {
        XCTAssertTrue(HUDSafety.hasUsableFix(fix(), now: now))
        XCTAssertEqual(HUDSafety.speedKmh(fix(), now: now)!, 36, accuracy: 0.001)
        XCTAssertEqual(HUDSafety.speedKmh(fix(speed: 0), now: now), 0)
    }

    func testMissingOrInvalidSpeedIsNotZero() {
        XCTAssertNil(HUDSafety.speedKmh(nil, now: now))
        XCTAssertNil(HUDSafety.speedKmh(fix(speed: -1), now: now))
        XCTAssertNil(HUDSafety.speedKmh(fix(speed: .nan), now: now))
        XCTAssertNil(HUDSafety.speedKmh(fix(speed: .infinity), now: now))
    }

    func testStaleAndFutureSamplesAreRejected() {
        XCTAssertTrue(HUDSafety.hasUsableFix(fix(age: 10), now: now))
        XCTAssertFalse(HUDSafety.hasUsableFix(fix(age: 10.01), now: now))
        XCTAssertFalse(HUDSafety.hasUsableFix(fix(age: -3), now: now))
        XCTAssertNil(HUDSafety.speedKmh(fix(age: 11), now: now))
    }

    func testPoorAndInvalidAccuracyAreRejected() {
        for accuracy in [-1.0, 50.1, .nan, .infinity] {
            XCTAssertFalse(HUDSafety.hasUsableFix(fix(accuracy: accuracy), now: now))
        }
        XCTAssertTrue(HUDSafety.hasUsableFix(fix(accuracy: 50), now: now))
    }

    func testOverspeedHysteresis() {
        var monitor = OverspeedMonitor()
        XCTAssertFalse(monitor.update(speedKmh: 62, limitKmh: 60, now: now))
        XCTAssertTrue(monitor.update(speedKmh: 63, limitKmh: 60, now: now))
        XCTAssertTrue(monitor.isOverspeed)
        XCTAssertFalse(monitor.update(speedKmh: 61, limitKmh: 60, now: now))
        XCTAssertTrue(monitor.isOverspeed)
        XCTAssertFalse(monitor.update(speedKmh: 60, limitKmh: 60, now: now))
        XCTAssertFalse(monitor.isOverspeed)
    }

    func testOverspeedAnnouncementsHaveCooldown() {
        var monitor = OverspeedMonitor()
        XCTAssertTrue(monitor.update(speedKmh: 70, limitKmh: 60, now: now))
        XCTAssertFalse(monitor.update(speedKmh: 70, limitKmh: 60, now: now.addingTimeInterval(29)))
        XCTAssertTrue(monitor.update(speedKmh: 70, limitKmh: 60, now: now.addingTimeInterval(30)))
        // Mất GPS không xoá cooldown và không được đọc lại ngay khi có GPS.
        XCTAssertFalse(monitor.update(speedKmh: nil, limitKmh: 60, now: now.addingTimeInterval(31)))
        XCTAssertFalse(monitor.isOverspeed)
        XCTAssertFalse(monitor.update(speedKmh: 70, limitKmh: 60, now: now.addingTimeInterval(32)))
    }

    func testNoLimitMeansNoOverspeedAnnouncement() {
        var monitor = OverspeedMonitor()
        XCTAssertFalse(monitor.update(speedKmh: 70, limitKmh: nil, now: now))
        XCTAssertFalse(monitor.update(speedKmh: 70, limitKmh: 0, now: now))
        XCTAssertFalse(monitor.update(speedKmh: .nan, limitKmh: 60, now: now))
        XCTAssertFalse(monitor.update(speedKmh: -1, limitKmh: 60, now: now))
        XCTAssertFalse(monitor.isOverspeed)
    }
}

@MainActor
final class HUDControllerSafetyTests: XCTestCase {
    func testStaleFixClearsReadingsAndAlerts() throws {
        let fixture = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let controller = SpeedmapController(database: fixture.database)
        let location = SpeedmapFixture.location(21, 105.8, course: 0, speedKmh: 80)
        controller.update(with: location)
        XCTAssertNotNil(controller.speedKmh)
        XCTAssertFalse(controller.alerts.isEmpty)
        controller.invalidateIfNeeded(now: location.timestamp.addingTimeInterval(11))
        XCTAssertNil(controller.speedKmh)
        XCTAssertNil(controller.speedLimitKmh)
        XCTAssertNil(controller.road)
        XCTAssertTrue(controller.alerts.isEmpty)
    }

    func testDeniedOrBackgroundResetDoesNotReuseLastFix() throws {
        let fixture = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let controller = SpeedmapController(database: fixture.database)
        controller.update(with: SpeedmapFixture.location(21, 105.8, course: 0, speedKmh: 80))
        controller.resetLocation()
        controller.tick()
        XCTAssertNil(controller.speedKmh)
        XCTAssertNil(controller.road)
        XCTAssertTrue(controller.alerts.isEmpty)
    }

    func testInaccurateLocationDoesNotProduceHazardAlerts() throws {
        let fixture = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let controller = SpeedmapController(database: fixture.database)
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105.8),
                                  altitude: 0, horizontalAccuracy: 200, verticalAccuracy: 5,
                                  course: 0, speed: 20, timestamp: Date())
        controller.update(with: location)
        XCTAssertNil(controller.speedKmh)
        XCTAssertNil(controller.speedLimitKmh)
        XCTAssertTrue(controller.alerts.isEmpty)
    }

    func testInstallingDatabaseProcessesFixReceivedWhileLoading() throws {
        let fixture = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let controller = SpeedmapController()
        controller.update(with: SpeedmapFixture.location(21, 105.8, course: 0, speedKmh: 80))
        controller.install(fixture.database)
        XCTAssertNotNil(controller.speedKmh)
        XCTAssertNotNil(controller.road)
    }

    func testOlderLocationDoesNotOverwriteCurrentFix() throws {
        let fixture = try SpeedmapFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let controller = SpeedmapController(database: fixture.database)
        let location = SpeedmapFixture.location(21, 105.8, course: 0, speedKmh: 80)
        controller.update(with: location)
        let old = CLLocation(coordinate: location.coordinate, altitude: 0,
                             horizontalAccuracy: 5, verticalAccuracy: 5,
                             course: 0, speed: 0, timestamp: location.timestamp.addingTimeInterval(-1))
        controller.update(with: old)
        XCTAssertEqual(controller.speedKmh!, 80, accuracy: 0.01)
    }
}

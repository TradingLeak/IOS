import XCTest
import CoreLocation
@testable import VietMap

final class AlertModelTests: XCTestCase {

    func testDecodesDatasetWithUnknownKindAndStringSpeed() throws {
        let json = """
        {
          "schema": 2,
          "alerts": [
            {"id": "a1", "kind": "speed_camera", "lat": 21.0285, "lng": 105.8542},
            {"id": "a2", "kind": "khong_biet", "lat": 10.77, "lng": 106.70, "speedLimit": "60"},
            {"id": "a3", "kind": "speed_zone", "lat": 16.05, "lng": 108.20,
             "speed_limit": 50, "length": 400, "bearing": 90}
          ]
        }
        """
        let dataset = try AlertDatabase.decode(Data(json.utf8))
        XCTAssertEqual(dataset.alerts.count, 3)

        let camera = dataset.alerts[0]
        XCTAssertEqual(camera.kind, .speedCamera)
        XCTAssertTrue(camera.hasValidCoordinate)

        let unknown = dataset.alerts[1]
        XCTAssertEqual(unknown.kind, .other)
        XCTAssertEqual(unknown.speedLimit, 60)

        let zone = dataset.alerts[2]
        XCTAssertEqual(zone.kind, .speedZone)
        XCTAssertEqual(zone.speedLimit, 50)
        XCTAssertEqual(zone.length, 400)
        XCTAssertEqual(zone.bearing, 90)
    }

    func testInvalidCoordinateIsRejectedByDatabase() {
        let valid = RoadAlert(id: "ok", kind: .hazard, latitude: 21.0, longitude: 105.0)
        let broken = RoadAlert(id: "bad", kind: .hazard, latitude: 0, longitude: 0)
        let database = AlertDatabase(alerts: [valid, broken])
        XCTAssertEqual(database.count, 1)
        XCTAssertEqual(database.alerts.first?.id, "ok")
    }

    func testDuplicateIDsAreDropped() {
        let first = RoadAlert(id: "same", kind: .speedCamera, latitude: 21.0, longitude: 105.0)
        let second = RoadAlert(id: "same", kind: .speedCamera, latitude: 21.1, longitude: 105.1)
        XCTAssertEqual(AlertDatabase(alerts: [first, second]).count, 1)
    }

    func testBundledDatasetIsPresent() {
        let database = AlertDatabase.loadBundled()
        XCTAssertGreaterThan(database.count, 100, "Không nạp được vn_alerts.json từ bundle")
        XCTAssertGreaterThan(database.cameraCount, 100)
        XCTAssertFalse(database.sources.isEmpty)
    }
}

final class AlertDatabaseQueryTests: XCTestCase {

    private func makeDatabase() -> AlertDatabase {
        AlertDatabase(alerts: [
            RoadAlert(id: "cam-1", kind: .speedCamera, latitude: 21.005, longitude: 105.0),
            RoadAlert(id: "cam-2", kind: .surveillanceCamera, latitude: 21.02, longitude: 105.0),
            RoadAlert(id: "zone-1", kind: .speedZone, latitude: 21.010, longitude: 105.0,
                      speedLimit: 60, length: 500),
            RoadAlert(id: "far", kind: .speedCamera, latitude: 10.77, longitude: 106.70)
        ])
    }

    func testNearbyFiltersByRadiusAndKind() {
        let database = makeDatabase()
        let center = CLLocationCoordinate2D(latitude: 21.0, longitude: 105.0)

        // cam-1 ≈ 556 m, zone-1 ≈ 1.113 m, cam-2 ≈ 2.224 m (ngoài bán kính 2 km)
        let all = database.nearby(around: center, radius: 2_000)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(database.nearby(around: center, radius: 3_000).count, 3)

        let cameras = database.nearby(around: center, radius: 2_000, kinds: [.speedCamera])
        XCTAssertEqual(cameras.count, 1)
        XCTAssertEqual(cameras.first?.id, "cam-1")

        let none = database.nearby(around: center, radius: 50)
        XCTAssertTrue(none.isEmpty)
    }

    func testAlongRouteComputesDistances() {
        let database = makeDatabase()
        let route = [CLLocationCoordinate2D(latitude: 21.0, longitude: 105.0),
                     CLLocationCoordinate2D(latitude: 21.03, longitude: 105.0)]
        let geometry = RouteGeometry(coordinates: route)
        XCTAssertEqual(geometry.totalDistance, 3_339, accuracy: 60)

        let alerts = database.alongRoute(geometry, corridor: 80)
        XCTAssertEqual(alerts.count, 3)

        // cam-1 ở 0,005° vĩ độ ≈ 556 m
        let camera = alerts.first { $0.alert.id == "cam-1" }
        XCTAssertNotNil(camera)
        XCTAssertEqual(camera?.distanceAlongRoute ?? 0, 556, accuracy: 25)
    }

    func testBearingFiltersOppositeDirection() {
        let database = AlertDatabase(alerts: [
            RoadAlert(id: "north", kind: .speedCamera, latitude: 21.005, longitude: 105.0, bearing: 0),
            RoadAlert(id: "south", kind: .speedCamera, latitude: 21.010, longitude: 105.0, bearing: 180)
        ])
        // Tuyến đi về hướng Bắc (bearing ≈ 0) → chỉ giữ camera hướng Bắc.
        let geometry = RouteGeometry(coordinates: [
            CLLocationCoordinate2D(latitude: 21.0, longitude: 105.0),
            CLLocationCoordinate2D(latitude: 21.03, longitude: 105.0)
        ])
        let alerts = database.alongRoute(geometry, corridor: 60)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.alert.id, "north")
    }
}

final class GeoAndPolylineTests: XCTestCase {

    func testAngleDifferenceWrapsAroundZero() {
        XCTAssertEqual(Geo.angleDifference(350, 10), 20, accuracy: 0.001)
        XCTAssertEqual(Geo.angleDifference(10, 350), 20, accuracy: 0.001)
        XCTAssertEqual(Geo.angleDifference(0, 180), 180, accuracy: 0.001)
    }

    func testDistanceBetweenKnownPoints() {
        let hanoi = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542)
        let hcm = CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009)
        XCTAssertEqual(Geo.distance(hanoi, hcm) / 1000, 1_137, accuracy: 30)
    }

    func testRouteGeometryProjection() {
        let geometry = RouteGeometry(coordinates: [
            CLLocationCoordinate2D(latitude: 21.0, longitude: 105.0),
            CLLocationCoordinate2D(latitude: 21.0, longitude: 105.02)
        ])
        let projection = geometry.projection(of: CLLocationCoordinate2D(latitude: 21.001, longitude: 105.01))
        XCTAssertNotNil(projection)
        XCTAssertEqual(projection?.offset ?? 0, 111, accuracy: 20)
        XCTAssertEqual((projection?.along ?? 0) / geometry.totalDistance, 0.5, accuracy: 0.05)
    }

    func testDecodesGooglePolyline() {
        let coordinates = PolylineCoder.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(coordinates.count, 3)
        XCTAssertEqual(coordinates[0].latitude, 38.5, accuracy: 0.0001)
        XCTAssertEqual(coordinates[0].longitude, -120.2, accuracy: 0.0001)
        XCTAssertEqual(coordinates[1].latitude, 40.7, accuracy: 0.0001)
        XCTAssertEqual(coordinates[2].longitude, -126.453, accuracy: 0.0001)
    }

    func testEmptyPolylineIsSafe() {
        XCTAssertTrue(PolylineCoder.decode("").isEmpty)
        XCTAssertTrue(RouteGeometry(coordinates: []).isEmpty)
    }
}

final class WarnDistanceTests: XCTestCase {

    func testFormulaClamps() {
        XCTAssertEqual(ActiveAlert.warnDistance(forSpeed: 0, min: 150, max: 500), 150)
        XCTAssertEqual(ActiveAlert.warnDistance(forSpeed: 30, min: 150, max: 500), 150)
        XCTAssertEqual(ActiveAlert.warnDistance(forSpeed: 80, min: 150, max: 500), 240)
        XCTAssertEqual(ActiveAlert.warnDistance(forSpeed: 200, min: 150, max: 500), 500)
        XCTAssertEqual(ActiveAlert.warnDistance(forSpeed: nil, min: 150, max: 500), 150)
    }
}

final class SpeedLimitRuleTests: XCTestCase {

    func testClassifiesVietnameseRoadNames() {
        XCTAssertEqual(SpeedLimitRules.classify("Đường cao tốc Pháp Vân - Cầu Giẽ"), .expressway)
        XCTAssertEqual(SpeedLimitRules.classify("Quốc lộ 1A"), .nationalHighway)
        XCTAssertEqual(SpeedLimitRules.classify("Tỉnh lộ 10"), .provincialRoad)
        XCTAssertEqual(SpeedLimitRules.classify("Đường Láng"), .urbanStreet)
        XCTAssertEqual(SpeedLimitRules.classify("Hẻm 45 Nguyễn Trãi"), .residential)
        XCTAssertEqual(SpeedLimitRules.classify(""), .other)
    }

    func testMotorcycleLimitsFollowCircular38() {
        XCTAssertEqual(SpeedLimitRules.legalLimit(roadClass: .urbanStreet, area: .urban,
                                                  mode: .motorcycle, dualCarriageway: true), 60)
        XCTAssertEqual(SpeedLimitRules.legalLimit(roadClass: .urbanStreet, area: .urban,
                                                  mode: .motorcycle, dualCarriageway: false), 50)
        XCTAssertEqual(SpeedLimitRules.legalLimit(roadClass: .nationalHighway, area: .rural,
                                                  mode: .motorcycle, dualCarriageway: true), 70)
        XCTAssertEqual(SpeedLimitRules.legalLimit(roadClass: .nationalHighway, area: .rural,
                                                  mode: .motorcycle, dualCarriageway: false), 60)
        // Xe máy không được đi cao tốc → không có giới hạn hợp lệ.
        XCTAssertNil(SpeedLimitRules.legalLimit(roadClass: .expressway, area: .rural, mode: .motorcycle))
    }

    func testMopedAlwaysForty() {
        // Xe gắn máy ≤ 50 cm³: 40 km/h trên mọi loại đường, kể cả đường đôi, quốc lộ.
        for (roadClass, area) in [(RoadClass.urbanStreet, RoadArea.urban),
                                  (.nationalHighway, .rural),
                                  (.provincialRoad, .rural),
                                  (.residential, .urban)] {
            XCTAssertEqual(SpeedLimitRules.legalLimit(roadClass: roadClass, area: area,
                                                      mode: .motorcycle,
                                                      dualCarriageway: true,
                                                      vehicle: .moped), 40)
        }
        XCTAssertNil(SpeedLimitRules.legalLimit(roadClass: .expressway, area: .rural,
                                                mode: .motorcycle, vehicle: .moped))
        XCTAssertEqual(SpeedLimitRules.estimate(roadNames: ["Quốc lộ 1A"],
                                                mode: .motorcycle,
                                                vehicle: .moped), 40)
        XCTAssertEqual(SpeedLimitRules.estimate(roadNames: ["Quốc lộ 1A"],
                                                mode: .motorcycle,
                                                vehicle: .motorcycle), 70)
    }

    func testCarLimits() {
        XCTAssertEqual(SpeedLimitRules.legalLimit(roadClass: .urbanStreet, area: .urban,
                                                  mode: .automobile, dualCarriageway: true), 60)
        XCTAssertEqual(SpeedLimitRules.legalLimit(roadClass: .nationalHighway, area: .rural,
                                                  mode: .automobile, dualCarriageway: true), 90)
        XCTAssertEqual(SpeedLimitRules.legalLimit(roadClass: .expressway, area: .rural, mode: .automobile), 120)
        XCTAssertNil(SpeedLimitRules.legalLimit(roadClass: .urbanStreet, area: .urban, mode: .walking))
    }

    func testEstimateFromRoadNames() {
        XCTAssertEqual(SpeedLimitRules.estimate(roadNames: ["Đường Láng"], mode: .motorcycle), 50)
        XCTAssertEqual(SpeedLimitRules.estimate(roadNames: ["Quốc lộ 1A"], mode: .automobile), 90)
    }

    func testRoadNameExtraction() {
        XCTAssertEqual(SpeedLimitRules.roadName(in: "Rẽ phải vào Đường Láng"), "Đường Láng")
        XCTAssertEqual(SpeedLimitRules.roadName(in: "Đi trên Quốc lộ 5, hướng Hải Phòng"), "Quốc lộ 5")
        XCTAssertNil(SpeedLimitRules.roadName(in: ""))
    }
}

final class AlertEngineTests: XCTestCase {

    private func route() -> RouteOption {
        let coordinates = [CLLocationCoordinate2D(latitude: 21.0, longitude: 105.0),
                           CLLocationCoordinate2D(latitude: 21.03, longitude: 105.0)]
        let steps = [RouteStep(instruction: "Đi thẳng trên Đường Láng", distance: 3_300,
                               endCoordinate: coordinates[1], roadName: "Đường Láng")]
        return RouteOption(name: "Tuyến chính",
                           distance: 3_339,
                           expectedTravelTime: 600,
                           coordinates: coordinates,
                           steps: steps,
                           mode: .motorcycle,
                           advisoryNotices: [])
    }

    func testZoneLimitAppliesInsideZone() {
        let database = AlertDatabase(alerts: [
            RoadAlert(id: "z", kind: .speedZone, latitude: 21.005, longitude: 105.0,
                      speedLimit: 40, length: 800)
        ])
        let engine = AlertEngine(database: database, preferences: .all)
        let alerts = engine.alertsAlongRoute(route())
        XCTAssertEqual(alerts.count, 1)

        let inside = engine.speedLimit(at: 900, alerts: alerts, roadNames: ["Đường Láng"], mode: .motorcycle)
        XCTAssertEqual(inside.limit, 40)
        XCTAssertEqual(inside.source, .zone)

        let before = engine.speedLimit(at: 100, alerts: alerts, roadNames: ["Đường Láng"], mode: .motorcycle)
        XCTAssertEqual(before.limit, 50)
        XCTAssertEqual(before.source, .estimated)
    }

    func testAheadAlertsUseRelativeDistance() {
        let database = AlertDatabase(alerts: [
            RoadAlert(id: "cam", kind: .speedCamera, latitude: 21.02, longitude: 105.0)
        ])
        let engine = AlertEngine(database: database, preferences: .all)
        let alerts = engine.alertsAlongRoute(route())
        XCTAssertEqual(alerts.count, 1)

        let ahead = engine.aheadAlerts(from: 1_000, alerts: alerts, speedKmh: 50, horizon: 2_000)
        XCTAssertEqual(ahead.count, 1)
        XCTAssertEqual(ahead.first?.distance ?? 0, 1_224, accuracy: 60)

        let behind = engine.aheadAlerts(from: 2_500, alerts: alerts, speedKmh: 50, horizon: 2_000)
        XCTAssertTrue(behind.isEmpty)
    }

    func testAnnouncementMentionsDistance() {
        let alert = RoadAlert(id: "cam", kind: .speedCamera, latitude: 21.02, longitude: 105.0)
        let active = ActiveAlert(alert: alert, distance: 320, warnDistance: 150, distanceAlongRoute: 320)
        let text = AlertEngine.announcement(for: active, mode: .motorcycle)
        XCTAssertTrue(text.contains("camera"))
        XCTAssertTrue(text.contains("320"))
    }

    func testOverspeedDetection() {
        var context = SpeedContext()
        context.speedKmh = 70
        context.limit = 60
        context.tolerance = 5
        XCTAssertTrue(context.isOverLimit)
        XCTAssertEqual(context.overspeed, 10, accuracy: 0.001)
        XCTAssertNotNil(AlertEngine.overspeedAnnouncement(context))

        context.speedKmh = 62
        XCTAssertFalse(context.isOverLimit)
    }
}

final class RouteScorerTests: XCTestCase {

    private func makeRoute(name: String,
                           distance: Double,
                           time: Double,
                           stepText: String) -> RouteOption {
        let coordinates = [CLLocationCoordinate2D(latitude: 21.0, longitude: 105.0),
                           CLLocationCoordinate2D(latitude: 21.05, longitude: 105.05)]
        let steps = [RouteStep(instruction: stepText, distance: distance,
                               endCoordinate: coordinates[1])]
        return RouteOption(name: name,
                           distance: distance,
                           expectedTravelTime: time,
                           coordinates: coordinates,
                           steps: steps,
                           mode: .motorcycle,
                           advisoryNotices: [])
    }

    func testExpresswayShare() {
        let onHighway = makeRoute(name: "A", distance: 10_000, time: 600,
                                  stepText: "Đi vào đường cao tốc Pháp Vân")
        XCTAssertEqual(RouteScorer.expresswayShare(onHighway), 1, accuracy: 0.001)

        let city = makeRoute(name: "B", distance: 10_000, time: 900, stepText: "Đi trên Đường Láng")
        XCTAssertEqual(RouteScorer.expresswayShare(city), 0, accuracy: 0.001)
    }

    func testFasterRouteScoresHigher() {
        let scorer = RouteScorer(database: AlertDatabase(alerts: []))
        let fast = makeRoute(name: "Nhanh", distance: 10_000, time: 600, stepText: "Đường Láng")
        let slow = makeRoute(name: "Chậm", distance: 12_000, time: 1_500, stepText: "Đường Láng")

        let scores = scorer.score([slow, fast])
        XCTAssertEqual(scores.count, 2)
        XCTAssertEqual(scores.first?.routeID, fast.id)
        XCTAssertGreaterThan(scores[0].total, scores[1].total)
        XCTAssertFalse(scores[0].reasons.isEmpty)
    }

    func testMotorcycleAvoidsExpresswayRoute() {
        let scorer = RouteScorer(database: AlertDatabase(alerts: []))
        let highway = makeRoute(name: "Cao tốc", distance: 10_000, time: 500,
                                stepText: "Đi vào đường cao tốc")
        let city = makeRoute(name: "Phố", distance: 12_000, time: 900, stepText: "Đường Láng")

        let scores = scorer.score([highway, city])
        XCTAssertEqual(scores.first?.routeID, city.id)
    }

    func testLocalAdviceMentionsRoute() {
        let scorer = RouteScorer(database: AlertDatabase(alerts: []))
        let routes = [makeRoute(name: "Tuyến A", distance: 5_000, time: 600, stepText: "Đường Láng"),
                      makeRoute(name: "Tuyến B", distance: 7_000, time: 900, stepText: "Đường Láng")]
        let scores = scorer.score(routes)
        let advice = AIRoutePlanner.localAdvice(routes: routes, scores: scores)
        XCTAssertNotNil(advice)
        XCTAssertTrue(advice?.contains("Tuyến A") ?? false)
    }
}

final class OSMServiceTests: XCTestCase {

    func testParsesSpeedLimits() {
        XCTAssertEqual(OSMAlertService.parseLimit("50"), 50)
        XCTAssertEqual(OSMAlertService.parseLimit("60 km/h"), 60)
        XCTAssertNil(OSMAlertService.parseLimit("none"))
        XCTAssertNil(OSMAlertService.parseLimit("5"))
        XCTAssertNil(OSMAlertService.parseLimit(nil))
    }

    func testBoundingBoxCoversRoute() {
        let box = OSMAlertService.boundingBox([
            CLLocationCoordinate2D(latitude: 21.0, longitude: 105.0),
            CLLocationCoordinate2D(latitude: 21.1, longitude: 105.2)
        ])
        let unwrapped = try? XCTUnwrap(box)
        XCTAssertNotNil(unwrapped)
        XCTAssertLessThan(unwrapped?.south ?? 0, 21.0)
        XCTAssertGreaterThan(unwrapped?.north ?? 0, 21.1)
        XCTAssertLessThan(unwrapped?.west ?? 0, 105.0)
        XCTAssertGreaterThan(unwrapped?.east ?? 0, 105.2)
    }

    func testConvertsNodeToCamera() {
        let element = OSMElement(type: "node", id: 42, lat: 21.02, lon: 105.85,
                                 tags: ["highway": "speed_camera"], geometry: nil)
        let alert = OSMAlertService.alert(from: element)
        XCTAssertEqual(alert?.kind, .speedCamera)
        XCTAssertEqual(alert?.id, "osm-node-42")
    }

    func testConvertsWayToSpeedZone() {
        let element = OSMElement(type: "way", id: 7, lat: nil, lon: nil,
                                 tags: ["maxspeed": "80", "highway": "trunk"],
                                 geometry: [OSMPoint(lat: 21.0, lon: 105.0),
                                            OSMPoint(lat: 21.01, lon: 105.0),
                                            OSMPoint(lat: 21.02, lon: 105.0)])
        let alert = OSMAlertService.alert(from: element)
        XCTAssertEqual(alert?.kind, .speedZone)
        XCTAssertEqual(alert?.speedLimit, 80)
        XCTAssertEqual(alert?.length ?? 0, 2_224, accuracy: 40)
    }
}

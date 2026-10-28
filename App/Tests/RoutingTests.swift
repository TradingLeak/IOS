import XCTest
import MapKit
@testable import VietMap

final class TravelModeTests: XCTestCase {

    func testMotorcycleIsFirstClassMode() {
        XCTAssertEqual(TravelMode.parse("xe máy"), .motorcycle)
        XCTAssertEqual(TravelMode.parse("đi xe máy"), .motorcycle)
        XCTAssertEqual(TravelMode.parse("motorbike"), .motorcycle)
        XCTAssertEqual(TravelMode.parse("motorcycle"), .motorcycle)
        XCTAssertEqual(TravelMode.parse("ô tô"), .automobile)
        XCTAssertEqual(TravelMode.parse("xe hơi"), .automobile)
        XCTAssertEqual(TravelMode.parse("đi bộ"), .walking)
        XCTAssertEqual(TravelMode.parse("xe buýt"), .transit)
        XCTAssertNil(TravelMode.parse("máy bay"))
    }

    func testMotorcycleUsesCarTransportTypeAsFallback() {
        XCTAssertEqual(TravelMode.motorcycle.transportType, .automobile)
        XCTAssertFalse(TravelMode.motorcycle.hasNativeProfile)
        XCTAssertTrue(TravelMode.automobile.hasNativeProfile)
    }

    func testAllModesHaveUniqueTitles() {
        let titles = TravelMode.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertTrue(titles.contains("Xe máy"))
    }
}

final class MotorcycleRoutingTests: XCTestCase {

    private func makeRoute(name: String,
                           distance: Double,
                           time: Double,
                           stepText: String,
                           mode: TravelMode = .motorcycle) -> RouteOption {
        let coordinates = [CLLocationCoordinate2D(latitude: 21.0, longitude: 105.0),
                           CLLocationCoordinate2D(latitude: 21.05, longitude: 105.05)]
        let steps = [RouteStep(instruction: stepText, distance: distance,
                               endCoordinate: coordinates[1])]
        return RouteOption(name: name,
                           distance: distance,
                           expectedTravelTime: time,
                           coordinates: coordinates,
                           steps: steps,
                           mode: mode,
                           advisoryNotices: [])
    }

    func testAdjustFiltersExpresswayRoute() {
        let highway = makeRoute(name: "Cao tốc", distance: 10_000, time: 600,
                                stepText: "Đi vào đường cao tốc Pháp Vân - Cầu Giẽ")
        let city = makeRoute(name: "Phố", distance: 11_000, time: 900, stepText: "Đi trên Đường Láng")

        let adjusted = RoutingService.adjustForMotorcycle([highway, city])
        XCTAssertEqual(adjusted.count, 1)
        XCTAssertEqual(adjusted.first?.name, "Phố")
        XCTAssertEqual(adjusted.first?.isEstimatedProfile, true)
        XCTAssertEqual(adjusted.first?.provider, .apple)
    }

    func testAdjustKeepsAllRoutesWhenAllUseExpressway() {
        let first = makeRoute(name: "Cao tốc 1", distance: 10_000, time: 600,
                              stepText: "Đường cao tốc")
        let second = makeRoute(name: "Cao tốc 2", distance: 12_000, time: 700,
                               stepText: "Đường cao tốc")
        let adjusted = RoutingService.adjustForMotorcycle([first, second])
        XCTAssertEqual(adjusted.count, 2)
        XCTAssertTrue(adjusted.allSatisfy { $0.isEstimatedProfile })
        XCTAssertTrue(adjusted.allSatisfy { route in
            route.advisoryNotices.contains { $0.contains("cao tốc") }
        })
    }

    func testAdjustKeepsNonMotorcycleRoutesUntouched() {
        let car = makeRoute(name: "Ô tô", distance: 10_000, time: 600,
                            stepText: "Đường Láng", mode: .automobile)
        let adjusted = RoutingService.adjustForMotorcycle([car])
        XCTAssertEqual(adjusted.count, 1)
        XCTAssertEqual(adjusted.first?.expectedTravelTime, 600)
        XCTAssertFalse(adjusted.first?.isEstimatedProfile ?? true)
    }

    func testSanitizeDropsDuplicateAndTinyRoutes() {
        let good = makeRoute(name: "A", distance: 5_000, time: 600, stepText: "Đường Láng")
        let duplicate = makeRoute(name: "B", distance: 5_000, time: 600, stepText: "Đường Láng")
        let tiny = makeRoute(name: "C", distance: 0.4, time: 10, stepText: "Đường Láng")

        let result = RoutingService.sanitize([good, duplicate, tiny])
        XCTAssertEqual(result.count, 1)
    }

    func testMotorcycleWarningWhenExpressway() {
        let route = makeRoute(name: "Cao tốc", distance: 10_000, time: 600,
                              stepText: "Đường cao tốc")
        XCTAssertNotNil(AlertEngine.motorcycleWarning(for: route))

        let city = makeRoute(name: "Phố", distance: 10_000, time: 600, stepText: "Đường Láng")
        XCTAssertNil(AlertEngine.motorcycleWarning(for: city))
    }
}

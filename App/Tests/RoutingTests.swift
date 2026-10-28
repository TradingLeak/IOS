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

        let result = RoutingService.sanitizeVietMap([good, duplicate, tiny])
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

final class VietMapParsingTests: XCTestCase {

    func testParsesPathIntoRouteOption() throws {
        let instruction = VietMapInstruction(distance: 1_200,
                                            text: "Rẽ phải vào Quốc lộ 1A",
                                            streetName: "Quốc lộ 1A",
                                            sign: 2,
                                            interval: [0, 1])
        let path = VietMapPath(distance: 5_500,
                               time: 720_000,
                               points: "_p~iF~ps|U_ulLnnqC",
                               pointsEncoded: true,
                               instructions: [instruction],
                               tollCost: 0)

        let route = try XCTUnwrap(VietMapRoutingService.makeOption(path, index: 0, mode: .motorcycle))
        XCTAssertEqual(route.provider, .vietmap)
        XCTAssertEqual(route.distance, 5_500, accuracy: 0.01)
        XCTAssertEqual(route.expectedTravelTime, 720, accuracy: 0.01)
        XCTAssertEqual(route.coordinates.count, 2)
        XCTAssertEqual(route.steps.count, 1)
        XCTAssertEqual(route.steps.first?.roadName, "Quốc lộ 1A")
        XCTAssertEqual(route.mode, .motorcycle)
    }

    func testParsesTollCostIntoNotice() throws {
        let path = VietMapPath(distance: 80_000,
                               time: 3_600_000,
                               points: "_p~iF~ps|U_ulLnnqC",
                               pointsEncoded: true,
                               instructions: [],
                               tollCost: 59_000)
        let route = try XCTUnwrap(VietMapRoutingService.makeOption(path, index: 0, mode: .motorcycle))
        XCTAssertEqual(route.tollCost, 59_000)
        XCTAssertFalse(route.advisoryNotices.isEmpty)
        XCTAssertNotNil(route.tollCostText)
    }

    func testRejectsEmptyGeometry() {
        let path = VietMapPath(distance: 100, time: 1_000, points: "", pointsEncoded: true,
                               instructions: [], tollCost: nil)
        XCTAssertNil(VietMapRoutingService.makeOption(path, index: 0, mode: .motorcycle))
    }

    func testDecodesServerResponseShape() throws {
        let json = """
        {
          "code": "OK",
          "paths": [
            {
              "distance": 194465.7,
              "time": 10854078,
              "points": "_p~iF~ps|U_ulLnnqC",
              "points_encoded": true,
              "instructions": [
                {"distance": 3590.7, "sign": 0, "interval": [0, 1], "text": "", "street_name": "Quốc Lộ 46"}
              ],
              "toll_cost": 59000
            }
          ]
        }
        """
        let response = try JSONDecoder().decode(VietMapRouteResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.code, "OK")
        let path = try XCTUnwrap(response.paths?.first)
        XCTAssertEqual(path.tollCost, 59_000)
        XCTAssertEqual(path.instructions?.first?.streetName, "Quốc Lộ 46")

        let route = try XCTUnwrap(VietMapRoutingService.makeOption(path, index: 0, mode: .motorcycle))
        XCTAssertEqual(route.expectedTravelTime, 10_854, accuracy: 1)
    }
}

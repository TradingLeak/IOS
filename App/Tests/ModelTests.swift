import XCTest
import MapKit
@testable import VietMap

final class FormatTests: XCTestCase {

    func testDistanceFormatting() {
        XCTAssertEqual(Format.distance(0), "0 m")
        XCTAssertEqual(Format.distance(850), "850 m")
        XCTAssertEqual(Format.distance(1234), "1,2 km")
        XCTAssertEqual(Format.distance(12345), "12 km")
    }

    func testDurationFormatting() {
        XCTAssertEqual(Format.duration(30), "dưới 1 phút")
        XCTAssertEqual(Format.duration(60), "1 phút")
        XCTAssertEqual(Format.duration(900), "15 phút")
        XCTAssertEqual(Format.duration(3600), "1 giờ")
        XCTAssertEqual(Format.duration(3900), "1 giờ 5 phút")
    }

    func testInvalidValuesDoNotCrash() {
        XCTAssertEqual(Format.distance(.nan), "—")
        XCTAssertEqual(Format.duration(-1), "—")
    }
}

final class RouteOptionTests: XCTestCase {

    private func makeRoute(steps: Int) -> RouteOption {
        let coordinates = [CLLocationCoordinate2D(latitude: 21.03, longitude: 105.85),
                           CLLocationCoordinate2D(latitude: 21.05, longitude: 105.83)]
        let routeSteps = (0..<steps).map { index in
            RouteStep(instruction: "Bước \(index)", distance: 100, endCoordinate: coordinates[1])
        }
        return RouteOption(name: "Tuyến chính",
                           distance: 5200,
                           expectedTravelTime: 900,
                           coordinates: coordinates,
                           steps: routeSteps,
                           mode: .automobile,
                           advisoryNotices: [])
    }

    func testFormattedValues() {
        let route = makeRoute(steps: 3)
        XCTAssertEqual(route.formattedDistance, "5,2 km")
        XCTAssertEqual(route.formattedDuration, "15 phút")
        XCTAssertGreaterThan(route.averageSpeed, 0)
    }

    func testLocalSummaryMentionsEndpoints() {
        let summary = RouteInsight.summary(route: makeRoute(steps: 6),
                                           originName: "Cầu Giấy",
                                           destinationName: "Hồ Tây")
        XCTAssertTrue(summary.contains("Cầu Giấy"))
        XCTAssertTrue(summary.contains("Hồ Tây"))
        XCTAssertTrue(summary.contains("5,2 km"))
    }

    func testArrivalFormatting() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Format.arrival(after: 3_600, from: now)?.count, 5)
        XCTAssertNil(Format.arrival(after: 0))
        XCTAssertEqual(Format.remaining(600), "10 phút")
    }

    func testStepSymbols() {
        let left = RouteStep(instruction: "Rẽ trái vào phố Huế", distance: 50,
                             endCoordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105))
        XCTAssertEqual(left.symbol, "arrow.turn.up.left")

        let arrive = RouteStep(instruction: "Đến nơi", distance: 0,
                               endCoordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105))
        XCTAssertEqual(arrive.symbol, "flag.checkered")
    }
}

final class PlacesStoreTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "vietmap.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRecentsAreStoredWithoutDuplicates() {
        let store = PlacesStore(defaults: defaults)
        let place = Place(name: "Hồ Tây", subtitle: "Hà Nội", latitude: 21.055, longitude: 105.82)

        store.addRecent(place)
        store.addRecent(place)

        XCTAssertEqual(store.recents().count, 1)
        XCTAssertEqual(store.recents().first?.name, "Hồ Tây")
    }

    func testFavoritesToggle() {
        let store = PlacesStore(defaults: defaults)
        let place = Place(name: "Bến Thành", subtitle: "TP.HCM", latitude: 10.7725, longitude: 106.6980)

        XCTAssertTrue(store.toggleFavorite(place))
        XCTAssertTrue(store.isFavorite(place))
        XCTAssertEqual(store.favorites().count, 1)

        XCTAssertFalse(store.toggleFavorite(place))
        XCTAssertFalse(store.isFavorite(place))
        XCTAssertTrue(store.favorites().isEmpty)
    }

    func testSamePlaceDetectionUsesDistance() {
        let stored = StoredPlace(place: Place(name: "A", subtitle: "", latitude: 21.0, longitude: 105.0))
        let near = Place(name: "B", subtitle: "", latitude: 21.0001, longitude: 105.0001)
        let far = Place(name: "C", subtitle: "", latitude: 10.0, longitude: 106.0)

        XCTAssertTrue(PlacesStore.isSame(stored, near))
        XCTAssertFalse(PlacesStore.isSame(stored, far))
    }

    func testClearRecentsAndFavorites() {
        let store = PlacesStore(defaults: defaults)
        let place = Place(name: "Đà Lạt", subtitle: "Lâm Đồng", latitude: 11.94, longitude: 108.45)
        store.addRecent(place)
        store.toggleFavorite(place)

        store.clearRecents()
        store.clearFavorites()

        XCTAssertTrue(store.recents().isEmpty)
        XCTAssertTrue(store.favorites().isEmpty)
    }
}

final class PresetTests: XCTestCase {

    func testVietnamPresetCoversCountry() {
        let region = MapPreset.vietnam.region
        XCTAssertLessThan(region.center.latitude, 24)
        XCTAssertGreaterThan(region.center.latitude, 8)
        XCTAssertGreaterThan(region.span.latitudeDelta, 8)
    }

    func testAllCitiesHaveUniqueIdentifiers() {
        let ids = MapPreset.cities.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertFalse(MapPreset.cities.isEmpty)
    }
}

import XCTest
import MapKit
@testable import VietMap

final class MapProviderTests: XCTestCase {
    func testOldInstallDefaultsToAppleMaps() {
        XCTAssertEqual(MapProvider.savedValue(nil), .apple)
        XCTAssertEqual(MapProvider.savedValue("unknown-provider"), .apple)
        XCTAssertEqual(MapProvider.savedValue("openStreetMap"), .openStreetMap)
        XCTAssertEqual(MapProvider.savedValue("apple"), .apple)
    }

    func testXYZToTMSConversion() {
        XCTAssertEqual(OfflineMBTiles.tmsRow(y: 0, z: 0), 0)
        XCTAssertEqual(OfflineMBTiles.tmsRow(y: 8, z: 5), 23)
        XCTAssertEqual(OfflineMBTiles.tmsRow(y: 524287, z: 19), 0)
        XCTAssertNil(OfflineMBTiles.tmsRow(y: -1, z: 5))
        XCTAssertNil(OfflineMBTiles.tmsRow(y: 32, z: 5))
        XCTAssertNil(OfflineMBTiles.tmsRow(y: 0, z: -1))
        XCTAssertNil(OfflineMBTiles.tmsRow(y: 0, z: Int.max))
    }

}

@MainActor
final class MapProviderIntegrationTests: XCTestCase {
    func testProviderChoicePersistsWithoutChangingAppleDisplayOptions() {
        let suite = "MapProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.mapProvider, .apple)
        settings.mapTypeIndex = 2
        settings.showTraffic = true
        settings.mapProvider = .openStreetMap
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.mapProvider, .openStreetMap)
        XCTAssertEqual(restored.mapTypeIndex, 2)
        XCTAssertTrue(restored.showTraffic)
        restored.mapProvider = .apple
        XCTAssertEqual(AppSettings(defaults: defaults).mapProvider, .apple)
    }

    func testOSMOverlayConfigurationAndRenderer() {
        let overlay = OpenStreetMapOverlay()
        XCTAssertTrue(overlay.canReplaceMapContent)
        XCTAssertNil(overlay.urlTemplate)
        XCTAssertEqual(overlay.minimumZ, 0)
        XCTAssertEqual(overlay.maximumZ, 19)
        XCTAssertEqual(overlay.tileSize.width, 256)
        let coordinator = MapContainer().makeCoordinator()
        XCTAssertTrue(coordinator.mapView(MKMapView(), rendererFor: overlay) is MKTileOverlayRenderer)
    }

    func testSwitchingProviderPreservesRoutesAndDoesNotDuplicateTiles() {
        let map = MKMapView()
        let coordinator = MapContainer().makeCoordinator()
        var coordinates = [CLLocationCoordinate2D(latitude: 21, longitude: 105.8),
                           CLLocationCoordinate2D(latitude: 21.1, longitude: 105.9)]
        let route = MKPolyline(coordinates: &coordinates, count: coordinates.count)
        map.addOverlay(route, level: .aboveLabels)
        coordinator.updateBasemap(map, provider: .openStreetMap)
        coordinator.updateBasemap(map, provider: .openStreetMap)
        XCTAssertEqual(map.overlays.filter { $0 is MKTileOverlay }.count, 1)
        XCTAssertTrue(map.overlays.contains { ($0 as AnyObject) === route })
        coordinator.updateBasemap(map, provider: .apple)
        XCTAssertEqual(map.overlays.filter { $0 is MKTileOverlay }.count, 0)
        XCTAssertTrue(map.overlays.contains { ($0 as AnyObject) === route })
        coordinator.updateBasemap(map, provider: .openStreetMap)
        XCTAssertEqual(map.overlays.filter { $0 is MKTileOverlay }.count, 1)
    }
}

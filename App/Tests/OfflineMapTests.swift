import XCTest
import SQLite3
import CryptoKit
import MapKit
import CoreGraphics
import ImageIO
@testable import VietMap

private enum OfflineMapFixture {
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!

    static func make(country: String = "VN", pngData: Data? = nil) throws -> (URL, OfflineMapManifest) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mbtiles")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw OfflineMapError.invalidDatabase("fixture") }
        let pngHex = (pngData ?? png).map { String(format: "%02x", $0) }.joined()
        let sql = """
        CREATE TABLE metadata (name TEXT PRIMARY KEY, value TEXT);
        INSERT INTO metadata VALUES ('format','png'),('country_code','\(country)'),('scheme','tms'),
          ('bounds','102,8,110,24'),('minzoom','5'),('maxzoom','5');
        CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB,
          PRIMARY KEY(zoom_level, tile_column, tile_row));
        INSERT INTO tiles VALUES (5,25,18,X'\(pngHex)');
        """
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        sqlite3_close(db)
        guard code == SQLITE_OK else { throw OfflineMapError.invalidDatabase("fixture SQL") }
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (url, OfflineMapManifest(schemaVersion: 1, countryCode: "VN", version: "fixture",
                                        downloadURL: URL(string: "https://example.com/vietnam.mbtiles")!,
                                        byteCount: Int64(data.count), sha256: hash, format: "png",
                                        bounds: [102, 8, 110, 24], minZoom: 5, maxZoom: 5,
                                        attribution: "© OpenStreetMap contributors"))
    }
}

final class OfflineMapTests: XCTestCase {
    func testManifestRejectsOtherCountriesWorldBoundsAndBadHash() throws {
        let (url, manifest) = try OfflineMapFixture.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let encoded = try JSONEncoder().encode(manifest)
        let original = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        let changes: [[String: Any]] = [
            ["countryCode": "US"], ["bounds": [-180, -85, 180, 85]],
            ["sha256": "bad"], ["format": "pbf"], ["minZoom": -1], ["maxZoom": 20],
            ["byteCount": 0], ["downloadURL": "http://example.com/vn.mbtiles"],
            ["downloadURL": "https://tile.openstreetmap.org/1/1/1.png"]
        ]
        for change in changes {
            let modified = original.merging(change) { _, new in new }
            let candidate = try JSONDecoder().decode(OfflineMapManifest.self,
                                                     from: JSONSerialization.data(withJSONObject: modified))
            XCTAssertThrowsError(try candidate.validate())
        }
        XCTAssertNoThrow(try manifest.validate())
    }

    func testTilesOutsideVietnamEnvelopeAreNotServed() {
        let bounds = [102.0, 8, 110, 24]
        XCTAssertTrue(OfflineMBTiles.tileIntersectsBounds(x: 25, y: 13, z: 5, bounds: bounds))
        XCTAssertFalse(OfflineMBTiles.tileIntersectsBounds(x: 1, y: 13, z: 5, bounds: bounds))
        XCTAssertFalse(OfflineMBTiles.tileIntersectsBounds(x: 25, y: 1, z: 5, bounds: bounds))
        XCTAssertFalse(OfflineMBTiles.tileIntersectsBounds(x: 25, y: 13, z: Int.max, bounds: bounds))
    }

    func testOverzoomFindsCorrectParentAndSubtile() {
        let native = OfflineMBTiles.sourceTile(x: 25, y: 13, z: 5, maximumNativeZoom: 13)
        XCTAssertEqual(native?.x, 25)
        XCTAssertEqual(native?.scale, 1)
        let zoomed = OfflineMBTiles.sourceTile(x: 101, y: 55, z: 7, maximumNativeZoom: 5)
        XCTAssertEqual(zoomed?.x, 25)
        XCTAssertEqual(zoomed?.y, 13)
        XCTAssertEqual(zoomed?.z, 5)
        XCTAssertEqual(zoomed?.offsetX, 1)
        XCTAssertEqual(zoomed?.offsetY, 3)
        XCTAssertEqual(zoomed?.scale, 4)
        XCTAssertNil(OfflineMBTiles.sourceTile(x: -1, y: 0, z: 7, maximumNativeZoom: 5))
        XCTAssertNil(OfflineMBTiles.sourceTile(x: 0, y: 0, z: Int.max, maximumNativeZoom: 5))
    }

    func testChecksumAndSizeAreVerified() throws {
        let (url, manifest) = try OfflineMapFixture.make()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNoThrow(try OfflineMBTiles.verifyFile(url, manifest: manifest))
        var data = try Data(contentsOf: url)
        data[data.count - 1] ^= 1
        try data.write(to: url)
        XCTAssertThrowsError(try OfflineMBTiles.verifyFile(url, manifest: manifest))
        try Data([1]).write(to: url)
        XCTAssertThrowsError(try OfflineMBTiles.verifyFile(url, manifest: manifest))
    }

    func testDatabaseRejectsForeignCountryMetadata() throws {
        let (url, manifest) = try OfflineMapFixture.make(country: "US")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try OfflineMBTiles(url: url, manifest: manifest))
    }

    func testTileIsReadFromDiskUsingTMSNotXYZRow() throws {
        let (url, manifest) = try OfflineMapFixture.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try OfflineMBTiles(url: url, manifest: manifest)
        let ready = expectation(description: "local PNG")
        database.tile(x: 25, y: 13, z: 5) { data, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, OfflineMapFixture.png)
            ready.fulfill()
        }
        wait(for: [ready], timeout: 2)
    }

    func testOverzoomProducesValid256PixelPNGFromLocalParent() throws {
        let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8,
                                bytesPerRow: 256 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        let pngData = NSMutableData()
        let output = CGImageDestinationCreateWithData(pngData, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(output, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(output))
        let (url, manifest) = try OfflineMapFixture.make(pngData: pngData as Data)
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try OfflineMBTiles(url: url, manifest: manifest)
        let ready = expectation(description: "overzoom parent PNG")
        database.tile(x: 51, y: 27, z: 6) { data, error in
            XCTAssertNil(error)
            if let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                XCTAssertEqual(image.width, 256)
                XCTAssertEqual(image.height, 256)
            } else { XCTFail("Invalid overzoom PNG") }
            ready.fulfill()
        }
        wait(for: [ready], timeout: 3)
    }

    func testNoDatabaseDoesNotFallbackToNetwork() {
        let overlay = OpenStreetMapOverlay()
        XCTAssertNil(overlay.urlTemplate)
        overlay.loadTile(at: MKTileOverlayPath(x: 25, y: 13, z: 5, contentScaleFactor: 2)) { data, error in
            XCTAssertNil(data)
            XCTAssertNotNil(error)
        }
    }

    func testMissingTileReturnsError() throws {
        let (url, manifest) = try OfflineMapFixture.make()
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try OfflineMBTiles(url: url, manifest: manifest)
        let missing = expectation(description: "missing tile")
        database.tile(x: 26, y: 13, z: 5) { data, error in
            XCTAssertNil(data)
            XCTAssertNotNil(error)
            missing.fulfill()
        }
        wait(for: [missing], timeout: 2)
    }
}

@MainActor
final class OfflineMapStoreTests: XCTestCase {
    func testMissingFileIsNotTreatedAsDownloaded() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflineMapStore(directory: directory)
        await store.restore()
        XCTAssertFalse(store.isReady)
        XCTAssertFalse(store.isBusy)
    }

    func testInstalledReceiptRestoresRealDatabaseAndRemovalRequiresRedownload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (file, manifest) = try OfflineMapFixture.make()
        defer { try? FileManager.default.removeItem(at: file) }
        let name = UUID().uuidString + ".mbtiles"
        try FileManager.default.copyItem(at: file, to: directory.appendingPathComponent(name))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest))
        let receipt: [String: Any] = ["fileName": name, "manifest": json]
        try JSONSerialization.data(withJSONObject: receipt).write(to: directory.appendingPathComponent("installed.json"))
        let store = OfflineMapStore(directory: directory)
        await store.restore()
        XCTAssertTrue(store.isReady)
        XCTAssertNil(store.errorMessage)
        store.remove()
        XCTAssertFalse(store.isReady)
        let reopened = OfflineMapStore(directory: directory)
        await reopened.restore()
        XCTAssertFalse(reopened.isReady)
    }

    func testCorruptReceiptDoesNotMarkMapReady() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{}".utf8).write(to: directory.appendingPathComponent("installed.json"))
        let store = OfflineMapStore(directory: directory)
        await store.restore()
        XCTAssertFalse(store.isReady)
        XCTAssertNotNil(store.errorMessage)
    }
}

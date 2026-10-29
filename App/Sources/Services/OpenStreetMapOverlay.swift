import Foundation
import MapKit

/// OSM chỉ đọc từ gói MBTiles Việt Nam đã tải. Không có fallback tile qua Internet.
final class OpenStreetMapOverlay: MKTileOverlay {
    static let maximumZoom = 19
    static let copyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!
    let database: OfflineMBTiles?

    init(database: OfflineMBTiles? = nil) {
        self.database = database
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: 256, height: 256)
        minimumZ = database?.manifest.minZoom ?? 0
        maximumZ = Self.maximumZoom // Tile native ít chi tiết hơn được phóng ảnh cục bộ.
        canReplaceMapContent = true
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        guard let database else {
            result(nil, OfflineMapError.missingTile)
            return
        }
        database.tile(x: path.x, y: path.y, z: path.z, completion: result)
    }
}

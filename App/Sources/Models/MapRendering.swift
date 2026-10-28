import Foundation
import MapKit
import CoreLocation

/// Một điểm ghim trên bản đồ (điểm đi / điểm đến / điểm dừng / POI).
struct MapPin: Identifiable {
    enum Kind: String {
        case origin
        case destination
        case waypoint
        case poi
        case favorite
        case camera
    }

    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    let kind: Kind

    // MARK: Thông tin riêng cho ghim cảnh báo giao thông

    /// Loại cảnh báo (biển tốc độ, camera đèn đỏ, khu trường học…). `nil` với ghim thường.
    var alertKind: AlertKind? = nil
    /// Giới hạn tốc độ để vẽ biển tròn P.127 ngay trên marker.
    var limit: Int? = nil
    /// 0…3 — mức nguy hiểm quyết định màu marker (0 xám, 1 màu loại, 2 cam, 3 đỏ).
    var severity: Int = 0
    /// Khoảng cách còn lại (mét) khi đang dẫn đường — hiện trong nhãn phụ.
    var distance: Double? = nil
    /// Icon riêng (báo cáo sự cố dùng biểu tượng theo loại thay vì icon cảnh báo chung).
    var glyphSymbol: String? = nil
}

/// Một đường vẽ trên bản đồ (tuyến chính, viền, hoặc tuyến thay thế).
struct MapPolyline: Identifiable {
    enum Style: String {
        case casing
        case primary
        case alternate
    }

    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let style: Style
}

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

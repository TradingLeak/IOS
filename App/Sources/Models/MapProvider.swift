import Foundation

/// Nguồn bản đồ nền, tách biệt với dịch vụ tìm kiếm/tính tuyến Apple.
enum MapProvider: String, CaseIterable, Identifiable {
    case apple
    case openStreetMap

    var id: String { rawValue }
    var title: String {
        switch self {
        case .apple: return "Apple Maps (MapKit)"
        case .openStreetMap: return "OpenStreetMap"
        }
    }

    static func savedValue(_ rawValue: String?) -> MapProvider {
        rawValue.flatMap(MapProvider.init(rawValue:)) ?? .apple
    }
}

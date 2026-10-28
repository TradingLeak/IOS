import Foundation
import CoreLocation

/// Hình học tuyến đường — hàm thuần, test trực tiếp được.
/// Dùng cho phát hiện "đi lệch tuyến" (off-route) khi đang điều hướng.
enum RouteGeometry {

    /// Khoảng cách nhỏ nhất (mét) từ `point` tới polyline.
    /// - Returns: `nil` nếu polyline rỗng.
    static func minDistance(from point: CLLocationCoordinate2D,
                            to polyline: [CLLocationCoordinate2D]) -> Double? {
        if polyline.isEmpty { return nil }
        if polyline.count == 1 { return SpeedmapMath.meters(point, polyline[0]) }
        var best = Double.infinity
        for i in 0..<(polyline.count - 1) {
            let d = SpeedmapMath.pointToSegmentM(point, polyline[i], polyline[i + 1])
            if d < best { best = d }
        }
        return best
    }

    /// Off-route nếu khoảng cách tới tuyến > `thresholdM`.
    static func isOffRoute(_ point: CLLocationCoordinate2D,
                           from polyline: [CLLocationCoordinate2D],
                           thresholdM: Double = 70) -> Bool {
        guard let d = minDistance(from: point, to: polyline) else { return false }
        return d > thresholdM
    }
}

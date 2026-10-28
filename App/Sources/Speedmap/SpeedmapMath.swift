import Foundation
import CoreLocation

// MARK: - Toạ độ & cảnh báo — hàm toán học thuần (test trực tiếp được)
//
// WGS84 xấp xỉ phẳng (equirectangular) quanh điểm quan tâm — đủ chính xác
// cấp mét trong bán kính <2 km, đúng chi phí tính trên firmware VietHUD.

enum SpeedmapMath {
    // MARK: Khoảng cách & phương vị

    /// Khoảng cách haversine (mét).
    static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Phương vị từ `a` sang `b` (0° = Bắc, thuận kim đồng hồ).
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var deg = atan2(y, x) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    /// Sai số góc tuyệt đối trong khoảng 0…180.
    static func angularDiff(_ a: Double, _ b: Double) -> Double {
        var d = abs(a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d = 360 - d }
        return d
    }

    // MARK: Dịch chuyển toạ độ

    /// Điểm cách `distanceM` mét trên hướng `bearingDeg`.
    static func coordinate(_ from: CLLocationCoordinate2D,
                           moving distanceM: Double,
                           bearingDeg: Double) -> CLLocationCoordinate2D {
        let r = 6_371_000.0
        let delta = distanceM / r
        let theta = bearingDeg * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(delta) + cos(lat1) * sin(delta) * cos(theta))
        let lon2 = lon1 + atan2(sin(theta) * sin(delta) * cos(lat1),
                                cos(delta) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi,
                                      longitude: lon2 * 180 / .pi)
    }

    // MARK: Khoảng cách điểm → đoạn thẳng

    /// Khoảng cách mét từ `p` tới đoạn `a`–`b` (chiếu trực giao, dệt phẳng local).
    static func pointToSegmentM(_ p: CLLocationCoordinate2D,
                                _ a: CLLocationCoordinate2D,
                                _ b: CLLocationCoordinate2D) -> Double {
        let mLat = 110_540.0
        let mLon = 111_320.0 * cos(p.latitude * .pi / 180)
        // Toạ độ mét relative tới p (p = gốc tọa độ).
        let ax = (a.longitude - p.longitude) * mLon
        let ay = (a.latitude - p.latitude) * mLat
        let bx = (b.longitude - p.longitude) * mLon
        let by = (b.latitude - p.latitude) * mLat
        let dx = bx - ax
        let dy = by - ay
        let len2 = dx * dx + dy * dy
        let t: Double
        if len2 < 1e-9 {
            t = 0
        } else {
            t = max(0, min(1, -(ax * dx + ay * dy) / len2))
        }
        let cx = ax + t * dx
        let cy = ay + t * dy
        return (cx * cx + cy * cy).squareRoot()
    }

    // MARK: Khoảng cách cảnh báo (port từ firmware SpeedLimitManager.cpp)

    /// `D_warn = clamp(v × 4.5, 100 m, 400 m)` — lead-time ~15s, cap 400 m.
    static func dynamicWarnDistance(speedKmh: Double) -> Double {
        let v = max(0, speedKmh)
        return min(max(v * 4.5, 100), 400)
    }

    /// Biển báo quy phạm (khu dân cư, cấm vượt, thu phí…) — cố định 350 m
    /// (kSignWarnDistanceM bên firmware).
    static let signWarnDistanceM: Double = 350
}

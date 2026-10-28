import Foundation
import CoreLocation

// MARK: - Tính toán toạ độ

/// Các phép tính toạ độ dùng chung (không phụ thuộc MapKit để test được trên simulator).
enum Geo {
    static let metersPerDegreeLatitude = 111_320.0

    static func metersPerDegreeLongitude(at latitude: Double) -> Double {
        let cosine = cos(latitude * Double.pi / 180)
        return max(1_000.0, metersPerDegreeLatitude * cosine)
    }

    /// Khoảng cách trên mặt đất (haversine, mét).
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        guard CLLocationCoordinate2DIsValid(a), CLLocationCoordinate2DIsValid(b) else { return .infinity }
        let earthRadius = 6_371_000.0
        let lat1 = a.latitude * Double.pi / 180
        let lat2 = b.latitude * Double.pi / 180
        let deltaLat = (b.latitude - a.latitude) * Double.pi / 180
        let deltaLng = (b.longitude - a.longitude) * Double.pi / 180

        let haversine = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2)
        return 2 * earthRadius * asin(min(1, sqrt(max(0, haversine))))
    }

    /// Góc phương vị từ `a` tới `b` (0 = Bắc, 90 = Đông).
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * Double.pi / 180
        let lat2 = b.latitude * Double.pi / 180
        let deltaLng = (b.longitude - a.longitude) * Double.pi / 180
        let y = sin(deltaLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLng)
        let degrees = atan2(y, x) * 180 / Double.pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Chênh lệch giữa hai hướng, luôn trong 0...180.
    static func angleDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return raw > 180 ? 360 - raw : raw
    }

    static func interpolate(_ a: CLLocationCoordinate2D,
                            _ b: CLLocationCoordinate2D,
                            fraction: Double) -> CLLocationCoordinate2D {
        let t = min(max(fraction, 0), 1)
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                      longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// Điểm cách `origin` một khoảng `meters` theo hướng `bearing` (0 = Bắc).
    static func offset(_ origin: CLLocationCoordinate2D,
                       meters: Double,
                       bearing: Double) -> CLLocationCoordinate2D {
        let radians = bearing * Double.pi / 180
        let deltaLat = meters * cos(radians) / metersPerDegreeLatitude
        let deltaLng = meters * sin(radians) / metersPerDegreeLongitude(at: origin.latitude)
        return CLLocationCoordinate2D(latitude: origin.latitude + deltaLat,
                                      longitude: origin.longitude + deltaLng)
    }
}

// MARK: - Hình học tuyến đường

/// Tuyến đường kèm khoảng cách luỹ kế — dùng để biết "còn bao xa tới cảnh báo".
struct RouteGeometry {
    struct Projection {
        /// Khoảng cách từ đầu tuyến tới điểm chiếu (mét).
        let along: Double
        /// Khoảng cách vuông góc tới tuyến (mét).
        let offset: Double
        let segmentIndex: Int
    }

    let coordinates: [CLLocationCoordinate2D]
    private let cumulative: [Double]

    init(coordinates: [CLLocationCoordinate2D]) {
        let valid = coordinates.filter { CLLocationCoordinate2DIsValid($0) }
        self.coordinates = valid

        var running = 0.0
        var distances: [Double] = []
        distances.reserveCapacity(valid.count)
        for (index, coordinate) in valid.enumerated() {
            if index > 0 {
                running += Geo.distance(valid[index - 1], coordinate)
            }
            distances.append(running)
        }
        self.cumulative = distances
    }

    var isEmpty: Bool { coordinates.count < 2 }

    var totalDistance: Double { cumulative.last ?? 0 }

    /// Toạ độ tại khoảng cách `distance` tính từ đầu tuyến.
    func point(at distance: Double) -> CLLocationCoordinate2D? {
        guard let first = coordinates.first else { return nil }
        guard coordinates.count > 1, totalDistance > 0 else { return first }

        let clamped = min(max(distance, 0), totalDistance)
        var low = 0
        var high = cumulative.count - 1
        while low + 1 < high {
            let middle = (low + high) / 2
            if cumulative[middle] <= clamped {
                low = middle
            } else {
                high = middle
            }
        }

        let segmentLength = cumulative[high] - cumulative[low]
        let fraction = segmentLength > 0 ? (clamped - cumulative[low]) / segmentLength : 0
        return Geo.interpolate(coordinates[low], coordinates[high], fraction: fraction)
    }

    func bearing(at distance: Double) -> Double? {
        guard coordinates.count > 1 else { return nil }
        let clamped = min(max(distance, 0), max(0, totalDistance - 1))
        guard let start = point(at: clamped),
              let end = point(at: min(totalDistance, clamped + 12)) else { return nil }
        guard Geo.distance(start, end) > 0.5 else { return nil }
        return Geo.bearing(from: start, to: end)
    }

    /// Chiếu một toạ độ lên tuyến: trả về khoảng cách dọc tuyến + lệch ngang.
    func projection(of coordinate: CLLocationCoordinate2D) -> Projection? {
        guard coordinates.count >= 2 else {
            guard let only = coordinates.first else { return nil }
            return Projection(along: 0, offset: Geo.distance(only, coordinate), segmentIndex: 0)
        }

        let longitudeScale = Geo.metersPerDegreeLongitude(at: coordinate.latitude)
        let latitudeScale = Geo.metersPerDegreeLatitude

        var best = Projection(along: 0, offset: .infinity, segmentIndex: 0)

        for index in 0..<(coordinates.count - 1) {
            let start = coordinates[index]
            let end = coordinates[index + 1]

            let startX = (start.longitude - coordinate.longitude) * longitudeScale
            let startY = (start.latitude - coordinate.latitude) * latitudeScale
            let endX = (end.longitude - coordinate.longitude) * longitudeScale
            let endY = (end.latitude - coordinate.latitude) * latitudeScale

            let segmentX = endX - startX
            let segmentY = endY - startY
            let lengthSquared = segmentX * segmentX + segmentY * segmentY

            var fraction = 0.0
            if lengthSquared > 0.0001 {
                fraction = -(startX * segmentX + startY * segmentY) / lengthSquared
                fraction = min(max(fraction, 0), 1)
            }

            let pointX = startX + segmentX * fraction
            let pointY = startY + segmentY * fraction
            let offset = (pointX * pointX + pointY * pointY).squareRoot()

            if offset < best.offset {
                let segmentLength = cumulative[min(index + 1, cumulative.count - 1)]
                    - cumulative[min(index, cumulative.count - 1)]
                best = Projection(along: cumulative[min(index, cumulative.count - 1)] + segmentLength * fraction,
                                  offset: offset,
                                  segmentIndex: index)
            }
        }

        return best
    }

    func offsetFromRoute(_ coordinate: CLLocationCoordinate2D) -> Double {
        projection(of: coordinate)?.offset ?? .infinity
    }
}

// MARK: - Giải mã polyline

/// Giải mã "Google polyline 5" (VietMap Route v4 trả về định dạng này).
enum PolylineCoder {

    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        let bytes = Array(encoded.utf8)
        var coordinates: [CLLocationCoordinate2D] = []
        var index = 0
        var latitude = 0
        var longitude = 0

        while index < bytes.count {
            guard let latDelta = decodeValue(bytes, index: &index) else { break }
            guard let lngDelta = decodeValue(bytes, index: &index) else { break }
            latitude += latDelta
            longitude += lngDelta
            coordinates.append(CLLocationCoordinate2D(latitude: Double(latitude) / 100_000.0,
                                                      longitude: Double(longitude) / 100_000.0))
        }

        return coordinates
    }

    private static func decodeValue(_ bytes: [UInt8], index: inout Int) -> Int? {
        var result = 0
        var shift = 0
        var byte = 0

        repeat {
            guard index < bytes.count else { return nil }
            byte = Int(bytes[index]) - 63
            guard byte >= 0 else { return nil }
            index += 1
            result |= (byte & 0x1f) << shift
            shift += 5
        } while byte >= 0x20

        return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
    }
}

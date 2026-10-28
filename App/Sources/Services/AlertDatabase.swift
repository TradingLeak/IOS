import Foundation
import CoreLocation

/// Kho cảnh báo trong bộ nhớ + chỉ mục lưới (0,01° ≈ 1,1 km) để truy vấn nhanh
/// mà không cần cơ sở dữ liệu hay thư viện ngoài.
struct AlertDatabase {

    private(set) var alerts: [RoadAlert] = []
    private(set) var sources: [AlertSource] = []
    private(set) var generatedAt: String?
    private(set) var datasetVersion: String?

    private var index: [String: [Int]] = [:]
    private let cellSize: Double

    // MARK: - Khởi tạo

    init(alerts: [RoadAlert], sources: [AlertSource] = [], generatedAt: String? = nil,
         version: String? = nil, cellSize: Double = 0.01) {
        self.cellSize = max(0.001, cellSize)
        self.sources = sources
        self.generatedAt = generatedAt
        self.datasetVersion = version

        var seen = Set<String>()
        var accepted: [RoadAlert] = []
        accepted.reserveCapacity(alerts.count)

        for alert in alerts {
            guard alert.hasValidCoordinate else { continue }
            guard !seen.contains(alert.id) else { continue }
            seen.insert(alert.id)
            accepted.append(alert)
        }

        self.alerts = accepted
        self.index = Self.buildIndex(accepted, cellSize: self.cellSize)
    }

    private static func buildIndex(_ alerts: [RoadAlert], cellSize: Double) -> [String: [Int]] {
        var result: [String: [Int]] = [:]
        for (index, alert) in alerts.enumerated() {
            let key = cellKey(latitude: alert.latitude, longitude: alert.longitude, cellSize: cellSize)
            result[key, default: []].append(index)
        }
        return result
    }

    private static func cellKey(latitude: Double, longitude: Double, cellSize: Double) -> String {
        let latCell = Int((latitude / cellSize).rounded(.down))
        let lngCell = Int((longitude / cellSize).rounded(.down))
        return "\(latCell):\(lngCell)"
    }

    // MARK: - Nạp dữ liệu

    static func decode(_ data: Data) throws -> AlertDataset {
        let decoder = JSONDecoder()
        return try decoder.decode(AlertDataset.self, from: data)
    }

    /// Nạp bộ dữ liệu nhúng trong app (`App/Resources/Data/vn_alerts.json`).
    static func loadBundled(bundle: Bundle = .main) -> AlertDatabase {
        guard let url = bundle.url(forResource: "vn_alerts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dataset = try? decode(data) else {
            return AlertDatabase(alerts: [])
        }
        return AlertDatabase(alerts: dataset.alerts,
                             sources: dataset.sources ?? [],
                             generatedAt: dataset.generatedAt,
                             version: dataset.version)
    }

    static func fromJSON(_ data: Data) throws -> (database: AlertDatabase, warnings: [String]) {
        let dataset = try decode(data)
        let valid = dataset.alerts.filter { $0.hasValidCoordinate }
        let skipped = dataset.alerts.count - valid.count
        var warnings: [String] = []
        if skipped > 0 {
            warnings.append("Bỏ qua \(skipped) mục có toạ độ không hợp lệ.")
        }
        let database = AlertDatabase(alerts: dataset.alerts,
                                     sources: dataset.sources ?? [],
                                     generatedAt: dataset.generatedAt,
                                     version: dataset.version)
        return (database, warnings)
    }

    // MARK: - Truy vấn

    var count: Int { alerts.count }

    var cameraCount: Int { alerts.filter(\.kind.isCamera).count }

    var isEmpty: Bool { alerts.isEmpty }

    func alert(id: String) -> RoadAlert? {
        alerts.first { $0.id == id }
    }

    /// Các cảnh báo trong bán kính `radius` mét quanh một toạ độ.
    func nearby(around coordinate: CLLocationCoordinate2D,
                radius: Double = 1_500,
                kinds: Set<AlertKind>? = nil,
                limit: Int = 200) -> [RoadAlert] {
        guard !alerts.isEmpty, CLLocationCoordinate2DIsValid(coordinate) else { return [] }

        let candidates = candidateIndices(around: coordinate, radius: radius)
        let center = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        var found: [(alert: RoadAlert, distance: Double)] = []
        for candidate in candidates {
            let alert = alerts[candidate]
            if let kinds, !kinds.contains(alert.kind) { continue }
            let distance = center.distance(from: alert.location)
            guard distance <= radius else { continue }
            found.append((alert, distance))
        }

        found.sort { $0.distance < $1.distance }
        return found.prefix(limit).map(\.alert)
    }

    func nearest(to coordinate: CLLocationCoordinate2D,
                 maxDistance: Double = 500,
                 kinds: Set<AlertKind>? = nil) -> RoadAlert? {
        nearby(around: coordinate, radius: maxDistance, kinds: kinds, limit: 1).first
    }

    /// Cảnh báo dọc tuyến, đã tính khoảng cách dọc tuyến và hướng đi.
    func alongRoute(_ geometry: RouteGeometry,
                    corridor: Double = 90,
                    kinds: Set<AlertKind>? = nil,
                    limit: Int = 400) -> [ActiveAlert] {
        guard !alerts.isEmpty, !geometry.isEmpty else { return [] }

        let samples = sampleCoordinates(geometry, spacing: 40)
        var candidateSet = Set<Int>()
        for sample in samples {
            for candidate in candidateIndices(around: sample, radius: corridor + 60) {
                candidateSet.insert(candidate)
            }
        }

        var results: [ActiveAlert] = []
        for candidate in candidateSet {
            let alert = alerts[candidate]
            if let kinds, !kinds.contains(alert.kind) { continue }

            guard let projection = geometry.projection(of: alert.coordinate) else { continue }

            // Vùng tốc độ: mốc là điểm bắt đầu, kéo dài `length` mét theo chiều đi.
            let isZone = alert.kind == .speedZone && (alert.length ?? 0) > 0
            var startAlong = projection.along
            var offset = projection.offset

            if isZone, let length = alert.length {
                // Mốc = điểm bắt đầu vùng; vùng kéo dài `length` mét theo chiều đi.
                guard offset <= corridor + 60 else { continue }
                startAlong = max(0, projection.along)
                if startAlong > geometry.totalDistance { continue }
                if length < 1 { continue }
            } else {
                guard offset <= corridor else { continue }
            }

            if let bearing = alert.bearing {
                let tolerance = isZone ? 65.0 : 55.0
                if let routeBearing = geometry.bearing(at: startAlong) {
                    guard Geo.angleDifference(bearing, routeBearing) <= tolerance else { continue }
                }
            }

            let warn = ActiveAlert.warnDistance(forSpeed: nil,
                                                min: 150,
                                                max: max(300, corridor * 3))
            results.append(ActiveAlert(alert: alert,
                                       distance: startAlong,
                                       warnDistance: warn,
                                       distanceAlongRoute: startAlong))
        }

        results.sort { $0.distanceAlongRoute < $1.distanceAlongRoute }
        return Array(results.prefix(limit))
    }

    func sampleCoordinates(_ geometry: RouteGeometry, spacing: Double) -> [CLLocationCoordinate2D] {
        let step = max(10, spacing)
        var samples: [CLLocationCoordinate2D] = []
        var distance = 0.0
        while distance <= geometry.totalDistance {
            if let point = geometry.point(at: distance) { samples.append(point) }
            distance += step
        }
        if let last = geometry.coordinates.last { samples.append(last) }
        return samples
    }

    // MARK: - Chỉ mục

    private func candidateIndices(around coordinate: CLLocationCoordinate2D, radius: Double) -> [Int] {
        guard CLLocationCoordinate2DIsValid(coordinate), radius > 0 else { return [] }

        let latitudeDelta = radius / Geo.metersPerDegreeLatitude
        let longitudeDelta = radius / Geo.metersPerDegreeLongitude(at: coordinate.latitude)

        let minLatCell = Int(((coordinate.latitude - latitudeDelta) / cellSize).rounded(.down))
        let maxLatCell = Int(((coordinate.latitude + latitudeDelta) / cellSize).rounded(.down))
        let minLngCell = Int(((coordinate.longitude - longitudeDelta) / cellSize).rounded(.down))
        let maxLngCell = Int(((coordinate.longitude + longitudeDelta) / cellSize).rounded(.down))

        // Chặn trên để tránh treo máy nếu ai đó hỏi bán kính quá lớn.
        let latSpan = maxLatCell - minLatCell
        let lngSpan = maxLngCell - minLngCell
        guard latSpan <= 400, lngSpan <= 400 else { return Array(0..<alerts.count) }

        var result: [Int] = []
        for latCell in minLatCell...maxLatCell {
            for lngCell in minLngCell...maxLngCell {
                if let bucket = index["\(latCell):\(lngCell)"] {
                    result.append(contentsOf: bucket)
                }
            }
        }
        return result
    }
}

extension ActiveAlert {
    /// D_warn = clamp(v_kmh × 3,0 m; 150 m; 500 m) — công thức của HUD dẫn đường Việt Nam.
    static func warnDistance(forSpeed speedKmh: Double?,
                             min minimum: Double,
                             max maximum: Double) -> Double {
        guard let speedKmh, speedKmh.isFinite, speedKmh > 0 else { return minimum }
        let computed = speedKmh * 3.0
        return Swift.min(Swift.max(computed, minimum), maximum)
    }
}

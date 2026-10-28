import Foundation
import CoreLocation

enum OSMError: LocalizedError {
    case noArea
    case server(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .noArea:
            return "Chưa có tuyến đường để tải dữ liệu OpenStreetMap."
        case .server(let message):
            return "OpenStreetMap trả về lỗi: \(message)"
        case .decoding(let message):
            return "Không đọc được dữ liệu OpenStreetMap: \(message)"
        }
    }
}

/// Tải biển giới hạn tốc độ + camera từ OpenStreetMap (Overpass API).
///
/// Chỉ chạy khi người dùng bấm "Tải biển tốc độ từ OSM" — dữ liệu OSM ở Việt Nam
/// còn thưa (cao tốc ~89% có `maxspeed`, quốc lộ ~20%, đường phố rất ít), nên
/// app luôn có thêm bảng mặc định theo TT 38/2024 để bù chỗ trống.
/// Dữ liệu © OpenStreetMap contributors, giấy phép ODbL.
struct OSMAlertService {

    static let endpoint = "https://overpass-api.de/api/interpreter"
    /// Bbox tối đa 0,6° (~65 km) mỗi chiều để Overpass không bị timeout.
    static let maxSpan = 0.6

    func fetchAlerts(around coordinates: [CLLocationCoordinate2D]) async throws -> [RoadAlert] {
        guard let box = Self.boundingBox(coordinates) else { throw OSMError.noArea }

        let query = """
        [out:json][timeout:25];
        (
          node["highway"="speed_camera"](\(box.south),\(box.west),\(box.north),\(box.east));
          node["enforcement"="speed"](\(box.south),\(box.west),\(box.north),\(box.east));
          node["traffic_sign"~"maxspeed",i](\(box.south),\(box.west),\(box.north),\(box.east));
          way["maxspeed"]["highway"](\(box.south),\(box.west),\(box.north),\(box.east));
        );
        out body geom 600;
        """

        var request = URLRequest(url: URL(string: Self.endpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")
        request.setValue("VietMap-iOS/2.0 (https://github.com/TradingLeak/IOS)",
                         forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("data=\(Self.formEncode(query))".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OSMError.server("HTTP \(http.statusCode)")
        }

        let decoded: OSMResponse
        do {
            decoded = try JSONDecoder().decode(OSMResponse.self, from: data)
        } catch {
            throw OSMError.decoding(error.localizedDescription)
        }

        return (decoded.elements ?? []).compactMap(Self.alert(from:))
    }

    // MARK: - Chuyển đổi

    static func alert(from element: OSMElement) -> RoadAlert? {
        guard let tags = element.tags else { return nil }

        if let latitude = element.lat, let longitude = element.lon {
            let isCamera = tags["highway"] == "speed_camera" || tags["enforcement"] == "speed"
            if isCamera {
                return RoadAlert(id: "osm-node-\(element.id ?? 0)",
                                 kind: .speedCamera,
                                 latitude: latitude,
                                 longitude: longitude,
                                 road: tags["name"],
                                 name: tags["name"] ?? "Camera tốc độ (OSM)",
                                 detail: "Nguồn: OpenStreetMap",
                                 confidence: 0.7,
                                 source: "osm")
            }
            if let limit = parseLimit(tags["maxspeed"]) {
                return RoadAlert(id: "osm-node-\(element.id ?? 0)",
                                 kind: .speedSign,
                                 latitude: latitude,
                                 longitude: longitude,
                                 speedLimit: limit,
                                 road: tags["name"],
                                 name: tags["name"] ?? "Biển \(limit) km/h (OSM)",
                                 detail: "Nguồn: OpenStreetMap",
                                 confidence: 0.6,
                                 source: "osm")
            }
            return nil
        }

        // Way có maxspeed → vùng giới hạn bắt đầu từ điểm đầu của way.
        guard let geometry = element.geometry, geometry.count >= 2,
              let limit = parseLimit(tags["maxspeed"]) else { return nil }

        let start = CLLocationCoordinate2D(latitude: geometry[0].lat, longitude: geometry[0].lon)
        let second = CLLocationCoordinate2D(latitude: geometry[1].lat, longitude: geometry[1].lon)
        guard CLLocationCoordinate2DIsValid(start) else { return nil }

        var length = 0.0
        for index in 1..<geometry.count {
            let previous = CLLocationCoordinate2D(latitude: geometry[index - 1].lat,
                                                  longitude: geometry[index - 1].lon)
            let current = CLLocationCoordinate2D(latitude: geometry[index].lat,
                                                 longitude: geometry[index].lon)
            length += Geo.distance(previous, current)
        }
        guard length >= 20 else { return nil }

        return RoadAlert(id: "osm-way-\(element.id ?? 0)",
                         kind: .speedZone,
                         latitude: start.latitude,
                         longitude: start.longitude,
                         speedLimit: limit,
                         bearing: Geo.bearing(from: start, to: second),
                         length: min(length, 5_000),
                         road: tags["name"] ?? tags["ref"],
                         name: tags["name"] ?? tags["ref"] ?? "Giới hạn \(limit) km/h",
                         detail: "Nguồn: OpenStreetMap",
                         confidence: 0.6,
                         source: "osm")
    }

    /// "50", "50 km/h", "50;60", "none" → 50 (bỏ qua giá trị không dùng được).
    static func parseLimit(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let digits = raw.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits) else { return nil }
        guard (20...120).contains(value) else { return nil }
        return value
    }

    // MARK: - Bbox

    struct BoundingBox {
        let south: Double
        let west: Double
        let north: Double
        let east: Double
    }

    static func boundingBox(_ coordinates: [CLLocationCoordinate2D]) -> BoundingBox? {
        let valid = coordinates.filter { CLLocationCoordinate2DIsValid($0) }
        guard !valid.isEmpty else { return nil }

        var south = valid[0].latitude
        var north = valid[0].latitude
        var west = valid[0].longitude
        var east = valid[0].longitude

        for coordinate in valid {
            south = min(south, coordinate.latitude)
            north = max(north, coordinate.latitude)
            west = min(west, coordinate.longitude)
            east = max(east, coordinate.longitude)
        }

        let margin = 0.02
        south -= margin
        north += margin
        west -= margin
        east += margin

        // Thu nhỏ quanh tâm nếu tuyến quá dài.
        var spanLat = north - south
        var spanLng = east - west
        let centerLat = (north + south) / 2
        let centerLng = (east + west) / 2

        if spanLat > maxSpan {
            south = centerLat - maxSpan / 2
            north = centerLat + maxSpan / 2
            spanLat = maxSpan
        }
        if spanLng > maxSpan {
            west = centerLng - maxSpan / 2
            east = centerLng + maxSpan / 2
            spanLng = maxSpan
        }

        return BoundingBox(south: south, west: west, north: north, east: east)
    }

    static func formEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

// MARK: - Mô hình Overpass

struct OSMResponse: Decodable {
    let elements: [OSMElement]?
}

struct OSMElement: Decodable {
    let type: String?
    let id: Int?
    let lat: Double?
    let lon: Double?
    let tags: [String: String]?
    let geometry: [OSMPoint]?
}

struct OSMPoint: Decodable {
    let lat: Double
    let lon: Double
}

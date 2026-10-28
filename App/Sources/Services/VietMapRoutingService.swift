import Foundation
import CoreLocation

// MARK: - Lỗi

enum VietMapError: LocalizedError {
    case missingKey
    case unsupportedMode(TravelMode)
    case badURL
    case server(String)
    case noRoute
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Chưa có API key VietMap. Nhập key trong Cài đặt → Dẫn đường xe máy."
        case .unsupportedMode(let mode):
            return "VietMap không hỗ trợ phương tiện \(mode.title)."
        case .badURL:
            return "Không tạo được địa chỉ yêu cầu VietMap."
        case .server(let message):
            return "VietMap trả về lỗi: \(message)"
        case .noRoute:
            return "VietMap không tìm thấy tuyến phù hợp."
        case .decoding(let message):
            return "Không đọc được phản hồi của VietMap: \(message)"
        }
    }
}

// MARK: - Phản hồi của Route v4

struct VietMapRouteResponse: Decodable {
    let code: String?
    let messages: String?
    let paths: [VietMapPath]?
}

struct VietMapPath: Decodable {
    let distance: Double?
    /// Milisecond theo tài liệu Route v4.
    let time: Double?
    let points: String?
    let pointsEncoded: Bool?
    let instructions: [VietMapInstruction]?
    let tollCost: Int?

    enum CodingKeys: String, CodingKey {
        case distance, time, points, instructions
        case pointsEncoded = "points_encoded"
        case tollCost = "toll_cost"
    }
}

struct VietMapInstruction: Decodable {
    let distance: Double?
    let text: String?
    let streetName: String?
    let sign: Int?
    let interval: [Int]?

    enum CodingKeys: String, CodingKey {
        case distance, text, sign, interval
        case streetName = "street_name"
    }
}

// MARK: - Dịch vụ

/// Dẫn đường bằng VietMap Route v4 — dịch vụ **duy nhất trong app có hồ sơ xe máy**
/// (`vehicle=motorcycle`) cho đường Việt Nam.
///
/// Cần API key (đăng ký tại https://maps.vietmap.vn — có gói miễn phí).
/// Không có key thì app dùng Apple Maps và ước lượng lại cho xe máy
/// (xem `RoutingService.adjustForMotorcycle`).
struct VietMapRoutingService {

    static let endpoint = "https://maps.vietmap.vn/api/route/v4"

    func routes(from origin: Place,
                to destination: Place,
                waypoints: [Place] = [],
                mode: TravelMode,
                apiKey: String) async throws -> [RouteOption] {
        var points: [CLLocationCoordinate2D] = [origin.coordinate]
        points.append(contentsOf: waypoints.map(\.coordinate))
        points.append(destination.coordinate)
        return try await routes(points: points, mode: mode, apiKey: apiKey, alternatives: waypoints.isEmpty)
    }

    func routes(points: [CLLocationCoordinate2D],
                mode: TravelMode,
                apiKey: String,
                alternatives: Bool = true) async throws -> [RouteOption] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw VietMapError.missingKey }

        let vehicle: String
        switch mode {
        case .motorcycle: vehicle = "motorcycle"
        case .automobile: vehicle = "car"
        case .walking, .transit: throw VietMapError.unsupportedMode(mode)
        }

        guard points.count >= 2 else {
            throw VietMapError.server("Cần ít nhất 2 điểm.")
        }

        var components = URLComponents(string: Self.endpoint)
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "apikey", value: key)]
        for point in points {
            queryItems.append(URLQueryItem(name: "point",
                                           value: String(format: "%.6f,%.6f", point.latitude, point.longitude)))
        }
        queryItems.append(URLQueryItem(name: "vehicle", value: vehicle))
        queryItems.append(URLQueryItem(name: "points_encoded", value: "true"))
        queryItems.append(URLQueryItem(name: "alternative", value: alternatives ? "true" : "false"))
        queryItems.append(URLQueryItem(name: "annotations", value: "toll"))
        components?.queryItems = queryItems

        guard let url = components?.url else { throw VietMapError.badURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw VietMapError.server("HTTP \(http.statusCode) \(body.prefix(180))")
        }

        let decoded: VietMapRouteResponse
        do {
            decoded = try JSONDecoder().decode(VietMapRouteResponse.self, from: data)
        } catch {
            throw VietMapError.decoding(error.localizedDescription)
        }

        if let code = decoded.code, code.uppercased() != "OK" {
            throw VietMapError.server(decoded.messages ?? code)
        }

        let paths = decoded.paths ?? []
        guard !paths.isEmpty else { throw VietMapError.noRoute }

        return paths.enumerated().compactMap { index, path in
            Self.makeOption(path, index: index, mode: mode)
        }
    }

    // MARK: - Chuyển đổi

    static func makeOption(_ path: VietMapPath, index: Int, mode: TravelMode) -> RouteOption? {
        let coordinates = PolylineCoder.decode(path.points ?? "")
        guard coordinates.count >= 2 else { return nil }

        let distance = path.distance ?? 0
        // Route v4 trả `time` bằng milisecond.
        let rawTime = path.time ?? 0
        let seconds = rawTime > 100_000 ? rawTime / 1000 : rawTime
        let travelTime = seconds > 0 ? seconds : max(60, distance / 8.3)

        var notices: [String] = []
        if let toll = path.tollCost, toll > 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = "."
            let money = formatter.string(from: NSNumber(value: toll)) ?? "\(toll)"
            notices.append("Tuyến có trạm thu phí, tổng khoảng \(money) đ.")
        }

        let steps = (path.instructions ?? []).map { instruction -> RouteStep in
            var text = instruction.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let street = instruction.streetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty { text = street }
            if text.isEmpty { text = index == 0 ? "Bắt đầu di chuyển" : "Tiếp tục di chuyển" }
            if instruction.sign == 4 { text = "Đến nơi" }

            var end = coordinates.last ?? kCLLocationCoordinate2DInvalid
            if let interval = instruction.interval, interval.count >= 2 {
                let target = min(max(interval[1], 0), coordinates.count - 1)
                end = coordinates[target]
            }

            return RouteStep(instruction: text,
                             distance: instruction.distance ?? 0,
                             endCoordinate: CLLocationCoordinate2DIsValid(end)
                                ? end
                                : CLLocationCoordinate2D(latitude: 0, longitude: 0),
                             roadName: street.isEmpty ? nil : street)
        }

        return RouteOption(name: index == 0 ? "Tuyến xe máy" : "Phương án \(index + 1)",
                           distance: distance,
                           expectedTravelTime: travelTime,
                           coordinates: coordinates,
                           steps: steps,
                           mode: mode,
                           advisoryNotices: notices,
                           provider: .vietmap,
                           tollCost: path.tollCost)
    }
}

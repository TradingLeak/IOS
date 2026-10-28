import Foundation
import CoreLocation

/// Soạn nội dung chia sẻ tuyến (tin nhắn + link mở Apple Maps).
///
/// Người nhận bấm link là mở ngay lộ trình trong Apple Maps — không cần cài app này.
enum RouteShare {

    /// `dirflg` của Apple Maps: d = lái xe, w = đi bộ, r = phương tiện công cộng.
    static func appleMapsURL(origin: Place?,
                             destination: Place,
                             waypoints: [Place] = [],
                             mode: TravelMode) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        var items: [URLQueryItem] = []

        if let origin {
            items.append(URLQueryItem(name: "saddr",
                                      value: coordinateText(origin.coordinate)))
        }
        let stops = waypoints.map { "\(coordinateText($0.coordinate))" }
        let destinationText = ([coordinateText(destination.coordinate)] + stops).joined(separator: "+to:")
        items.append(URLQueryItem(name: "daddr", value: destinationText))
        items.append(URLQueryItem(name: "dirflg", value: mode == .walking ? "w" : (mode == .transit ? "r" : "d")))
        components?.queryItems = items
        return components?.url
    }

    /// Tin nhắn chia sẻ: tuyến, thời gian, cảnh báo, điểm dừng và link.
    static func message(origin: Place?,
                        destination: Place,
                        waypoints: [Place] = [],
                        route: RouteOption,
                        alerts: Int = 0,
                        mode: TravelMode) -> String {
        var lines: [String] = []
        let from = origin?.name ?? "vị trí hiện tại"
        lines.append("Lộ trình: \(from) → \(destination.name)")

        var facts = ["\(route.formattedDistance)", "\(route.formattedDuration)"]
        if let arrival = route.arrivalText() {
            facts.append("tới nơi \(arrival)")
        }
        facts.append(route.mode.title.lowercased())
        lines.append(facts.joined(separator: " · "))

        if !waypoints.isEmpty {
            lines.append("Ghé: " + waypoints.map(\.name).joined(separator: " → "))
        }
        if alerts > 0 {
            lines.append("Trên đường có \(alerts) cảnh báo (camera / biển tốc độ).")
        }
        if let url = appleMapsURL(origin: origin, destination: destination, waypoints: waypoints, mode: mode) {
            lines.append(url.absoluteString)
        }
        lines.append("(Chia sẻ từ Bản đồ Việt Nam)")
        return lines.joined(separator: "\n")
    }

    private static func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
    }
}

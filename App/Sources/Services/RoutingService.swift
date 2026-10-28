import Foundation
import CoreLocation

/// Chọn nhà cung cấp tuyến đường phù hợp với phương tiện:
///
/// - Ô tô / đi bộ / xe buýt → Apple Maps (MapKit).
/// - Xe máy + có API key VietMap → VietMap Route v4 (`vehicle=motorcycle`),
///   đây là dịch vụ duy nhất có hồ sơ xe máy thật cho đường Việt Nam.
/// - Xe máy + không có key → Apple Maps rồi **lọc tuyến có cao tốc** và hiệu chỉnh
///   thời gian theo tốc độ xe máy (ước lượng, có ghi chú rõ trong app).
struct RoutingService {

    var vietmapKey: String
    private let apple = DirectionsService()
    private let vietmap = VietMapRoutingService()

    init(vietmapKey: String = "") {
        self.vietmapKey = vietmapKey
    }

    var hasVietMapKey: Bool {
        !vietmapKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func routes(from origin: Place,
                to destination: Place,
                mode: TravelMode,
                waypoints: [Place] = []) async throws -> [RouteOption] {

        if mode == .motorcycle, hasVietMapKey {
            do {
                var result = try await vietmap.routes(from: origin,
                                                      to: destination,
                                                      waypoints: waypoints,
                                                      mode: mode,
                                                      apiKey: vietmapKey)
                result = Self.sanitizeVietMap(result)
                if !result.isEmpty { return result }
            } catch {
                // VietMap lỗi (hết quota, mạng, key sai) → vẫn phải có tuyến để đi.
                var fallback = try await apple.routes(from: origin,
                                                      to: destination,
                                                      mode: mode,
                                                      waypoints: waypoints)
                fallback = Self.adjustForMotorcycle(fallback)
                if !fallback.isEmpty {
                    fallback[0].advisoryNotices.insert(
                        "Không gọi được VietMap (\(error.localizedDescription)). Đang dùng tuyến ước lượng từ Apple Maps.",
                        at: 0)
                }
                return fallback
            }
        }

        var result = try await apple.routes(from: origin,
                                            to: destination,
                                            mode: mode,
                                            waypoints: waypoints)
        if mode == .motorcycle {
            result = Self.adjustForMotorcycle(result)
        }
        return result
    }

    // MARK: - Xe máy trên Apple Maps

    /// Apple Maps không có hồ sơ xe máy: lọc bỏ tuyến đi cao tốc, hiệu chỉnh thời gian.
    static func adjustForMotorcycle(_ routes: [RouteOption]) -> [RouteOption] {
        guard !routes.isEmpty else { return [] }

        // Chỉ hiệu chỉnh tuyến được yêu cầu cho xe máy; tuyến ô tô/đi bộ giữ nguyên.
        guard routes.contains(where: { $0.mode == .motorcycle }) else { return routes }

        let shares = routes.map { RouteScorer.expresswayShare($0) }
        let bestShare = shares.min() ?? 0
        var output: [RouteOption] = []

        for (index, route) in routes.enumerated() {
            guard route.mode == .motorcycle else {
                output.append(route)
                continue
            }
            var adjusted = route
            let share = shares[index]

            // Giữ lại tuyến tránh cao tốc; nếu mọi tuyến đều có cao tốc thì vẫn giữ
            // nhưng cảnh báo rõ (xe máy không được đi cao tốc).
            if routes.count > 1, bestShare < 0.2, share >= 0.2 { continue }

            // Trong phố xe máy thường nhanh hơn ô tô; ngoài đô thị thì chậm hơn.
            let factor = share > 0.05 ? 1.02 : 0.92
            adjusted.expectedTravelTime = max(60, route.expectedTravelTime * factor)
            adjusted.isEstimatedProfile = true
            adjusted.provider = .apple

            if share > 0.05 {
                adjusted.advisoryNotices.append(SpeedLimitRules.motorcycleExpresswayNotice)
            } else {
                adjusted.advisoryNotices.append(
                    "Thời gian xe máy là ước lượng từ Apple Maps (chưa có hồ sơ xe máy). "
                    + "Nhập API key VietMap trong Cài đặt để có tuyến xe máy chính xác.")
            }

            output.append(adjusted)
        }

        if output.isEmpty { output = routes }
        // Giữ nguyên thứ tự ban đầu để bảng so sánh không bị đảo.
        let order = Dictionary(uniqueKeysWithValues: routes.enumerated().map { ($1.id, $0) })
        return output.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }

    /// VietMap có thể trả tuyến 0 mét hoặc trùng nhau — bỏ đi.
    static func sanitizeVietMap(_ routes: [RouteOption]) -> [RouteOption] {
        var seen = Set<String>()
        var output: [RouteOption] = []
        for route in routes where route.distance > 1 && route.coordinates.count >= 2 {
            let signature = "\(Int(route.distance.rounded()))-\(route.coordinates.count)"
            if seen.contains(signature) { continue }
            seen.insert(signature)
            output.append(route)
        }
        return output
    }
}

import Foundation
import CoreLocation

/// Tính tuyến đường **không phụ thuộc dịch vụ ngoài**: chỉ Apple Maps (MapKit) + logic nội bộ.
///
/// - Ô tô / đi bộ / xe buýt → Apple Maps nguyên bản.
/// - Xe máy → Apple Maps (chưa có hồ sơ xe máy) rồi **lọc tuyến có cao tốc**, hiệu chỉnh
///   thời gian theo tốc độ xe máy và chấm điểm bằng `RouteScorer`. Mọi điểm ước lượng
///   đều được ghi rõ trong `advisoryNotices`.
///
/// Trước 3.0 app gọi VietMap Route v4 khi có API key; từ 3.0 đã bỏ hoàn toàn để
/// không phụ thuộc bên thứ ba (xem `docs/NAVIGATION.md`).
struct RoutingService {

    private let apple = DirectionsService()

    func routes(from origin: Place,
                to destination: Place,
                mode: TravelMode,
                waypoints: [Place] = []) async throws -> [RouteOption] {

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
                    "Thời gian xe máy là ước lượng nội bộ từ Apple Maps "
                    + "(tốc độ trung bình theo loại đường Việt Nam), không dùng dịch vụ ngoài.")
            }

            output.append(adjusted)
        }

        if output.isEmpty { output = routes }
        // Giữ nguyên thứ tự ban đầu để bảng so sánh không bị đảo.
        let order = Dictionary(uniqueKeysWithValues: routes.enumerated().map { ($1.id, $0) })
        return output.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }

    /// Bỏ tuyến 0 mét hoặc trùng nhau (Apple Maps đôi khi trả về nhiều phương án giống hệt).
    static func sanitize(_ routes: [RouteOption]) -> [RouteOption] {
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

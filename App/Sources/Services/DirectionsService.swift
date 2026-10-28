import Foundation
import MapKit
import CoreLocation

enum DirectionsError: LocalizedError {
    case noRoute(TravelMode)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noRoute(let mode):
            switch mode {
            case .transit:
                return "Apple Maps chưa có dữ liệu xe buýt cho tuyến này. Hãy thử Ô tô, Xe máy hoặc Đi bộ."
            case .walking:
                return "Không tìm được tuyến đi bộ giữa hai điểm này (có thể cách sông hoặc biển)."
            case .automobile:
                return "Không tìm được tuyến ô tô giữa hai điểm này."
            case .motorcycle:
                return "Không tìm được tuyến xe máy giữa hai điểm này. Hãy thử đổi điểm đi/điểm đến hoặc dùng Ô tô."
            }
        case .failed(let message):
            return "Không tính được tuyến đường: \(message)"
        }
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        guard pointCount > 0 else { return [] }
        var result = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&result, range: NSRange(location: 0, length: pointCount))
        return result
    }
}

/// Tính tuyến đường bằng MKDirections (Apple Maps) — miễn phí, không cần API key.
struct DirectionsService {

    func routes(from origin: Place,
                to destination: Place,
                mode: TravelMode,
                waypoints: [Place] = []) async throws -> [RouteOption] {
        try await routes(from: origin.mkMapItem,
                         to: destination.mkMapItem,
                         mode: mode,
                         waypoints: waypoints.map(\.mkMapItem))
    }

    func routes(from origin: MKMapItem,
                to destination: MKMapItem,
                mode: TravelMode,
                waypoints: [MKMapItem] = []) async throws -> [RouteOption] {

        // Không có điểm dừng giữa đường → lấy cả tuyến thay thế để người dùng chọn.
        guard !waypoints.isEmpty else {
            let results = try await request(from: origin, to: destination, mode: mode, alternatives: true)
            guard !results.isEmpty else { throw DirectionsError.noRoute(mode) }
            return results.enumerated().map { index, route in
                makeOption(route, mode: mode, name: index == 0 ? "Tuyến chính" : "Phương án \(index + 1)")
            }
        }

        // Có điểm dừng → nối từng chặng thành một tuyến duy nhất.
        var stops: [MKMapItem] = [origin] + waypoints + [destination]
        var coordinates: [CLLocationCoordinate2D] = []
        var steps: [RouteStep] = []
        var distance: Double = 0
        var travelTime: TimeInterval = 0
        var notices: [String] = []

        while stops.count > 1 {
            let start = stops.removeFirst()
            guard let end = stops.first else { break }
            let results = try await request(from: start, to: end, mode: mode, alternatives: false)
            guard let route = results.first else { throw DirectionsError.noRoute(mode) }

            distance += route.distance
            travelTime += route.expectedTravelTime
            notices.append(contentsOf: route.advisoryNotices)
            steps.append(contentsOf: route.steps.map(Self.step(from:)))

            let legCoordinates = route.polyline.coordinates
            if let last = coordinates.last, let first = legCoordinates.first,
               last.latitude == first.latitude, last.longitude == first.longitude {
                coordinates.append(contentsOf: legCoordinates.dropFirst())
            } else {
                coordinates.append(contentsOf: legCoordinates)
            }
        }

        guard !coordinates.isEmpty else { throw DirectionsError.noRoute(mode) }
        return [RouteOption(name: "Tuyến có điểm dừng",
                            distance: distance,
                            expectedTravelTime: travelTime,
                            coordinates: coordinates,
                            steps: steps,
                            mode: mode,
                            advisoryNotices: notices)]
    }

    // MARK: - Private

    private func request(from origin: MKMapItem,
                         to destination: MKMapItem,
                         mode: TravelMode,
                         alternatives: Bool) async throws -> [MKRoute] {
        let request = MKDirections.Request()
        request.source = origin
        request.destination = destination
        request.transportType = mode.transportType
        request.requestsAlternateRoutes = alternatives

        let directions = MKDirections(request: request)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[MKRoute], Error>) in
            directions.calculate { response, error in
                if let error {
                    continuation.resume(throwing: DirectionsError.failed(error.localizedDescription))
                    return
                }
                continuation.resume(returning: response?.routes ?? [])
            }
        }
    }

    private func makeOption(_ route: MKRoute, mode: TravelMode, name: String) -> RouteOption {
        RouteOption(name: route.name.isEmpty ? name : route.name,
                    distance: route.distance,
                    expectedTravelTime: route.expectedTravelTime,
                    coordinates: route.polyline.coordinates,
                    steps: route.steps.map(Self.step(from:)),
                    mode: mode,
                    advisoryNotices: route.advisoryNotices)
    }

    static func step(from step: MKRoute.Step) -> RouteStep {
        // `instructions`/`notice` có thể là optional tuỳ phiên bản SDK → gán qua String?
        let instructions: String? = step.instructions
        let notice: String? = step.notice
        var text = ""
        if let instructions, !instructions.isEmpty {
            text = instructions
        } else if let notice, !notice.isEmpty {
            text = notice
        }
        if text.isEmpty { text = "Tiếp tục di chuyển" }

        let end = step.polyline.coordinates.last ?? kCLLocationCoordinate2DInvalid
        return RouteStep(instruction: text,
                         distance: step.distance,
                         endCoordinate: CLLocationCoordinate2DIsValid(end)
                            ? end
                            : CLLocationCoordinate2D(latitude: 0, longitude: 0))
    }
}

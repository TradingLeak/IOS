import Foundation
import MapKit
import CoreLocation
import Combine

enum SearchError: LocalizedError {
    case empty
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Không tìm thấy địa điểm nào phù hợp."
        case .failed(let message):
            return message
        }
    }
}

struct SearchSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion
}

/// Tìm kiếm địa điểm bằng Apple Maps (MapKit), thiên vị khu vực Việt Nam.
final class SearchService: NSObject, ObservableObject {
    @Published private(set) var suggestions: [SearchSuggestion] = []

    private let completer = MKLocalSearchCompleter()
    private var region: MKCoordinateRegion

    init(region: MKCoordinateRegion = MapPreset.vietnam.region) {
        self.region = region
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = region
    }

    func updateRegion(_ region: MKCoordinateRegion) {
        self.region = region
        completer.region = region
    }

    /// Gợi ý khi người dùng đang gõ.
    func suggest(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            completer.queryFragment = ""
            return
        }
        completer.queryFragment = trimmed
    }

    func clearSuggestions() {
        suggestions = []
        completer.queryFragment = ""
    }

    // MARK: Tìm kiếm

    func search(query: String, near region: MKCoordinateRegion? = nil) async throws -> [Place] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = region ?? self.region
        let response = try await run(request)
        return response.mapItems.map(Self.place(from:))
    }

    /// Chuyển một gợi ý (completion) thành địa điểm đầy đủ.
    func resolve(_ suggestion: SearchSuggestion) async throws -> Place? {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        request.region = region
        let response = try await run(request)
        guard let item = response.mapItems.first else { return nil }
        return Self.place(from: item)
    }

    /// Tìm địa điểm theo danh mục quanh một toạ độ.
    func nearby(_ category: NearbyCategory,
                around coordinate: CLLocationCoordinate2D,
                radiusMeters: CLLocationDistance = 5000) async throws -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category.query
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [category.category])
        let response = try await run(request)
        return response.mapItems.map(Self.place(from:))
    }

    /// Chuyển toạ độ thành địa chỉ (dùng khi người dùng nhấn giữ trên bản đồ).
    func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> Place {
        let geocoder = CLGeocoder()
        let placemarks: [CLPlacemark] = await withCheckedContinuation { continuation in
            geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude,
                                                       longitude: coordinate.longitude)) { placemarks, _ in
                continuation.resume(returning: placemarks ?? [])
            }
        }
        if let placemark = placemarks.first {
            let name = placemark.name ?? placemark.locality ?? "Điểm đã chọn"
            return Place(name: name,
                         subtitle: Self.addressLine(from: placemark),
                         coordinate: coordinate)
        }
        return Place(name: "Điểm đã chọn",
                     subtitle: Format.coordinates(coordinate),
                     coordinate: coordinate)
    }

    // MARK: Helpers

    private func run(_ request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKLocalSearch.Response, Error>) in
            let search = MKLocalSearch(request: request)
            search.start { response, error in
                if let error {
                    continuation.resume(throwing: SearchError.failed(error.localizedDescription))
                    return
                }
                guard let response else {
                    continuation.resume(throwing: SearchError.empty)
                    return
                }
                continuation.resume(returning: response)
            }
        }
    }

    static func place(from item: MKMapItem) -> Place {
        let placemark = item.placemark
        let name = item.name ?? placemark.name ?? "Địa điểm"
        return Place(name: name,
                     subtitle: addressLine(from: placemark),
                     coordinate: placemark.coordinate,
                     mapItem: item)
    }

    static func addressLine(from placemark: CLPlacemark) -> String {
        var parts: [String] = []
        if let sub = placemark.subThoroughfare, let thoroughfare = placemark.thoroughfare {
            parts.append("\(sub) \(thoroughfare)")
        } else if let thoroughfare = placemark.thoroughfare {
            parts.append(thoroughfare)
        }
        if let locality = placemark.locality, !parts.contains(locality) {
            parts.append(locality)
        }
        if let admin = placemark.administrativeArea, !parts.contains(admin) {
            parts.append(admin)
        }
        if parts.isEmpty, let country = placemark.country {
            parts.append(country)
        }
        return parts.joined(separator: ", ")
    }
}

extension SearchService: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results.prefix(12).map {
            SearchSuggestion(title: $0.title, subtitle: $0.subtitle, completion: $0)
        }
        DispatchQueue.main.async {
            self.suggestions = Array(items)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.suggestions = []
        }
    }
}

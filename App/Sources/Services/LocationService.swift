import Foundation
import CoreLocation
import Combine

/// Bọc CLLocationManager: xin quyền, lấy vị trí hiện tại, theo dõi khi đang chỉ đường.
final class LocationService: NSObject, ObservableObject {
    private let manager = CLLocationManager()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var isLocating = false
    @Published private(set) var lastError: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 8
        authorizationStatus = manager.authorizationStatus
    }

    var hasLocation: Bool { coordinate != nil }

    /// Tốc độ hiện tại (km/h). `CLLocation.speed` trả -1 khi không xác định.
    var speedKmh: Double {
        guard let speed = lastLocation?.speed, speed >= 0 else { return 0 }
        return speed * 3.6
    }

    var courseDegrees: Double? {
        guard let course = lastLocation?.course, course >= 0 else { return nil }
        return course
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Xin quyền (nếu chưa có) và lấy một lần vị trí.
    func requestLocation() {
        lastError = nil
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isLocating = true
            manager.requestLocation()
        case .denied, .restricted:
            lastError = "Bạn đã từ chối quyền vị trí. Mở Cài đặt để bật lại."
        @unknown default:
            manager.requestWhenInUseAuthorization()
        }
    }

    func startUpdating() {
        guard isAuthorized else {
            requestLocation()
            return
        }
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Bỏ qua điểm cũ / kém chính xác để số km/h không nhảy loạn.
        if location.horizontalAccuracy > 80 { return }
        coordinate = location.coordinate
        lastLocation = location
        isLocating = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        lastError = "Không lấy được vị trí: \(error.localizedDescription)"
    }
}

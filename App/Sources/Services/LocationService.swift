import Foundation
import CoreLocation
import Combine

/// Bọc CLLocationManager: xin quyền, lấy vị trí hiện tại, theo dõi khi đang chỉ đường.
final class LocationService: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    private var wantsContinuousUpdates = false

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    /// CLLocation đầy đủ (course/speed/timestamp) — HUD speedmap cần speed & heading.
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
        wantsContinuousUpdates = true
        guard isAuthorized else {
            requestLocation()
            return
        }
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        wantsContinuousUpdates = false
        manager.stopUpdatingLocation()
    }

    /// Chế độ chỉ đường: tần suất GPS cao hơn (3m) để HUD/cảnh báo chạy mượt.
    func setNavigationMode(_ active: Bool) {
        manager.distanceFilter = active ? 3 : 8
        manager.desiredAccuracy = active ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyBest
        manager.activityType = active ? .automotiveNavigation : .other
        if active { startUpdating() }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            if wantsContinuousUpdates {
                manager.startUpdatingLocation()
            } else {
                manager.requestLocation()
            }
        } else {
            coordinate = nil
            lastLocation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        if let lastLocation, location.timestamp < lastLocation.timestamp { return }
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

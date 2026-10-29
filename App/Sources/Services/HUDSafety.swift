import Foundation
import CoreLocation

/// Chính sách dùng chung cho HUD và bộ cảnh báo. Không suy ra tốc độ 0 khi GPS lỗi.
enum HUDSafety {
    static let maximumAge: TimeInterval = 10
    static let maximumAccuracyM: Double = 50

    static func hasUsableFix(_ location: CLLocation?, now: Date = Date()) -> Bool {
        guard let location else { return false }
        let age = now.timeIntervalSince(location.timestamp)
        return age >= -2 && age <= maximumAge
            && location.horizontalAccuracy.isFinite
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumAccuracyM
            && CLLocationCoordinate2DIsValid(location.coordinate)
    }

    static func speedKmh(_ location: CLLocation?, now: Date = Date()) -> Double? {
        guard hasUsableFix(location, now: now), let location,
              location.speed.isFinite, location.speed >= 0 else { return nil }
        return location.speed * 3.6
    }
}

/// Hysteresis 2 km/h + cooldown để giọng nói không lặp liên tục quanh ngưỡng.
struct OverspeedMonitor {
    private(set) var isOverspeed = false
    private var lastAnnouncement: Date?
    var cooldown: TimeInterval = 30

    mutating func update(speedKmh: Double?, limitKmh: Int?, now: Date = Date()) -> Bool {
        guard let speedKmh, speedKmh.isFinite, speedKmh >= 0,
              let limitKmh, limitKmh > 0 else {
            isOverspeed = false
            return false
        }
        let limit = Double(limitKmh)
        if isOverspeed {
            isOverspeed = speedKmh > limit
        } else {
            isOverspeed = speedKmh > limit + 2
        }
        guard isOverspeed else { return false }
        if let lastAnnouncement, now.timeIntervalSince(lastAnnouncement) < cooldown { return false }
        lastAnnouncement = now
        return true
    }
}

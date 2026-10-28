import Foundation
import CoreLocation

struct StoredPlace: Codable, Identifiable {
    var id: UUID
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double

    init(place: Place) {
        id = place.id
        name = place.name
        subtitle = place.subtitle
        latitude = place.latitude
        longitude = place.longitude
    }

    var place: Place {
        Place(id: id, name: name, subtitle: subtitle, latitude: latitude, longitude: longitude)
    }
}

/// Lưu lịch sử tìm kiếm + địa điểm yêu thích bằng UserDefaults (dạng JSON).
final class PlacesStore {
    private let defaults: UserDefaults
    private let recentKey = "vietmap.places.recent"
    private let favoriteKey = "vietmap.places.favorites"
    private let maxRecents = 8

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Gần đây

    func recents() -> [Place] {
        load(recentKey).map(\.place)
    }

    func addRecent(_ place: Place) {
        var items = load(recentKey)
        items.removeAll { Self.isSame($0, place) }
        items.insert(StoredPlace(place: place), at: 0)
        if items.count > maxRecents { items = Array(items.prefix(maxRecents)) }
        save(items, key: recentKey)
    }

    func clearRecents() {
        defaults.removeObject(forKey: recentKey)
    }

    // MARK: Yêu thích

    func favorites() -> [Place] {
        load(favoriteKey).map(\.place)
    }

    func isFavorite(_ place: Place) -> Bool {
        load(favoriteKey).contains { Self.isSame($0, place) }
    }

    /// Trả về true nếu vừa thêm vào yêu thích, false nếu vừa bỏ ra.
    @discardableResult
    func toggleFavorite(_ place: Place) -> Bool {
        var items = load(favoriteKey)
        if let index = items.firstIndex(where: { Self.isSame($0, place) }) {
            items.remove(at: index)
            save(items, key: favoriteKey)
            return false
        }
        items.insert(StoredPlace(place: place), at: 0)
        save(items, key: favoriteKey)
        return true
    }

    func removeFavorite(_ place: Place) {
        var items = load(favoriteKey)
        items.removeAll { Self.isSame($0, place) }
        save(items, key: favoriteKey)
    }

    func clearFavorites() {
        defaults.removeObject(forKey: favoriteKey)
    }

    // MARK: Helpers

    /// Coi là cùng một địa điểm nếu tên giống nhau hoặc cách nhau < 60 m.
    static func isSame(_ stored: StoredPlace, _ place: Place) -> Bool {
        if stored.name.caseInsensitiveCompare(place.name) == .orderedSame { return true }
        let a = CLLocation(latitude: stored.latitude, longitude: stored.longitude)
        let b = CLLocation(latitude: place.latitude, longitude: place.longitude)
        return a.distance(from: b) < 60
    }

    private func load(_ key: String) -> [StoredPlace] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([StoredPlace].self, from: data)) ?? []
    }

    private func save(_ items: [StoredPlace], key: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }
}

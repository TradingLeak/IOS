import Foundation
import CoreLocation

/// Xếp hạng & lọc địa điểm **không phân biệt dấu** ("ho hoan kiem" vẫn ra "Hồ Hoàn Kiếm"),
/// ưu tiên khớp đầu tên rồi mới tới gần nhất — giống cách Google Maps/VietMap gợi ý.
enum SearchRanking {

    /// Chuẩn hoá: chữ thường, bỏ dấu tiếng Việt (kể cả đ → d), gộp khoảng trắng.
    static func normalize(_ text: String) -> String {
        let lowered = text
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "vi_VN"))
            .lowercased()

        let cleaned = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                return Character(scalar)
            }
            return " "
        }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// Địa điểm có khớp câu tìm hay không (xét cả tên, địa chỉ phụ).
    static func matches(_ place: Place, query: String) -> Bool {
        let needle = normalize(query)
        guard !needle.isEmpty else { return true }
        let haystack = normalize(place.name + " " + place.displaySubtitle)
        if haystack.contains(needle) { return true }
        // Người dùng gõ nhiều từ rời: mọi từ phải xuất hiện.
        let words = needle.split(separator: " ")
        return words.count > 1 && words.allSatisfy { haystack.contains($0) }
    }

    /// Lọc danh sách cục bộ (yêu thích, gần đây) theo câu tìm.
    static func filter(_ places: [Place], query: String) -> [Place] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return places }
        return places.filter { matches($0, query: query) }
    }

    /// Sắp xếp kết quả: khớp đầu tên trước, sau đó theo khoảng cách (nếu có vị trí hiện tại).
    static func rank(_ places: [Place],
                     query: String,
                     near coordinate: CLLocationCoordinate2D?) -> [Place] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return places }

        func score(_ place: Place) -> (Int, Double) {
            let name = normalize(place.name)
            let prefix = name.hasPrefix(needle) ? 0 : (name.contains(needle) ? 1 : 2)
            let distance: Double
            if let coordinate {
                distance = CLLocation(latitude: place.latitude, longitude: place.longitude)
                    .distance(from: CLLocation(latitude: coordinate.latitude,
                                               longitude: coordinate.longitude))
            } else {
                distance = 0
            }
            return (prefix, distance)
        }

        return places.sorted { left, right in
            let a = score(left)
            let b = score(right)
            if a.0 != b.0 { return a.0 < b.0 }
            if a.1 != b.1 { return a.1 < b.1 }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    /// "cách 320 m", "cách 1,4 km" — hiện kèm kết quả tìm kiếm.
    static func distanceText(_ place: Place, from coordinate: CLLocationCoordinate2D?) -> String? {
        guard let coordinate else { return nil }
        let meters = CLLocation(latitude: place.latitude, longitude: place.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        return "cách \(Format.distance(meters))"
    }
}

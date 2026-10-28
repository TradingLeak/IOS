import Foundation
import MapKit
import CoreLocation

// MARK: - Chế độ di chuyển

enum TravelMode: String, CaseIterable, Identifiable, Codable {
    case automobile
    case motorcycle
    case walking
    case transit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automobile: return "Ô tô"
        case .motorcycle: return "Xe máy"
        case .walking: return "Đi bộ"
        case .transit: return "Xe buýt"
        }
    }

    var shortTitle: String {
        switch self {
        case .automobile: return "Ô tô"
        case .motorcycle: return "Xe máy"
        case .walking: return "Đi bộ"
        case .transit: return "Buýt"
        }
    }

    var symbol: String {
        switch self {
        case .automobile: return "car.fill"
        case .motorcycle: return "scooter"
        case .walking: return "figure.walk"
        case .transit: return "bus.fill"
        }
    }

    /// Apple Maps chỉ có ô tô / đi bộ / xe buýt, **không** có hồ sơ xe máy.
    /// Xe máy dùng tạm hồ sơ ô tô rồi lọc/ước lượng lại (xem `RoutingService`),
    /// hoặc dùng VietMap Route v4 nếu người dùng nhập API key.
    var transportType: MKDirectionsTransportType {
        switch self {
        case .automobile, .motorcycle: return .automobile
        case .walking: return .walking
        case .transit: return .transit
        }
    }

    /// Có hồ sơ dẫn đường riêng trong Apple Maps hay không.
    var hasNativeProfile: Bool {
        self != .motorcycle
    }

    /// Nhận cả tiếng Việt lẫn tiếng Anh, dùng cho dữ liệu do AI trả về.
    static func parse(_ raw: String?) -> TravelMode? {
        guard let raw else { return nil }
        let value = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        if value.contains("xe máy") || value.contains("xe may") || value.contains("mô tô")
            || value.contains("mo to") || value.contains("motorcycle") || value.contains("motorbike")
            || value.contains("scooter") || value.contains("two-wheel")
            || (value.contains("xe") && value.contains("máy")) { return .motorcycle }
        if value.contains("đi bộ") || value.contains("di bo") || value.contains("walk")
            || value.contains("foot") || value.contains("xe đạp") || value.contains("bicycle") {
            return .walking
        }
        if value.contains("transit") || value.contains("bus") || value.contains("buýt")
            || value.contains("công cộng") || value.contains("tàu") { return .transit }
        if value.contains("car") || value.contains("drive") || value.contains("auto")
            || value.contains("ô tô") || value.contains("o to") || value.contains("xe hơi")
            || value.contains("lái") { return .automobile }
        return nil
    }
}

// MARK: - Địa điểm

struct Place: Identifiable {
    let id: UUID
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var mapItem: MKMapItem?

    init(id: UUID = UUID(),
         name: String,
         subtitle: String = "",
         coordinate: CLLocationCoordinate2D,
         mapItem: MKMapItem? = nil) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.mapItem = mapItem
    }

    init(id: UUID = UUID(), name: String, subtitle: String = "", latitude: Double, longitude: Double) {
        self.init(id: id, name: name, subtitle: subtitle,
                  coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var mkMapItem: MKMapItem {
        if let mapItem { return mapItem }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        return item
    }

    var displaySubtitle: String {
        subtitle.isEmpty ? Format.coordinates(coordinate) : subtitle
    }
}

// MARK: - Tuyến đường

/// Nhà cung cấp dịch vụ tính tuyến.
enum RouteProviderKind: String, Codable {
    case apple
    case vietmap

    var title: String {
        switch self {
        case .apple: return "Apple Maps"
        case .vietmap: return "VietMap"
        }
    }

    var supportsMotorcycleProfile: Bool { self == .vietmap }
}

struct RouteStep: Identifiable {
    let id = UUID()
    let instruction: String
    let distance: Double
    let endCoordinate: CLLocationCoordinate2D
    /// Tên đường (nếu nhà cung cấp trả về) — dùng để suy ra giới hạn tốc độ.
    var roadName: String? = nil

    var formattedDistance: String { Format.distance(distance) }

    var symbol: String {
        let text = instruction.lowercased()
        if text.contains("rẽ trái") || text.contains("turn left") || text.contains("quẹo trái") {
            return "arrow.turn.up.left"
        }
        if text.contains("rẽ phải") || text.contains("turn right") || text.contains("quẹo phải") {
            return "arrow.turn.up.right"
        }
        if text.contains("vòng xuyến") || text.contains("roundabout") {
            return "arrow.triangle.turn.up.right.circle"
        }
        if text.contains("cao tốc") || text.contains("highway") || text.contains("motorway") {
            return "road.lanes"
        }
        if text.contains("đến nơi") || text.contains("arrive") || text.contains("điểm đến") {
            return "flag.checkered"
        }
        if text.contains("phà") || text.contains("ferry") {
            return "ferry.fill"
        }
        return "arrow.up"
    }
}

struct RouteOption: Identifiable {
    let id = UUID()
    let name: String
    let distance: Double
    var expectedTravelTime: TimeInterval
    let coordinates: [CLLocationCoordinate2D]
    let steps: [RouteStep]
    let mode: TravelMode
    var advisoryNotices: [String]

    /// Nhà cung cấp đã tính tuyến.
    var provider: RouteProviderKind = .apple
    /// Chi phí cầu đường (đồng) nếu nhà cung cấp trả về.
    var tollCost: Int? = nil
    /// `true` khi tuyến xe máy phải ước lượng từ hồ sơ ô tô của Apple Maps.
    var isEstimatedProfile: Bool = false

    var formattedDistance: String { Format.distance(distance) }
    var formattedDuration: String { Format.duration(expectedTravelTime) }

    /// Ước lượng tốc độ trung bình, dùng để so sánh các tuyến.
    var averageSpeed: Double {
        guard expectedTravelTime > 0 else { return 0 }
        return distance / expectedTravelTime // m/s
    }

    /// Tốc độ trung bình theo km/h (dễ đọc hơn cho người dùng).
    var averageSpeedKmh: Double { averageSpeed * 3.6 }

    /// Giờ tới nơi (giờ hiện tại + thời gian dự kiến).
    func arrivalText(from date: Date = Date()) -> String? {
        Format.arrival(after: expectedTravelTime, from: date)
    }

    var tollCostText: String? {
        guard let tollCost, tollCost > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        let number = formatter.string(from: NSNumber(value: tollCost)) ?? "\(tollCost)"
        return "\(number) đ"
    }
}

// MARK: - Định dạng hiển thị

enum Format {
    static func distance(_ meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "—" }
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        let km = meters / 1000
        if km < 10 {
            return String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",")
        }
        return "\(Int(km.rounded())) km"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds < 60 { return "dưới 1 phút" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "dưới 1 phút" }
        if minutes < 60 { return "\(minutes) phút" }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 { return "\(hours) giờ" }
        return "\(hours) giờ \(rest) phút"
    }

    static func coordinates(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    /// "48 km/h"
    static func speed(_ kmh: Double) -> String {
        guard kmh.isFinite, kmh >= 0 else { return "0 km/h" }
        return "\(Int(kmh.rounded())) km/h"
    }

    /// Giờ tới nơi dạng "14:35" (24h). `nil` nếu thời lượng không hợp lệ.
    static func arrival(after seconds: TimeInterval, from now: Date = Date()) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let date = now.addingTimeInterval(seconds)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Thời lượng còn lại đã trừ phần đã đi: "12 phút".
    static func remaining(_ seconds: TimeInterval) -> String {
        duration(max(0, seconds))
    }

    /// Khoảng cách ngắn gọn cho thanh tốc độ / nhãn trên bản đồ: "320 m", "1,4 km".
    static func hudDistance(_ meters: Double) -> String {
        guard meters.isFinite, meters > 0 else { return "0 m" }
        if meters < 950 {
            return "\(Int((meters / 10).rounded()) * 10) m"
        }
        return distance(meters)
    }
}

// MARK: - Thành phố / vùng có sẵn

struct MapPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    var shortName: String {
        name.replacingOccurrences(of: "TP. ", with: "").replacingOccurrences(of: "Thành phố ", with: "")
    }

    static let vietnam = MapPreset(
        id: "vn",
        name: "Việt Nam",
        latitude: 16.30,
        longitude: 106.30,
        latitudeDelta: 13.5,
        longitudeDelta: 8.5
    )

    static let cities: [MapPreset] = [
        MapPreset(id: "hanoi", name: "Hà Nội", latitude: 21.0285, longitude: 105.8542,
                  latitudeDelta: 0.12, longitudeDelta: 0.12),
        MapPreset(id: "hcm", name: "TP. Hồ Chí Minh", latitude: 10.7769, longitude: 106.7009,
                  latitudeDelta: 0.14, longitudeDelta: 0.14),
        MapPreset(id: "danang", name: "Đà Nẵng", latitude: 16.0544, longitude: 108.2022,
                  latitudeDelta: 0.09, longitudeDelta: 0.09),
        MapPreset(id: "haiphong", name: "Hải Phòng", latitude: 20.8449, longitude: 106.6881,
                  latitudeDelta: 0.10, longitudeDelta: 0.10),
        MapPreset(id: "cantho", name: "Cần Thơ", latitude: 10.0452, longitude: 105.7469,
                  latitudeDelta: 0.10, longitudeDelta: 0.10),
        MapPreset(id: "hue", name: "Huế", latitude: 16.4637, longitude: 107.5909,
                  latitudeDelta: 0.09, longitudeDelta: 0.09),
        MapPreset(id: "nhatrang", name: "Nha Trang", latitude: 12.2388, longitude: 109.1967,
                  latitudeDelta: 0.08, longitudeDelta: 0.08),
        MapPreset(id: "dalat", name: "Đà Lạt", latitude: 11.9404, longitude: 108.4583,
                  latitudeDelta: 0.08, longitudeDelta: 0.08),
        MapPreset(id: "halong", name: "Hạ Long", latitude: 20.9599, longitude: 107.0425,
                  latitudeDelta: 0.09, longitudeDelta: 0.09),
        MapPreset(id: "phuquoc", name: "Phú Quốc", latitude: 10.2270, longitude: 103.9640,
                  latitudeDelta: 0.16, longitudeDelta: 0.16),
        MapPreset(id: "sapa", name: "Sa Pa", latitude: 22.3364, longitude: 103.8438,
                  latitudeDelta: 0.09, longitudeDelta: 0.09),
        MapPreset(id: "quynhon", name: "Quy Nhơn", latitude: 13.7829, longitude: 109.2196,
                  latitudeDelta: 0.08, longitudeDelta: 0.08)
    ]
}

// MARK: - Danh mục địa điểm gần đây

struct NearbyCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let category: MKPointOfInterestCategory
    let query: String

    static func == (lhs: NearbyCategory, rhs: NearbyCategory) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static let all: [NearbyCategory] = [
        NearbyCategory(id: "food", title: "Ăn uống", symbol: "fork.knife",
                       category: .restaurant, query: "quán ăn"),
        NearbyCategory(id: "cafe", title: "Cà phê", symbol: "cup.and.saucer.fill",
                       category: .cafe, query: "quán cà phê"),
        NearbyCategory(id: "fuel", title: "Xăng", symbol: "fuelpump.fill",
                       category: .gasStation, query: "trạm xăng"),
        NearbyCategory(id: "hotel", title: "Khách sạn", symbol: "bed.double.fill",
                       category: .hotel, query: "khách sạn"),
        NearbyCategory(id: "hospital", title: "Bệnh viện", symbol: "cross.case.fill",
                       category: .hospital, query: "bệnh viện"),
        NearbyCategory(id: "pharmacy", title: "Nhà thuốc", symbol: "pills.fill",
                       category: .pharmacy, query: "nhà thuốc"),
        NearbyCategory(id: "atm", title: "ATM", symbol: "creditcard.fill",
                       category: .atm, query: "ATM"),
        NearbyCategory(id: "bank", title: "Ngân hàng", symbol: "building.columns.fill",
                       category: .bank, query: "ngân hàng"),
        NearbyCategory(id: "store", title: "Siêu thị", symbol: "cart.fill",
                       category: .store, query: "siêu thị"),
        NearbyCategory(id: "parking", title: "Đỗ xe", symbol: "parkingsign.circle.fill",
                       category: .parking, query: "bãi đỗ xe"),
        NearbyCategory(id: "sight", title: "Tham quan", symbol: "camera.fill",
                       category: .museum, query: "điểm tham quan"),
        NearbyCategory(id: "park", title: "Công viên", symbol: "tree.fill",
                       category: .park, query: "công viên"),
        NearbyCategory(id: "beach", title: "Biển", symbol: "beach.umbrella.fill",
                       category: .beach, query: "bãi biển"),
        NearbyCategory(id: "airport", title: "Sân bay", symbol: "airplane",
                       category: .airport, query: "sân bay")
    ]

    /// Truy cập nhanh theo mã — dùng khi lập kế hoạch điểm dừng dọc tuyến.
    static func named(_ id: String) -> NearbyCategory? {
        all.first { $0.id == id }
    }

    static var fuel: NearbyCategory { named("fuel") ?? all[0] }
    static var cafe: NearbyCategory { named("cafe") ?? all[0] }
    static var food: NearbyCategory { named("food") ?? all[0] }
}

// MARK: - Thông tin app

struct AppInfo {
    let version: String
    let build: String
    let commit: String
    let bundleIdentifier: String

    static let current = AppInfo()

    init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        func value(_ key: String, fallback: String) -> String {
            guard let raw = info[key] as? String else { return fallback }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("$(") { return fallback }
            return trimmed
        }
        version = value("CFBundleShortVersionString", fallback: "1.0.0")
        build = value("CFBundleVersion", fallback: "1")
        commit = value("GitCommit", fallback: "local")
        bundleIdentifier = value("CFBundleIdentifier", fallback: "com.tradingleak.vietmap")
    }
}

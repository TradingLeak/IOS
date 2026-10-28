import Foundation
import CoreLocation

// MARK: - Loại cảnh báo

/// Các loại cảnh báo giao thông mà ứng dụng hiểu được.
/// `rawValue` trùng với trường `kind` trong `App/Resources/Data/vn_alerts.json`
/// và với schema mô tả trong `docs/ALERTS.md`.
enum AlertKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case speedCamera = "speed_camera"
    case redLightCamera = "red_light_camera"
    case surveillanceCamera = "surveillance_camera"
    case speedSign = "speed_sign"
    case speedZone = "speed_zone"
    case residentialZone = "residential_zone"
    case noOvertake = "no_overtake"
    case tollStation = "toll_station"
    case schoolZone = "school_zone"
    case checkpoint = "checkpoint"
    case hazard = "hazard"
    case other = "other"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speedCamera: return "Camera bắn tốc độ"
        case .redLightCamera: return "Camera đèn đỏ"
        case .surveillanceCamera: return "Camera giám sát"
        case .speedSign: return "Biển báo tốc độ"
        case .speedZone: return "Vùng giới hạn tốc độ"
        case .residentialZone: return "Khu đông dân cư"
        case .noOvertake: return "Cấm vượt"
        case .tollStation: return "Trạm thu phí"
        case .schoolZone: return "Khu vực trường học"
        case .checkpoint: return "Kiểm tra tốc độ"
        case .hazard: return "Sự cố / ngập"
        case .other: return "Cảnh báo khác"
        }
    }

    /// Nhãn ngắn dùng trên chip / bản đồ.
    var shortTitle: String {
        switch self {
        case .speedCamera: return "Bắn tốc độ"
        case .redLightCamera: return "Đèn đỏ"
        case .surveillanceCamera: return "Giám sát"
        case .speedSign: return "Biển tốc độ"
        case .speedZone: return "Vùng tốc độ"
        case .residentialZone: return "Khu dân cư"
        case .noOvertake: return "Cấm vượt"
        case .tollStation: return "Thu phí"
        case .schoolZone: return "Trường học"
        case .checkpoint: return "Kiểm tra"
        case .hazard: return "Sự cố"
        case .other: return "Khác"
        }
    }

    var symbol: String {
        switch self {
        case .speedCamera: return "camera.fill"
        case .redLightCamera: return "light.beacon.max.fill"
        case .surveillanceCamera: return "video.fill"
        case .speedSign: return "speedometer"
        case .speedZone: return "gauge.with.dots.needle.67percent"
        case .residentialZone: return "house.fill"
        case .noOvertake: return "arrow.left.arrow.right"
        case .tollStation: return "road.lanes"
        case .schoolZone: return "figure.2.and.child.holdinghands"
        case .checkpoint: return "shield.lefthalf.filled"
        case .hazard: return "exclamationmark.triangle.fill"
        case .other: return "bell.fill"
        }
    }

    /// Cảnh báo có kèm giới hạn tốc độ (km/h) hay không.
    var carriesSpeedLimit: Bool {
        switch self {
        case .speedSign, .speedZone, .residentialZone: return true
        case .speedCamera, .schoolZone, .checkpoint, .redLightCamera,
             .surveillanceCamera, .noOvertake, .tollStation, .hazard, .other:
            return false
        }
    }

    var isCamera: Bool {
        switch self {
        case .speedCamera, .redLightCamera, .surveillanceCamera: return true
        default: return false
        }
    }

    /// Cảnh báo nguy hiểm: cần ưu tiên hiển thị và đọc lên.
    var isSafetyCritical: Bool {
        switch self {
        case .speedCamera, .redLightCamera, .speedZone, .speedSign,
             .residentialZone, .noOvertake, .schoolZone, .hazard, .checkpoint:
            return true
        default:
            return false
        }
    }

    /// Nhóm hiển thị trong Cài đặt.
    static let cameraKinds: [AlertKind] = [.speedCamera, .redLightCamera, .surveillanceCamera]
    static let speedKinds: [AlertKind] = [.speedSign, .speedZone, .residentialZone, .noOvertake]
    static let otherKinds: [AlertKind] = [.tollStation, .schoolZone, .checkpoint, .hazard, .other]
}

// MARK: - Một cảnh báo cụ thể

struct RoadAlert: Identifiable, Codable, Hashable {
    let id: String
    let kind: AlertKind
    let latitude: Double
    let longitude: Double

    var speedLimit: Int?
    var bearing: Double?
    var length: Double?
    var road: String?
    var name: String?
    var district: String?
    var ward: String?
    var detail: String?
    var imageUrl: String?
    var videoUrl: String?
    var confidence: Double?
    var source: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let road, !road.isEmpty { return road }
        return kind.title
    }

    var displaySubtitle: String {
        var parts: [String] = []
        if let detail, !detail.isEmpty { parts.append(detail) }
        if let road, !road.isEmpty, road != displayName { parts.append(road) }
        if let ward, !ward.isEmpty { parts.append(ward) }
        if let district, !district.isEmpty, district != ward { parts.append(district) }
        if let speedLimit { parts.insert("Giới hạn \(speedLimit) km/h", at: 0) }
        return parts.joined(separator: " · ")
    }

    var updatedImageURL: URL? {
        guard let imageUrl else { return nil }
        let trimmed = imageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http") else { return nil }
        return URL(string: trimmed)
    }

    var updatedVideoURL: URL? {
        guard let videoUrl else { return nil }
        let trimmed = videoUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http") else { return nil }
        return URL(string: trimmed)
    }

    // MARK: - Mã hoá

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case latitude = "lat"
        case longitude = "lng"
        case speedLimit
        case bearing
        case length
        case road
        case name
        case district
        case ward
        case detail
        case imageUrl
        case videoUrl
        case confidence
        case source
    }

    init(id: String = UUID().uuidString,
         kind: AlertKind,
         latitude: Double,
         longitude: Double,
         speedLimit: Int? = nil,
         bearing: Double? = nil,
         length: Double? = nil,
         road: String? = nil,
         name: String? = nil,
         district: String? = nil,
         ward: String? = nil,
         detail: String? = nil,
         imageUrl: String? = nil,
         videoUrl: String? = nil,
         confidence: Double? = nil,
         source: String? = nil) {
        self.id = id
        self.kind = kind
        self.latitude = latitude
        self.longitude = longitude
        self.speedLimit = speedLimit
        self.bearing = bearing
        self.length = length
        self.road = road
        self.name = name
        self.district = district
        self.ward = ward
        self.detail = detail
        self.imageUrl = imageUrl
        self.videoUrl = videoUrl
        self.confidence = confidence
        self.source = source
    }

    /// Đọc được cả dữ liệu của app lẫn tệp JSON do người dùng nhập tay:
    /// `kind` lạ → `.other`, `speedLimit` có thể là số hoặc chuỗi.
    /// Không ném lỗi vì toạ độ sai: dòng lỗi bị bỏ qua ở `AlertDatabase`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawID = Self.flexibleString(container, .id)
        id = rawID ?? UUID().uuidString
        kind = AlertKind(rawValue: (Self.flexibleString(container, .kind) ?? "").lowercased()) ?? .other

        latitude = Self.flexibleDouble(container, .latitude) ?? 0
        longitude = Self.flexibleDouble(container, .longitude) ?? 0
        speedLimit = Self.flexibleInt(container, .speedLimit)
        bearing = Self.flexibleDouble(container, .bearing)
        length = Self.flexibleDouble(container, .length)
        road = Self.flexibleString(container, .road)
        name = Self.flexibleString(container, .name)
        district = Self.flexibleString(container, .district)
        ward = Self.flexibleString(container, .ward)
        detail = Self.flexibleString(container, .detail)
        imageUrl = Self.flexibleString(container, .imageUrl)
        videoUrl = Self.flexibleString(container, .videoUrl)
        confidence = Self.flexibleDouble(container, .confidence)
        source = Self.flexibleString(container, .source)
    }

    /// `false` với dòng dữ liệu hỏng (toạ độ ngoài Trái Đất, 0,0...).
    var hasValidCoordinate: Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && abs(latitude) <= 90
            && abs(longitude) <= 180
            && !(latitude == 0 && longitude == 0)
    }

    private static func flexibleDouble(_ container: KeyedDecodingContainer<CodingKeys>,
                                       _ key: CodingKeys) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
        if let text = try? container.decode(String.self, forKey: key) {
            return Double(text.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    private static func flexibleInt(_ container: KeyedDecodingContainer<CodingKeys>,
                                    _ key: CodingKeys) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(Double.self, forKey: key) { return Int(value.rounded()) }
        if let text = try? container.decode(String.self, forKey: key) {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func flexibleString(_ container: KeyedDecodingContainer<CodingKeys>,
                                       _ key: CodingKeys) -> String? {
        if let text = try? container.decode(String.self, forKey: key) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
}

// MARK: - Bộ dữ liệu

struct AlertSource: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var url: String?
    var license: String?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id, name, url, license, note
    }

    init(id: String, name: String, url: String? = nil, license: String? = nil, note: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.license = license
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = UUID().uuidString
        id = (try? container.decode(String.self, forKey: .id)) ?? fallback
        name = (try? container.decode(String.self, forKey: .name)) ?? id
        url = try? container.decode(String.self, forKey: .url)
        license = try? container.decode(String.self, forKey: .license)
        note = try? container.decode(String.self, forKey: .note)
    }
}

struct AlertDataset: Codable {
    var schema: Int?
    var version: String?
    var generatedAt: String?
    var sources: [AlertSource]?
    var counts: [String: Int]?
    var alerts: [RoadAlert]

    enum CodingKeys: String, CodingKey {
        case schema, version, generatedAt, sources, counts, alerts
    }

    init(schema: Int? = 2,
         version: String? = nil,
         generatedAt: String? = nil,
         sources: [AlertSource]? = nil,
         counts: [String: Int]? = nil,
         alerts: [RoadAlert]) {
        self.schema = schema
        self.version = version
        self.generatedAt = generatedAt
        self.sources = sources
        self.counts = counts
        self.alerts = alerts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try? container.decode(Int.self, forKey: .schema)
        version = try? container.decode(String.self, forKey: .version)
        generatedAt = try? container.decode(String.self, forKey: .generatedAt)
        sources = try? container.decode([AlertSource].self, forKey: .sources)
        counts = try? container.decode([String: Int].self, forKey: .counts)
        alerts = (try? container.decode([RoadAlert].self, forKey: .alerts)) ?? []
    }
}

// MARK: - Cảnh báo đang hoạt động (đã tính khoảng cách)

struct ActiveAlert: Identifiable, Hashable {
    let alert: RoadAlert
    /// Khoảng cách theo đường tới điểm cảnh báo (mét); âm = đã đi qua.
    let distance: Double
    /// Ngưỡng cảnh báo động D_warn (mét).
    let warnDistance: Double
    /// Vị trí trên tuyến (mét từ điểm đi).
    let distanceAlongRoute: Double

    var id: String { alert.id }

    var isAhead: Bool { distance >= -10 }
    var isImminent: Bool { distance >= -10 && distance <= warnDistance }

    /// Chia 3 mức để tô màu: xa / đang tới / rất gần.
    var level: Level {
        if distance < 0 { return .passed }
        if distance <= warnDistance * 0.45 { return .close }
        if distance <= warnDistance { return .approaching }
        return .far
    }

    enum Level {
        case far
        case approaching
        case close
        case passed
    }
}

// MARK: - Ngữ cảnh tốc độ

enum SpeedLimitSource: String {
    case sign = "Biển báo"
    case zone = "Vùng giới hạn"
    case imported = "Dữ liệu nhập"
    case estimated = "Ước tính TT 38/2024"
    case unknown = "Chưa xác định"
}

struct SpeedLimitInfo: Equatable {
    var limit: Int?
    var source: SpeedLimitSource
    var alertID: String?
    var roadName: String?

    static let unknown = SpeedLimitInfo(limit: nil, source: .unknown, alertID: nil, roadName: nil)
}

struct SpeedContext {
    var speedKmh: Double = 0
    var limit: Int?
    var limitSource: SpeedLimitSource = .unknown
    var roadName: String?
    var tolerance: Int = 5
    var nextAlert: ActiveAlert?

    var overspeed: Double {
        guard let limit else { return 0 }
        return max(0, speedKmh - Double(limit))
    }

    var isOverLimit: Bool {
        guard let limit else { return false }
        return speedKmh > Double(limit) + Double(tolerance)
    }

    var isHardOverspeed: Bool {
        guard let limit else { return false }
        return speedKmh > Double(limit) + 15
    }
}

// MARK: - Tuỳ chọn cảnh báo

struct AlertPreferences: Equatable {
    var voiceEnabled: Bool = true
    var speakOnlyCritical: Bool = true
    var hudAutoOpen: Bool = true
    var showOnMap: Bool = true
    var overspeedTolerance: Int = 5
    var enabledKinds: Set<AlertKind> = Set(AlertKind.allCases)
    /// Ngưỡng D_warn tối thiểu / tối đa (mét) — lấy theo công thức của HUD Việt Nam.
    var warnDistanceMin: Double = 150
    var warnDistanceMax: Double = 500

    func isEnabled(_ kind: AlertKind) -> Bool {
        enabledKinds.contains(kind)
    }

    static let all = AlertPreferences()
}

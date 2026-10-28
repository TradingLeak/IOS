import Foundation

/// Loại đường — dùng để tra bảng tốc độ mặc định.
enum RoadClass: String, CaseIterable {
    case expressway
    case nationalHighway
    case provincialRoad
    case urbanStreet
    case residential
    case other

    var title: String {
        switch self {
        case .expressway: return "Đường cao tốc"
        case .nationalHighway: return "Quốc lộ"
        case .provincialRoad: return "Tỉnh lộ"
        case .urbanStreet: return "Đường đô thị"
        case .residential: return "Hẻm / ngõ"
        case .other: return "Đường khác"
        }
    }

    /// Cao tốc, quốc lộ, tỉnh lộ mặc định coi là ngoài khu đông dân cư.
    var defaultArea: RoadArea {
        switch self {
        case .expressway, .nationalHighway, .provincialRoad: return .rural
        case .urbanStreet, .residential, .other: return .urban
        }
    }
}

/// Nhóm phương tiện hai bánh — quyết định bảng tốc độ áp dụng.
///
/// - `motorcycle` (xe mô tô, xe máy > 50 cm³): theo bảng 60/50 – 70/60.
/// - `moped` (xe gắn máy ≤ 50 cm³, xe đạp điện): **40 km/h** trên mọi tuyến
///   không phải đường cao tốc (Điều 8 Thông tư 38/2024/TT-BGTVT).
enum VehicleClass: String, CaseIterable, Codable, Identifiable {
    case motorcycle
    case moped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .motorcycle: return "Xe mô tô / xe máy trên 50 cm³"
        case .moped: return "Xe gắn máy ≤ 50 cm³, xe đạp điện"
        }
    }

    var shortTitle: String {
        switch self {
        case .motorcycle: return "Xe mô tô"
        case .moped: return "Xe gắn máy"
        }
    }
}

enum RoadArea: String, CaseIterable {
    case urban
    case rural

    var title: String {
        switch self {
        case .urban: return "Khu vực đông dân cư"
        case .rural: return "Ngoài khu vực đông dân cư"
        }
    }
}

/// Bảng tốc độ khai thác tối đa theo **Thông tư 38/2024/TT-BGTVT** (hiệu lực 01/01/2025).
///
/// Đây là **giới hạn luật định mặc định** khi không có biển báo thực tế:
/// - Xe mô tô (xe máy trên 50 cm³): trong khu đông dân cư 60 km/h (đường đôi / ≥2 làn)
///   hoặc 50 km/h; ngoài khu đông dân cư 70 km/h hoặc 60 km/h.
/// - Xe gắn máy ≤ 50 cm³ và xe đạp điện: **40 km/h** trên mọi tuyến (không được đi cao tốc).
/// - Ô tô con: trong khu đông dân cư 60 / 50; ngoài khu đông dân cư 90 / 80; cao tốc tối đa 120.
///
/// Biển báo/vùng giới hạn thật (nhập tay hoặc tải từ OpenStreetMap) luôn được ưu tiên
/// hơn bảng này — xem `AlertEngine.speedLimit(...)`.
enum SpeedLimitRules {

    static func classify(_ roadName: String?) -> RoadClass {
        guard let roadName, !roadName.isEmpty else { return .other }
        let text = roadName.lowercased()

        func contains(_ needles: [String]) -> Bool {
            needles.contains { text.contains($0) }
        }

        if contains(["cao tốc", "cao toc", "đường trên cao", "duong tren cao", "ct.", "ct ", "ct0", "ct1", "ct2"]) {
            return .expressway
        }
        if contains(["quốc lộ", "quoc lo", "ql.", "ql ", "ql1", "đại lộ", "dai lo"]) {
            return .nationalHighway
        }
        if contains(["tỉnh lộ", "tinh lo", "đt.", "dt.", "đường tỉnh", "duong tinh"]) {
            return .provincialRoad
        }
        if contains(["hẻm", "hem ", "ngõ", "ngo ", "kiệt", "kiet ", "hxh"]) {
            return .residential
        }
        if contains(["phố", "pho ", "đường", "duong ", "street", "road"]) {
            return .urbanStreet
        }
        return .other
    }

    /// Tốc độ tối đa theo luật. `nil` = không áp dụng (đi bộ, xe buýt, hoặc xe máy trên cao tốc).
    static func legalLimit(roadClass: RoadClass,
                           area: RoadArea,
                           mode: TravelMode,
                           dualCarriageway: Bool = false,
                           vehicle: VehicleClass = .motorcycle) -> Int? {
        switch mode {
        case .walking, .transit:
            return nil

        case .motorcycle:
            // Xe hai bánh không được phép chạy trên đường cao tốc.
            if roadClass == .expressway { return nil }
            // Xe gắn máy ≤ 50 cm³: một mức 40 km/h cho mọi loại đường.
            if vehicle == .moped { return 40 }
            switch (area, dualCarriageway) {
            case (.urban, true): return 60
            case (.urban, false): return 50
            case (.rural, true): return 70
            case (.rural, false): return 60
            }

        case .automobile:
            switch roadClass {
            case .expressway: return 120
            default:
                switch (area, dualCarriageway) {
                case (.urban, true): return 60
                case (.urban, false): return 50
                case (.rural, true): return 90
                case (.rural, false): return 80
                }
            }
        }
    }

    /// Suy ra giới hạn tốc độ từ danh sách tên đường (ưu tiên tên đầu tiên nhận diện được).
    static func estimate(roadNames: [String],
                         mode: TravelMode,
                         vehicle: VehicleClass = .motorcycle) -> Int? {
        for name in roadNames {
            let roadClass = classify(name)
            guard roadClass != .other else { continue }
            let limit = legalLimit(roadClass: roadClass,
                                   area: roadClass.defaultArea,
                                   mode: mode,
                                   dualCarriageway: isDualCarriageway(name),
                                   vehicle: vehicle)
            if let limit { return limit }
        }
        return nil
    }

    /// Đoán đường đôi: tên có "đại lộ", "vành đai", "cao tốc", "quốc lộ", "đường đôi".
    static func isDualCarriageway(_ roadName: String) -> Bool {
        let text = roadName.lowercased()
        let needles = ["đại lộ", "dai lo", "vành đai", "vanh dai", "cao tốc", "cao toc",
                       "quốc lộ", "quoc lo", "đường đôi", "duong doi", "boulevard"]
        return needles.contains { text.contains($0) }
    }

    /// Lấy tên đường từ câu chỉ dẫn của Apple Maps: "Rẽ phải vào Đường Láng".
    static func roadName(in instruction: String) -> String? {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        for marker in [" vào ", " trên ", " theo ", " tới ", " đến "] {
            guard let range = text.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }
            var candidate = String(text[range.upperBound...])
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if let comma = candidate.firstIndex(of: ",") {
                candidate = String(candidate[..<comma])
            }
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.count >= 3 {
                return String(candidate.prefix(60))
            }
        }

        // Không có động từ rẽ → có thể câu chỉ dẫn chỉ là tên đường ("Đường Láng").
        if classify(text) != .other, text.count <= 60 {
            return text
        }
        return nil
    }

    /// Cảnh báo cố định cho xe máy khi tuyến đi vào đường cao tốc.
    static let motorcycleExpresswayNotice =
        "Xe máy không được phép đi trên đường cao tốc. Tuyến này có đoạn cao tốc — hãy kiểm tra lại hoặc dùng tuyến khác."
}

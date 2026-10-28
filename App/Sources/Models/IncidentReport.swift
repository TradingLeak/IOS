import Foundation
import CoreLocation

// MARK: - Loại sự cố người lái báo trên đường

/// Sự cố người dùng tự báo khi đang lái (cảnh sát, tai nạn, ngập, ổ gà, cấm đường, kẹt xe).
///
/// App **không có máy chủ**: báo cáo được lưu trên máy, hiển thị trên bản đồ và được đọc lên
/// khi bạn tới gần — hữu ích cho chính bạn và khi dùng chung máy với người khác. Mỗi loại có
/// thời hạn riêng để báo cũ tự biến mất.
enum IncidentKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case police
    case accident
    case flooding
    case pothole
    case roadClosed
    case trafficJam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .police: return "CSGT / kiểm tra"
        case .accident: return "Tai nạn"
        case .flooding: return "Ngập nước"
        case .pothole: return "Ổ gà / mặt đường xấu"
        case .roadClosed: return "Cấm đường / thi công"
        case .trafficJam: return "Kẹt xe"
        }
    }

    /// Nhãn ngắn cho marker / danh sách.
    var shortTitle: String {
        switch self {
        case .police: return "CSGT"
        case .accident: return "Tai nạn"
        case .flooding: return "Ngập"
        case .pothole: return "Ổ gà"
        case .roadClosed: return "Cấm đường"
        case .trafficJam: return "Kẹt xe"
        }
    }

    var symbol: String {
        switch self {
        case .police: return "shield.lefthalf.filled"
        case .accident: return "car.2.fill"
        case .flooding: return "drop.fill"
        case .pothole: return "exclamationmark.triangle.fill"
        case .roadClosed: return "nosign"
        case .trafficJam: return "car.fill"
        }
    }

    /// Câu đọc lên khi tới gần.
    var spokenWarning: String {
        switch self {
        case .police: return "Chú ý, phía trước có CSGT hoặc chốt kiểm tra."
        case .accident: return "Chú ý, phía trước có tai nạn."
        case .flooding: return "Chú ý, phía trước có điểm ngập nước."
        case .pothole: return "Chú ý, mặt đường xấu phía trước."
        case .roadClosed: return "Chú ý, phía trước có thể cấm đường."
        case .trafficJam: return "Chú ý, phía trước đang kẹt xe."
        }
    }

    /// Loại cảnh báo tương ứng khi vẽ lên bản đồ / lọc theo tuỳ chọn cảnh báo.
    var alertKind: AlertKind {
        switch self {
        case .police, .roadClosed: return .checkpoint
        case .accident, .flooding: return .hazard
        case .pothole, .trafficJam: return .other
        }
    }

    /// Báo cáo sống bao lâu thì tự biến mất.
    var lifetime: TimeInterval {
        switch self {
        case .police: return 45 * 60
        case .accident: return 3 * 3600
        case .flooding: return 6 * 3600
        case .pothole: return 7 * 24 * 3600
        case .roadClosed: return 24 * 3600
        case .trafficJam: return 30 * 60
        }
    }

    var lifetimeText: String {
        let seconds = lifetime
        if seconds < 3600 { return "\(Int(seconds / 60)) phút" }
        if seconds < 24 * 3600 { return "\(Int(seconds / 3600)) giờ" }
        return "\(Int(seconds / (24 * 3600))) ngày"
    }
}

// MARK: - Một báo cáo

struct IncidentReport: Identifiable, Codable, Hashable {
    let id: String
    let kind: IncidentKind
    let latitude: Double
    let longitude: Double
    let createdAt: Date
    var note: String?

    init(kind: IncidentKind,
         coordinate: CLLocationCoordinate2D,
         note: String? = nil,
         createdAt: Date = Date(),
         id: String = UUID().uuidString) {
        self.id = id
        self.kind = kind
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.createdAt = createdAt

        // Ghi chú sạch: bỏ khoảng trắng thừa, rỗng thì coi như không có.
        let cleaned = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = (cleaned?.isEmpty ?? true) ? nil : cleaned
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var expiresAt: Date {
        createdAt.addingTimeInterval(kind.lifetime)
    }

    var isExpired: Bool {
        Date() >= expiresAt
    }

    /// Thời gian còn lại, dạng ngắn: "còn 25 phút".
    var remainingText: String {
        let seconds = expiresAt.timeIntervalSinceNow
        guard seconds > 0 else { return "đã hết hạn" }
        if seconds < 3600 { return "còn \(max(1, Int(seconds / 60))) phút" }
        if seconds < 24 * 3600 { return "còn \(Int(seconds / 3600)) giờ" }
        return "còn \(Int(seconds / (24 * 3600))) ngày"
    }

    var title: String {
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return note
        }
        return kind.title
    }

    var subtitle: String {
        "\(kind.shortTitle) · \(remainingText)"
    }

    /// 2 khi vừa báo (đáng chú ý nhất), 1 khi đã cũ.
    var severityHint: Int {
        Date().timeIntervalSince(createdAt) < 20 * 60 ? 2 : 1
    }

    func distance(from coordinate: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}

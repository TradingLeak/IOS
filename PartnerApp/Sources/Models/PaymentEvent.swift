import Foundation

/// Loại khoản tiền phát sinh mà app theo dõi để báo cho người dùng.
enum PaymentKind: String, Codable {
    /// Hoa hồng đối tác được ghi có theo ngày (từ báo cáo rewards).
    case reward
    /// Hoàn phí (autorebate) đã trả cho khách hàng.
    case rebateProcessed
    /// Hoàn phí bị từ chối.
    case rebateRejected
    /// Hoàn phí gặp lỗi khi xử lý.
    case rebateError

    var title: String {
        switch self {
        case .reward: return "Hoa hồng mới đã trả"
        case .rebateProcessed: return "Đã trả hoàn phí cho khách"
        case .rebateRejected: return "Hoàn phí bị từ chối"
        case .rebateError: return "Hoàn phí gặp lỗi"
        }
    }

    var symbol: String {
        switch self {
        case .reward: return "dollarsign.circle.fill"
        case .rebateProcessed: return "arrow.counterclockwise.circle.fill"
        case .rebateRejected: return "xmark.octagon.fill"
        case .rebateError: return "exclamationmark.triangle.fill"
        }
    }

    /// Khoản tiền thực sự về tài khoản (còn lại là cảnh báo cần xử lý).
    var isPositive: Bool {
        switch self {
        case .reward, .rebateProcessed: return true
        case .rebateRejected, .rebateError: return false
        }
    }
}

/// Một khoản thanh toán mới phát hiện được — dùng cho pop-up và thông báo hệ thống.
struct PaymentEvent: Identifiable, Equatable {
    let id: String
    let kind: PaymentKind
    let amountUSD: Decimal
    let dateText: String
    let detail: String
    let sortDate: Date?

    var amountText: String {
        Fmt.usd(amountUSD)
    }

    var notificationBody: String {
        let parts = [amountText, dateText, detail].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}

/// Dấu vết các khoản đã biết, dùng để so sánh với lần kiểm tra sau.
struct PaymentSnapshot: Codable, Equatable {
    var rewardDates: Set<String>
    var rebatePaymentIDs: Set<Int>
    var lastChecked: Date

    init(rewardDates: Set<String> = [],
         rebatePaymentIDs: Set<Int> = [],
         lastChecked: Date = Date()) {
        self.rewardDates = rewardDates
        self.rebatePaymentIDs = rebatePaymentIDs
        self.lastChecked = lastChecked
    }
}

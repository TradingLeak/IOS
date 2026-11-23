import Foundation

// MARK: - Trang liên kết mặc định (kiểm tra kết nối)

struct DefaultLink: Decodable {
    let fullDefaultLink: String
    let domain: String
    let code: String
    let path: String
    let url: String
}

// MARK: - Reward history (hoa hồng)

struct RewardReport: Decodable {
    let data: [RewardRow]
    let totals: RewardTotals
}

struct RewardRow: Decodable {
    let rewardDate: String
    let rewardUsd: String
    let reward: String?
    let volumeLots: Double
    let volumeMlnUsd: Double?
    let ordersCount: Int
    let currency: String?
    let clientAccount: String?
    let clientAccountType: String?
    let clientUid: String?
    let country: String?
    let platform: String?
    let linkCode: String?
    let partnerAccount: String?
    let partnerAccountName: String?
    let subpartnerAccount: String?

    var rewardUsdDecimal: Decimal {
        Decimal(apiString: rewardUsd) ?? 0
    }
}

struct RewardTotals: Decodable {
    let count: Int
    let volumeLots: Double
    let volumeMlnUsd: Double?
    let reward: String?
    let rewardUsd: String
    let ordersCount: Int
    let currency: [String]?

    var rewardUsdDecimal: Decimal {
        Decimal(apiString: rewardUsd) ?? 0
    }
}

// MARK: - Clients report (khách hàng)

struct ClientReport: Decodable {
    let data: [ClientRow]
    let totals: ClientTotals
}

struct ClientRow: Decodable {
    let clientUid: String
    let regDate: String
    let clientCountry: String
    let volumeLots: Double
    let volumeMlnUsd: Double?
    let rewardUsd: String
    let tradeFn: String?
    let clientStatus: String?
    let kycPassed: Bool?
    let ftdReceived: Bool?
    let fttMade: Bool?
    let rebateAmountUsd: Double?
    let comment: String?

    var rewardUsdDecimal: Decimal {
        Decimal(apiString: rewardUsd) ?? 0
    }
}

struct ClientTotals: Decodable {
    let count: Int
    let volumeLots: Double
    let volumeMlnUsd: Double?
    let rewardUsd: String
    let availableForRequest: Int?
}

// MARK: - Client transactions (lệnh đã đóng)

struct OrderReport: Decodable {
    let data: [OrderRow]
    let totals: OrderTotals
}

struct OrderRow: Decodable {
    let symbol: String
    let formulaCode: String?
    let volumeLots: Double
    let volumeMlnUsd: Double?
    let reward: Double
    let rewardUsd: Double
    let currency: String?
    let openSpread: Double?
    let closeSpread: Double?
    let avgSpread: Double?
    let openDate: String?
    let closeDate: String
    let clientAccountType: String
    let date: String
    let partnerAccount: String?
    let clientAccount: String
    let orderId: String
}

struct OrderTotals: Decodable {
    let count: Int
    let volumeLots: Double
    let volumeMlnUsd: Double?
    let rewardUsd: Double
    let currency: [String]?
    let clientAccountType: [String]?
}

// MARK: - Transactions pending payment (chờ tính hoa hồng)

struct PendingReport: Decodable {
    let data: [PendingRow]
    let totals: PendingTotals
}

struct PendingRow: Decodable {
    let clientAccount: String
    let clientAccountType: String
    let countOrders: Int
    let volumeLots: Double
    let volumeMlnUsd: Double?
    let currency: String?
}

struct PendingTotals: Decodable {
    let count: Int
    let countOrders: Int
    let volumeLots: Double
    let volumeMlnUsd: Double?
}

// MARK: - Partner tier (cấp bậc)

struct TierState: Decodable {
    let clientsCount: Int
    let usdVolume: Double
    let subpartnersCount: Int
    let subpartnersUsdVolume: Double?
    let registeredDt: String?
    let tierId: Int
    let tierName: String
    let tierGroup: String?
    let tierOrder: Int?
    let gracePeriodStartDt: String?
    let gracePeriodFinishDt: String?
    let isSecondLvl: Bool?
    let isIb: Bool?
    let ibCandidate: IBCandidate?
    let commission: [String: [Int?]]?
    let qualificationTier: QualificationTier?
    let lastGracePeriodStatus: String?
}

struct IBCandidate: Decodable {
    let kycPassed: Bool?
    let clients: Bool?
    let readyForPromotion: Bool?
    let promoted: Bool?
}

struct QualificationTier: Decodable {
    let id: Int?
    let name: String?
    let group: String?
    let order: Int?
}

// MARK: - Rebate history (lịch sử hoàn phí)

struct RebateHistoryReport: Decodable {
    let data: [RebateHistoryRow]
    let totals: RebateHistoryTotals
}

struct RebateHistoryRow: Decodable {
    let id: Int
    let partnerAccount: String
    let clientAccount: String
    let clientAccountType: String?
    let rebateGroupTitle: String?
    let volumeLots: Double
    let reward: Double
    let rewardUsd: Double
    let rebate: Double
    let rebateUsd: Double
    let rebatePercent: Double
    let status: String
    let errorCode: String?
    let destinationClientAccount: String?
    let processedDate: String?
    let rewardDate: String
    let groupId: Int?
}

struct RebateHistoryTotals: Decodable {
    let clientsCount: Int
    let clientsApprovedCount: Int?
    let clientsRejectedCount: Int?
    let rewardUsd: Double
    let topayRebateUsd: Double
    let status: String?
    let rejectedRebateUsd: Double?
    let errorRebateUsd: Double?
    let processedRebateUsd: Double?
    let groupId: Int?
    let groupName: String?
    let clientsPendingCount: Int?
    let pendingRewardUsd: Double?
}

// MARK: - Rebate payments (thanh toán hoàn phí)

struct RebatePaymentsReport: Decodable {
    let data: [RebatePaymentRow]
    let totals: RebatePaymentTotals
}

struct RebatePaymentRow: Decodable {
    let id: Int
    let partnerAccount: String
    let status: String
    let clientAccount: String
    let clientAccountType: String?
    let destinationClientAccount: String?
    let reward: Double
    let rewardUsd: Double
    let volumeLots: Double
    let rebate: Double
    let rebateUsd: Double
    let processedDate: String?
    let errorCode: String?
}

struct RebatePaymentTotals: Decodable {
    let count: Int
    let reward: Double
    let rewardUsd: Double
    let volumeLots: Double
    let processedRebate: Double
    let processedRebateUsd: Double
    let rejectedRebateUsd: Double
    let errorRebateUsd: Double
}

// MARK: - Điểm biểu đồ

struct ChartPoint: Identifiable {
    let id = UUID()
    let label: String
    let sortKey: String
    let value: Double
    let detail: String
}

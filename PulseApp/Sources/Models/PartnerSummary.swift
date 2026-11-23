import Foundation

// MARK: - Tóm tắt đối tác (Partnership API) cho tab "Đối tác"

struct PartnerSummary: Equatable {
    var tierName: String
    var tierGroup: String?
    var clientsCount: Int
    var clientsVolumeLots: Double
    var usdVolume: Double
    var rewards30d: Decimal?
    var rewardRows: Int
    var lastRewardDate: String?
}

/// `GET /v1/partnership/partner-tier/partner-state`
struct PartnerTierState: Decodable {
    let clientsCount: Int
    let usdVolume: Double
    let subpartnersCount: Int
    let tierId: Int
    let tierName: String
    let tierGroup: String?
    let isIb: Bool?
}

/// `GET /v1/partnership/reports/rewards` (aggregate_by=day)
struct PartnerRewardReport: Decodable {
    let data: [PartnerRewardRow]
    let totals: PartnerRewardTotals
}

struct PartnerRewardRow: Decodable, Identifiable {
    let rewardDate: String
    let rewardUsd: String
    let volumeLots: Double
    let ordersCount: Int
    let clientAccount: String?
    let country: String?

    var id: String { rewardDate + "|" + (clientAccount ?? "") }
    var rewardUsdDecimal: Decimal { Decimal(apiString: rewardUsd) ?? 0 }
}

struct PartnerRewardTotals: Decodable {
    let count: Int
    let volumeLots: Double
    let rewardUsd: String
    let ordersCount: Int

    var rewardUsdDecimal: Decimal { Decimal(apiString: rewardUsd) ?? 0 }
}

/// `GET /v1/partnership/reports/clients`
struct PartnerClientReport: Decodable {
    let data: [PartnerClientRow]
    let totals: PartnerClientTotals
}

struct PartnerClientRow: Decodable, Identifiable {
    let clientUid: String
    let clientCountry: String
    let volumeLots: Double
    let rewardUsd: String
    let clientStatus: String?

    var id: String { clientUid }
}

struct PartnerClientTotals: Decodable {
    let count: Int
    let volumeLots: Double
    let rewardUsd: String
}

/// `GET /v1/partnership/partner/default-link` — dùng để kiểm tra kết nối.
struct PartnerDefaultLink: Decodable {
    let fullDefaultLink: String
    let code: String?
}

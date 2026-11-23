import Foundation

/// Client cho Trader API (Exness Trade API) — gọi qua gateway của tài khoản.
/// Mọi yêu cầu đều được ký bằng `EXN-*` headers (xem `ExnessClient`).
final class TradingClient {
    let client: ExnessClient
    let accountId: String
    private let iso: ISO8601DateFormatter

    init(client: ExnessClient, accountId: String) {
        self.client = client
        self.accountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
    }

    // MARK: - Discovery

    /// `GET /v1/trading/access-point?account_id=…` → host dùng cho WebSocket.
    func accessPoint() async throws -> String {
        let response = try await client.get(AccessPointResponse.self,
                                            path: "/v1/trading/access-point",
                                            query: [("account_id", accountId)])
        return PulseCredentials.normalizeAccessPoint(response.accessPoint)
    }

    // MARK: - Cấu hình tài khoản

    func account() async throws -> TradingAccountInfo {
        try await client.get(TradingAccountInfo.self,
                             path: "/v1/configuration/accounts/\(accountId)/account")
    }

    /// Danh sách mã có thể giao dịch trên tài khoản (schema tuỳ môi trường → parse thủ công).
    func instruments() async throws -> [String] {
        let data = try await client.data(path: "/v1/configuration/accounts/\(accountId)/instruments")
        return Self.parseInstruments(data)
    }

    static func parseInstruments(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var list: [Any] = []
        if let array = json as? [Any] {
            list = array
        } else if let dict = json as? [String: Any] {
            if let array = dict["instruments"] as? [Any] {
                list = array
            } else if let inner = dict["data"] as? [Any] {
                list = inner
            }
        }
        var names: [String] = []
        for item in list {
            if let name = item as? String {
                names.append(name)
            } else if let dict = item as? [String: Any] {
                for key in ["instrument", "symbol", "name", "code"] {
                    if let name = dict[key] as? String {
                        names.append(name)
                        break
                    }
                }
            }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }.sorted()
    }

    // MARK: - Trạng thái giao dịch

    func snapshot() async throws -> TradingSnapshot {
        try await client.get(TradingSnapshot.self,
                             path: "/v1/trading/accounts/\(accountId)/snapshot")
    }

    // MARK: - Nến giá

    /// Nến giá (`from` inclusive, `to` exclusive). Cộng thêm 1 nến ở `to` để lấy cả nến đang tạo.
    func candles(symbol: String,
                 timeframe: Timeframe,
                 count: Int? = nil,
                 priceType: String = "bid") async throws -> [Candle] {
        let n = max(count ?? timeframe.defaultCount, 1)
        let seconds = TimeInterval(timeframe.seconds)
        let to = Date().addingTimeInterval(seconds)
        let from = to.addingTimeInterval(-seconds * Double(n + 1))
        let response = try await client.get(CandleHistory.self,
                                            path: "/v1/market-data/accounts/\(accountId)/candles",
                                            query: [
                                                ("instrument", symbol),
                                                ("timeframe", timeframe.rawValue),
                                                ("from", iso.string(from: from)),
                                                ("to", iso.string(from: to)),
                                                ("price_type", priceType)
                                            ])
        return response.candles
    }

    /// Giá đóng của nến 1 phút gần nhất (dùng kiểm tra cảnh báo khi không có WebSocket).
    func latestPrice(symbol: String) async throws -> Double? {
        let list = try await candles(symbol: symbol, timeframe: .M1, count: 5)
        return list.last?.close
    }
}

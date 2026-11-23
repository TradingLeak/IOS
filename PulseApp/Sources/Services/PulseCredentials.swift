import Foundation
import Security

/// Thông tin đăng nhập của Pulse: một API key cho Partnership, một cho Trader API
/// (có thể dùng chung key nếu key đó có cả hai scope).
struct PulseCredentials: Codable, Equatable {
    /// Host Partnership API (vd `https://api.exness.com` hoặc host trong DNS widget).
    var partnerHost: String
    var apiKey: String
    var privateKey: String
    /// Host Trader API (gateway lấy từ DNS widget trong Personal Area).
    var tradingHost: String
    /// Account ID (chuỗi số dương uint64).
    var accountId: String
    /// Key riêng cho Trader API — để trống sẽ dùng lại `apiKey`/`privateKey`.
    var tradingAPIKey: String
    var tradingPrivateKey: String
    /// Access point phát hiện được (lưu lại để mở WebSocket nhanh).
    var accessPoint: String?

    init(partnerHost: String = "",
         apiKey: String = "",
         privateKey: String = "",
         tradingHost: String = "",
         accountId: String = "",
         tradingAPIKey: String = "",
         tradingPrivateKey: String = "",
         accessPoint: String? = nil) {
        self.partnerHost = partnerHost
        self.apiKey = apiKey
        self.privateKey = privateKey
        self.tradingHost = tradingHost
        self.accountId = accountId
        self.tradingAPIKey = tradingAPIKey
        self.tradingPrivateKey = tradingPrivateKey
        self.accessPoint = accessPoint
    }

    var isPartnerConfigured: Bool {
        !partnerHost.trimmingCharacters(in: .whitespaces).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty &&
        !privateKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isTradingConfigured: Bool {
        !tradingHost.trimmingCharacters(in: .whitespaces).isEmpty &&
        !accountId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Đã cấu hình tối thiểu để dùng app (Partnership hoặc Trader API).
    var isConfigured: Bool { isPartnerConfigured || isTradingConfigured }

    var partnerClient: ExnessClient? {
        guard isPartnerConfigured else { return nil }
        return ExnessClient(credentials: ExnessCredentials(baseURL: partnerHost, apiKey: apiKey, privateKey: privateKey))
    }

    var tradingCredentials: ExnessCredentials? {
        guard isTradingConfigured else { return nil }
        let key = tradingAPIKey.isEmpty ? apiKey : tradingAPIKey
        let priv = tradingPrivateKey.isEmpty ? privateKey : tradingPrivateKey
        guard !key.isEmpty, !priv.isEmpty else { return nil }
        return ExnessCredentials(baseURL: tradingHost, apiKey: key, privateKey: priv)
    }

    /// Chuẩn hoá access point thành host (bỏ scheme, slash).
    static func normalizeAccessPoint(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if let range = value.range(of: "://") {
            value = String(value[range.upperBound...])
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        return value
    }

    /// URL WebSocket ticks: `wss://{access_point}/v1/server-events/accounts/{id}/ws/ticks`.
    func ticksURL() -> URL? {
        guard let accessPoint, !accessPoint.isEmpty else { return nil }
        let host = Self.normalizeAccessPoint(accessPoint)
        guard !host.isEmpty, !accountId.isEmpty else { return nil }
        return URL(string: "wss://\(host)/v1/server-events/accounts/\(accountId)/ws/ticks")
    }
}

struct PulseCredentialStoreError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        "Không lưu được thông tin đăng nhập vào Keychain (mã \(status))."
    }
}

/// Lưu thông tin đăng nhập trong Keychain (mã hoá bởi hệ điều hành), không dùng UserDefaults.
struct PulseKeychain {
    /// Service theo bundle id để không dính với app khác trong repo.
    private let service = (Bundle.main.bundleIdentifier ?? "com.tradingleak.pulsehub") + ".credentials"
    private let account = "pulse.credentials"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func load() -> PulseCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(PulseCredentials.self, from: data)
    }

    func save(_ credentials: PulseCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PulseCredentialStoreError(status: status)
        }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

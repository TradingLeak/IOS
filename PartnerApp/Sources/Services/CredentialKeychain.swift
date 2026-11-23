import Foundation
import Security

struct CredentialStoreError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        "Không lưu được thông tin đăng nhập vào Keychain (mã \(status))."
    }
}

/// Lưu API key + private key trong Keychain của máy, mã hoá bởi hệ điều hành.
/// Không dùng UserDefaults, không ghi log.
struct CredentialKeychain {
    /// Service theo bundle id: PartnerHub giữ nguyên giá trị cũ để không mất key đã lưu.
    private let service = (Bundle.main.bundleIdentifier ?? "com.tradingleak.partnerhub") + ".credentials"
    private let account = "partner.credentials"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func load() -> ExnessCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(ExnessCredentials.self, from: data)
    }

    func save(_ credentials: ExnessCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError(status: status)
        }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

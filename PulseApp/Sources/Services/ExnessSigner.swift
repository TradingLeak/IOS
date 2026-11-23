import Foundation
import CryptoKit

// MARK: - Thông tin đăng nhập

struct ExnessCredentials: Codable, Equatable {
    var baseURL: String
    var apiKey: String
    var privateKey: String

    /// Chuẩn hoá host: bỏ khoảng trắng và dấu `/` cuối.
    var normalizedBaseURL: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    /// Kiểm tra host hợp lệ: HTTPS, không có đường dẫn/query.
    var hostValidationError: String? {
        let value = normalizedBaseURL
        guard !value.isEmpty else { return "Chưa nhập API host." }
        guard value.lowercased().hasPrefix("https://") else {
            return "API host phải bắt đầu bằng https://"
        }
        guard let url = URL(string: value) else { return "API host không hợp lệ." }
        guard let scheme = url.scheme, scheme.lowercased() == "https" else {
            return "API host phải dùng HTTPS."
        }
        guard url.host != nil, url.query == nil, url.fragment == nil else {
            return "API host chỉ được gồm https://<host>, không có query hoặc fragment."
        }
        let path = url.path
        if !path.isEmpty && path != "/" {
            return "API host không được chứa đường dẫn. Chỉ dán https://<host> (bắt đầu bằng /v1/... sẽ tự thêm)."
        }
        return nil
    }

    var maskedAPIKey: String {
        guard apiKey.count > 12 else { return String(repeating: "•", count: max(apiKey.count, 4)) }
        return apiKey.prefix(7) + "…" + apiKey.suffix(4)
    }
}

// MARK: - Lỗi

enum SigningError: LocalizedError {
    case invalidPrivateKey

    var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            return "Khóa riêng không hợp lệ. Dán 128 ký tự hex (hoặc 64 ký tự hex) hoặc nội dung PEM."
        }
    }
}

enum ExnessCredentialsError: LocalizedError {
    case invalidHost(String)
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .invalidHost(let message):
            return message
        case .missingCredentials:
            return "Chưa cấu hình API key. Vào Cài đặt để kết nối tài khoản Exness Partner."
        }
    }
}

// MARK: - Ký yêu cầu (Ed25519 + EXN-* headers)

/// Triển khai đúng đặc tả "Request signing" của Exness API:
/// payload JSON theo thứ tự cố định, base64url không pad, chữ ký Ed25519.
enum ExnessSigner {

    /// SHA-256 của body rỗng, base64url không pad — hằng số trong tài liệu Exness.
    static let emptyBodyHash = "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU"

    // MARK: Payload

    /// JSON payload được ký. THỨ TỰ KHÓA là bắt buộc, không dùng JSONEncoder
    /// vì không đảm bảo thứ tự key.
    static func payloadJSON(apiKey: String,
                            method: String,
                            pathAndQuery: String,
                            bodyHash: String,
                            timestamp: Int64) -> String {
        [
            "{\"api_key\":", jsonEscape(apiKey),
            ",\"idempotency_key\":\"\"",
            ",\"timestamp\":", String(timestamp),
            ",\"sign_version\":1",
            ",\"method\":", jsonEscape(method.uppercased()),
            ",\"path\":", jsonEscape(pathAndQuery),
            ",\"body_hash\":", jsonEscape(bodyHash),
            "}"
        ].joined()
    }

    static func bodyHash(_ body: Data) -> String {
        base64URLEncode(Data(SHA256.hash(data: body)))
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Escape chuỗi JSON (kể cả ký tự điều khiển và dấu ngoặc kép).
    static func jsonEscape(_ value: String) -> String {
        var output = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            default:
                if scalar.value < 0x20 {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    output.append(String(scalar))
                }
            }
        }
        output += "\""
        return output
    }

    // MARK: Headers

    static func signedHeaders(credentials: ExnessCredentials,
                              method: String,
                              pathAndQuery: String,
                              body: Data = Data(),
                              timestamp: Int64? = nil) throws -> [String: String] {
        let seedBytes = try seed(from: credentials.privateKey)
        let signingKey: Curve25519.Signing.PrivateKey
        do {
            signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seedBytes)
        } catch {
            throw SigningError.invalidPrivateKey
        }

        let stamp = timestamp ?? Int64(Date().timeIntervalSince1970 * 1000)
        let payload = payloadJSON(apiKey: credentials.apiKey,
                                  method: method,
                                  pathAndQuery: pathAndQuery,
                                  bodyHash: bodyHash(body),
                                  timestamp: stamp)
        let payloadData = Data(payload.utf8)

        let signature: Data
        do {
            signature = try signingKey.signature(for: payloadData)
        } catch {
            throw SigningError.invalidPrivateKey
        }

        return [
            "EXN-API-KEY": credentials.apiKey,
            "EXN-IDEMPOTENCY-KEY": "",
            "EXN-TIMESTAMP": String(stamp),
            "EXN-SIGN-VERSION": "1",
            "EXN-DATA": base64URLEncode(payloadData),
            "EXN-SIGN": base64URLEncode(signature)
        ]
    }

    // MARK: Private key

    /// Nhận các định dạng:
    /// - 128 ký tự hex (seed 32 byte + public key 32 byte) do Exness tạo
    /// - 64 ký tự hex (chỉ seed)
    /// - Base64 của 32 hoặc 64 byte
    /// - PEM PKCS#8 (`-----BEGIN PRIVATE KEY-----`)
    static func seed(from raw: String) throws -> Data {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SigningError.invalidPrivateKey }

        // PEM
        if trimmed.contains("BEGIN") {
            let lines = trimmed.split(whereSeparator: \.isNewline).map(String.init)
            let body = lines.filter { !$0.hasPrefix("-----") }.joined()
            guard let der = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else {
                throw SigningError.invalidPrivateKey
            }
            if let parsed = seed(fromDER: der) { return parsed }
            if der.count == 32 { return der }
            throw SigningError.invalidPrivateKey
        }

        // Hex
        let compact = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")
        if compact.allSatisfy({ $0.isHexDigit }) {
            if let data = Data(hexString: compact) {
                if data.count == 64 { return data.prefix(32) }
                if data.count == 32 { return data }
            }
        }

        // Base64 của 32/64 byte
        if let data = Data(base64Encoded: trimmed, options: []) {
            if data.count == 64 { return data.prefix(32) }
            if data.count == 32 { return data }
        }

        throw SigningError.invalidPrivateKey
    }

    // MARK: DER

    private struct TLV {
        let tag: UInt8
        let value: Data
    }

    /// Đọc một TLV DER (hỗ trợ độ dài ngắn và dài).
    private static func readTLV(_ data: Data, at offset: inout Int) -> TLV? {
        let base = data.startIndex
        guard offset >= 0, base + offset + 2 <= data.endIndex else { return nil }

        let tag = data[base + offset]
        var cursor = offset + 1
        let first = data[base + cursor]
        cursor += 1

        var length = 0
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            let byteCount = Int(first & 0x7F)
            guard byteCount > 0, byteCount <= 4 else { return nil }
            guard base + cursor + byteCount <= data.endIndex else { return nil }
            for _ in 0..<byteCount {
                length = (length << 8) | Int(data[base + cursor])
                cursor += 1
            }
        }

        guard base + cursor + length <= data.endIndex else { return nil }
        let value = data.subdata(in: (base + cursor)..<(base + cursor + length))
        offset = cursor + length
        return TLV(tag: tag, value: value)
    }

    /// Tìm seed Ed25519 (32 byte) trong DER PKCS#8.
    /// Cấu trúc: SEQUENCE { INTEGER 0, SEQUENCE { OID 1.3.101.112 }, OCTET STRING { OCTET STRING seed } }
    private static func seed(fromDER der: Data) -> Data? {
        var offset = 0
        guard let outer = readTLV(der, at: &offset), outer.tag == 0x30 else { return nil }

        var cursor = 0
        let body = outer.value
        while cursor < body.count {
            guard let tlv = readTLV(body, at: &cursor) else { return nil }
            guard tlv.tag == 0x04 else { continue }

            if tlv.value.count == 32 {
                return tlv.value
            }
            if tlv.value.count >= 34 {
                let start = tlv.value.startIndex
                if tlv.value[start] == 0x04 {
                    let innerLength = Int(tlv.value[start + 1])
                    if innerLength == 32 {
                        return tlv.value.subdata(in: (start + 2)..<(start + 34))
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - Data helpers

extension Data {
    init?(hexString: String) {
        let characters = Array(hexString.utf8)
        guard characters.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(characters.count / 2)
        var index = 0
        while index < characters.count {
            guard let high = Data.hexValue(characters[index]),
                  let low = Data.hexValue(characters[index + 1]) else {
                return nil
            }
            bytes.append(high << 4 | low)
            index += 2
        }
        self.init(bytes)
    }

    private static func hexValue(_ character: UInt8) -> UInt8? {
        switch character {
        case 48...57: return character - 48                 // 0-9
        case 65...70: return character - 65 + 10            // A-F
        case 97...102: return character - 97 + 10           // a-f
        default: return nil
        }
    }
}

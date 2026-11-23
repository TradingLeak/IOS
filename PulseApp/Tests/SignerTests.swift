import XCTest
import CryptoKit
@testable import PulseHub

final class SignerTests: XCTestCase {

    // MARK: - Hash & payload

    func testEmptyBodyHashMatchesExnessSpec() {
        XCTAssertEqual(ExnessSigner.bodyHash(Data()),
                       "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU")
    }

    func testPayloadKeepsDocumentedKeyOrder() {
        let payload = ExnessSigner.payloadJSON(
            apiKey: "exnsk-abc",
            method: "get",
            pathAndQuery: "/v1/partnership/reports/rewards?limit=100&aggregate_by=day",
            bodyHash: "HASH",
            timestamp: 1_700_000_000_000
        )

        XCTAssertEqual(
            payload,
            "{\"api_key\":\"exnsk-abc\",\"idempotency_key\":\"\",\"timestamp\":1700000000000," +
            "\"sign_version\":1,\"method\":\"GET\"," +
            "\"path\":\"/v1/partnership/reports/rewards?limit=100&aggregate_by=day\"," +
            "\"body_hash\":\"HASH\"}"
        )
    }

    func testPayloadEscapesQuotesAndControlCharacters() {
        let escaped = ExnessSigner.jsonEscape("a\"b\\c\nd\u{01}")
        XCTAssertEqual(escaped, "\"a\\\"b\\\\c\\nd\\u0001\"")
    }

    func testBase64URLHasNoPadding() {
        let encoded = ExnessSigner.base64URLEncode(Data([0xfb, 0xff, 0xbf]))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
    }

    // MARK: - Private key formats

    func testHex128UsesFirst32BytesAsSeed() throws {
        let bytes = (0..<64).map { UInt8($0) }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let seed = try ExnessSigner.seed(from: hex)
        XCTAssertEqual(seed, Data(bytes[0..<32]))
    }

    func testHex64IsAccepted() throws {
        let bytes = (0..<32).map { UInt8($0 &* 3) }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let seed = try ExnessSigner.seed(from: hex)
        XCTAssertEqual(seed, Data(bytes))
    }

    func testBase64RawKeyIsAccepted() throws {
        let bytes = (0..<32).map { UInt8($0 + 7) }
        let encoded = Data(bytes).base64EncodedString()
        XCTAssertEqual(try ExnessSigner.seed(from: encoded), Data(bytes))
    }

    func testPKCS8PEMIsParsed() throws {
        let seed = (0..<32).map { UInt8($0 + 10) }
        var der: [UInt8] = [
            0x30, 0x2e, 0x02, 0x01, 0x00,
            0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70,
            0x04, 0x22, 0x04, 0x20
        ]
        der.append(contentsOf: seed)

        let pem = "-----BEGIN PRIVATE KEY-----\n" +
            Data(der).base64EncodedString() +
            "\n-----END PRIVATE KEY-----"

        XCTAssertEqual(try ExnessSigner.seed(from: pem), Data(seed))
    }

    func testInvalidKeyThrows() {
        XCTAssertThrowsError(try ExnessSigner.seed(from: "not-a-key"))
        XCTAssertThrowsError(try ExnessSigner.seed(from: ""))
    }

    // MARK: - Headers

    func testSignedHeadersVerifyWithPublicKey() throws {
        let seedBytes = (0..<32).map { UInt8($0) }
        let seed = Data(seedBytes)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let hex = seedBytes.map { String(format: "%02x", $0) }.joined()

        let credentials = ExnessCredentials(baseURL: "https://example.com",
                                            apiKey: "exnsk-test",
                                            privateKey: hex)

        let headers = try ExnessSigner.signedHeaders(credentials: credentials,
                                                      method: "GET",
                                                      pathAndQuery: "/v1/partnership/partner/default-link",
                                                      timestamp: 1_700_000_000_000)

        XCTAssertEqual(headers["EXN-API-KEY"], "exnsk-test")
        XCTAssertEqual(headers["EXN-TIMESTAMP"], "1700000000000")
        XCTAssertEqual(headers["EXN-SIGN-VERSION"], "1")
        XCTAssertEqual(headers["EXN-IDEMPOTENCY-KEY"], "")

        let payloadData = try XCTUnwrap(base64URLDecode(headers["EXN-DATA"]))
        let signature = try XCTUnwrap(base64URLDecode(headers["EXN-SIGN"]))
        XCTAssertTrue(privateKey.publicKey.isValidSignature(signature, for: payloadData))

        let payload = String(data: payloadData, encoding: .utf8)
        XCTAssertEqual(payload, ExnessSigner.payloadJSON(apiKey: "exnsk-test",
                                                         method: "GET",
                                                         pathAndQuery: "/v1/partnership/partner/default-link",
                                                         bodyHash: ExnessSigner.emptyBodyHash,
                                                         timestamp: 1_700_000_000_000))
    }

    // MARK: - Helper

    private func base64URLDecode(_ value: String?) -> Data? {
        guard let value else { return nil }
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return Data(base64Encoded: base64)
    }
}

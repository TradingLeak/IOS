import XCTest
@testable import PartnerHub

final class ClientTests: XCTestCase {

    func testQueryPreservesOrderAndSkipsNil() {
        let path = ExnessClient.pathAndQuery(
            "/v1/partnership/reports/rewards",
            query: [
                ("limit", "1000"),
                ("offset", "0"),
                ("aggregate_by", "day"),
                ("reward_date_from", nil),
                ("reward_date_to", "")
            ]
        )

        XCTAssertEqual(path, "/v1/partnership/reports/rewards?limit=1000&offset=0&aggregate_by=day")
    }

    func testPathWithoutQuery() {
        XCTAssertEqual(ExnessClient.pathAndQuery("/v1/partnership/partner/default-link", query: []),
                       "/v1/partnership/partner/default-link")
    }

    func testPathWithoutLeadingSlashIsNormalized() {
        XCTAssertEqual(ExnessClient.pathAndQuery("v1/test", query: []),
                       "/v1/test")
    }

    func testCommaSeparatedListStaysReadable() {
        let path = ExnessClient.pathAndQuery("/v1/report", query: [("country", "VN,TH")])
        XCTAssertEqual(path, "/v1/report?country=VN,TH")
    }

    func testSpecialCharactersArePercentEncoded() {
        XCTAssertEqual(ExnessClient.encode("a b&c=d"), "a%20b%26c%3Dd")
    }

    func testHostValidation() {
        let good = ExnessCredentials(baseURL: " https://api.example.com/ ", apiKey: "k", privateKey: "p")
        XCTAssertNil(good.hostValidationError)
        XCTAssertEqual(good.normalizedBaseURL, "https://api.example.com")

        let withPath = ExnessCredentials(baseURL: "https://api.example.com/v1", apiKey: "k", privateKey: "p")
        XCTAssertNotNil(withPath.hostValidationError)

        let insecure = ExnessCredentials(baseURL: "http://api.example.com", apiKey: "k", privateKey: "p")
        XCTAssertNotNil(insecure.hostValidationError)
    }

    func testNumericErrorEnvelopeIsParsed() {
        let body = """
        {"code":1001,"error_message":"AUTH_INVALID_SIGNATURE","description":"signature verification failed"}
        """
        let data = Data(body.utf8)
        let error = ExnessClient.parseError(data: data,
                                            status: 401,
                                            headers: [AnyHashable("Retry-After"): "3" as Any])

        XCTAssertEqual(error.status, 401)
        XCTAssertEqual(error.code, "1001")
        XCTAssertTrue(error.message.contains("AUTH_INVALID_SIGNATURE"))
        XCTAssertEqual(error.retryAfter, "3")
        XCTAssertFalse(error.isRetryable)
    }

    func testPartnershipErrorEnvelopeIsParsed() {
        let body = """
        {"code":"ValidationError","message":"Invalid input.","details":"date_from is required"}
        """
        let error = ExnessClient.parseError(data: Data(body.utf8), status: 400, headers: [:])
        XCTAssertEqual(error.code, "ValidationError")
        XCTAssertTrue(error.message.contains("Invalid input"))
    }
}

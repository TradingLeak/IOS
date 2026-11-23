import XCTest
@testable import PartnerHub

final class FormattingTests: XCTestCase {

    func testDecimalParsingUsesDotAsDecimalSeparator() {
        XCTAssertEqual(Decimal(apiString: "123.45"), Decimal(string: "123.45"))
        XCTAssertNil(Decimal(apiString: "abc"))
        XCTAssertEqual(Decimal(apiString: "0"), 0)
    }

    func testUSDDisplayUsesVietnameseGrouping() {
        XCTAssertEqual(Fmt.usd(Decimal(string: "1234.5")!), "$1.234,50")
        XCTAssertEqual(Fmt.usd(Decimal(string: "0")!), "$0,00")
        XCTAssertEqual(Fmt.usd("12.50"), "$12,50")
    }

    func testCompactUSD() {
        XCTAssertEqual(Fmt.compactUSD(1_500_000), "$1,50M")
        XCTAssertEqual(Fmt.compactUSD(1_234), "$1,23K")
        XCTAssertEqual(Fmt.compactUSD(999), "$999,00")
    }

    func testLotsFormatting() {
        XCTAssertEqual(Fmt.lots(1_250), "1.250,0")
        XCTAssertEqual(Fmt.lots(3.25), "3,25")
    }

    func testPercentFormatting() {
        XCTAssertEqual(Fmt.percent(20), "20,00%")
    }

    func testDateParsing() {
        XCTAssertNotNil(Fmt.parseDate("2026-07-30T10:30:00Z"))
        XCTAssertNotNil(Fmt.parseDate("2026-07-30"))
        XCTAssertNil(Fmt.parseDate("not-a-date"))
    }

    func testDisplayDateFormatting() {
        XCTAssertEqual(Fmt.date("2026-07-30"), "30/07/2026")
        XCTAssertEqual(Fmt.shortDate("2026-07-30"), "30/07")
    }

    func testAPIDateStringIsUTC() {
        let date = Date(timeIntervalSince1970: 1_785_000_000) // 2026-07-25 UTC
        XCTAssertEqual(Fmt.apiDateString(date), "2026-07-25")
    }

    func testMaskedAPIKey() {
        let credentials = ExnessCredentials(baseURL: "https://example.com",
                                            apiKey: "exnsk-abcdefghijklmnop",
                                            privateKey: "p")
        XCTAssertEqual(credentials.maskedAPIKey, "exnsk-a…mnop")

        let short = ExnessCredentials(baseURL: "https://example.com", apiKey: "abc", privateKey: "p")
        XCTAssertEqual(short.maskedAPIKey, "••••")
    }
}

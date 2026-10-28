import XCTest
@testable import VietMap

/// Test phần AI: dựng URL, đọc JSON "bẩn" của model và bộ phân tích tiếng Việt offline.
/// Tất cả đều thuần logic, không gọi mạng nên chạy được trên CI không có key.
final class AIClientURLTests: XCTestCase {

    func testAddsHTTPSAndEndpoint() {
        XCTAssertEqual(AIClient.chatCompletionsURL(baseURL: "api.xah.io/v1")?.absoluteString,
                       "https://api.xah.io/v1/chat/completions")
    }

    func testKeepsHTTPSAndTrimsTrailingSlash() {
        XCTAssertEqual(AIClient.chatCompletionsURL(baseURL: "https://api.xah.io/v1/")?.absoluteString,
                       "https://api.xah.io/v1/chat/completions")
        XCTAssertEqual(AIClient.chatCompletionsURL(baseURL: "  https://api.xah.io/v1///  ")?.absoluteString,
                       "https://api.xah.io/v1/chat/completions")
    }

    func testAcceptsFullEndpointWithoutDuplicating() {
        XCTAssertEqual(AIClient.chatCompletionsURL(baseURL: "https://api.xah.io/v1/chat/completions")?.absoluteString,
                       "https://api.xah.io/v1/chat/completions")
    }

    func testLocalServerBaseURL() {
        XCTAssertEqual(AIClient.chatCompletionsURL(baseURL: "http://192.168.1.10:11434/v1")?.absoluteString,
                       "http://192.168.1.10:11434/v1/chat/completions")
    }

    func testEmptyOrBrokenInputReturnsNil() {
        XCTAssertNil(AIClient.chatCompletionsURL(baseURL: ""))
        XCTAssertNil(AIClient.chatCompletionsURL(baseURL: "   "))
    }
}

final class AIConfigTests: XCTestCase {

    func testNeedsKeyWhenKeyMissing() {
        var config = AIConfig()
        config.apiKey = ""
        XCTAssertTrue(config.needsKey)
        XCTAssertFalse(config.isConfigured)

        config.apiKey = "  sk-test  "
        XCTAssertTrue(config.isConfigured)
        XCTAssertEqual(config.trimmedKey, "sk-test")
    }

    func testDisabledConfigIsNeverConfigured() {
        var config = AIConfig()
        config.apiKey = "sk-test"
        config.enabled = false
        XCTAssertFalse(config.isConfigured)
        XCTAssertFalse(config.needsKey)
    }

    func testDefaultProviderIsCkey() {
        XCTAssertEqual(AIConfig.defaultBaseURL, "https://api.xah.io/v1")
        XCTAssertEqual(AIProviderPreset.all.first?.baseURL, AIConfig.defaultBaseURL)
    }

    func testHostText() {
        XCTAssertEqual(AIConfig().host, "api.xah.io")
    }
}

final class AIJSONTests: XCTestCase {

    func testExtractsFencedJSON() {
        let reply = """
        Đây là kết quả:
        ```json
        {"origin": "Cầu Giấy", "destination": "Hồ Hoàn Kiếm", "mode": "motorcycle"}
        ```
        Chúc bạn đi vui vẻ!
        """
        XCTAssertEqual(AIClient.extractJSONObject(from: reply),
                       #"{"origin": "Cầu Giấy", "destination": "Hồ Hoàn Kiếm", "mode": "motorcycle"}"#)
    }

    func testIgnoresBracesInsideStrings() {
        let reply = #"{"destination": "Quán cà phê {The Coffee}", "mode": "walking"}"#
        XCTAssertEqual(AIClient.extractJSONObject(from: reply), reply)
    }

    func testReturnsNilWithoutJSON() {
        XCTAssertNil(AIClient.extractJSONObject(from: "Xin lỗi, tôi không hiểu câu này."))
    }

    func testDecodesIntentFromNoisyText() throws {
        let reply = """
        ```json
        {"from": "Ngã tư Sở", "to": "Sân bay Nội Bài",
         "via": "Cầu Thăng Long", "travel_mode": "automobile",
         "goal": "fewestCameras", "depart_after": "8 giờ", "explanation": "Đi sớm cho đỡ tắc"}
        ```
        """
        let intent = try AIClient.decodeJSON(AIIntent.self, from: reply)
        XCTAssertEqual(intent.origin, "Ngã tư Sở")
        XCTAssertEqual(intent.destination, "Sân bay Nội Bài")
        XCTAssertEqual(intent.waypoints, ["Cầu Thăng Long"])
        XCTAssertEqual(intent.mode, "automobile")
        XCTAssertEqual(intent.preference, "fewestCameras")
        XCTAssertEqual(intent.departAfter, "8 giờ")
        XCTAssertEqual(intent.explanation, "Đi sớm cho đỡ tắc")
    }

    func testDecodesIntentWithNeedsClarification() throws {
        let reply = #"{"needs_clarification": true, "question": "Bạn muốn đi ô tô hay xe máy?"}"#
        let intent = try AIClient.decodeJSON(AIIntent.self, from: reply)
        XCTAssertEqual(intent.needsClarification, true)
        XCTAssertEqual(intent.question, "Bạn muốn đi ô tô hay xe máy?")
        XCTAssertNil(intent.destination)
    }
}

final class RouteIntentParserTests: XCTestCase {

    func testParsesMotorcycleTripWithOriginDestination() {
        let intent = RouteIntentParser.parse("đi xe máy từ Cầu Giấy đến Hồ Hoàn Kiếm, tránh cao tốc")
        XCTAssertEqual(intent.mode, TravelMode.motorcycle.rawValue)
        XCTAssertEqual(intent.origin, "Cầu Giấy")
        XCTAssertEqual(intent.destination, "Hồ Hoàn Kiếm")
        XCTAssertEqual(intent.avoid, ["highway"])
        XCTAssertEqual(intent.preference, RoutePreference.avoidHighway.rawValue)
    }

    func testParsesPreferenceFewestCameras() {
        let intent = RouteIntentParser.parse("ô tô từ Ngã tư Sở đến sân bay Nội Bài, ít camera nhất")
        XCTAssertEqual(intent.mode, TravelMode.automobile.rawValue)
        XCTAssertEqual(intent.destination, "sân bay Nội Bài")
        XCTAssertEqual(intent.preference, RoutePreference.fewestCameras.rawValue)
        XCTAssertTrue(intent.avoid?.contains("cameras") ?? false)
    }

    func testParsesWaypointAndDepartureTime() {
        let intent = RouteIntentParser.parse("xe máy từ Đà Nẵng đến Hội An lúc 8 giờ sáng, ghé An Bàng")
        XCTAssertEqual(intent.origin, "Đà Nẵng")
        XCTAssertEqual(intent.destination, "Hội An")
        XCTAssertEqual(intent.waypoints, ["An Bàng"])
        XCTAssertEqual(intent.departAfter, "8 giờ sáng")
    }

    func testDestinationOnlySentence() {
        let intent = RouteIntentParser.parse("chỉ đường đến Hồ Tây")
        XCTAssertEqual(intent.destination, "Hồ Tây")
        XCTAssertNil(intent.origin)
    }

    func testWalkingMode() {
        let intent = RouteIntentParser.parse("đi bộ từ Hồ Tây đến phố cổ")
        XCTAssertEqual(intent.mode, TravelMode.walking.rawValue)
    }

    func testEmptySentenceDoesNotInventData() {
        let intent = RouteIntentParser.parse("   ")
        XCTAssertNil(intent.origin)
        XCTAssertNil(intent.destination)
        XCTAssertEqual(intent.waypoints, [])
    }

    func testPreferenceParsingVariants() {
        XCTAssertEqual(RoutePreference.parse("đi đường dễ nhất"), .easiest)
        XCTAssertEqual(RoutePreference.parse("phạt nguội"), .fewestCameras)
        XCTAssertEqual(RoutePreference.parse("tránh cao tốc"), .avoidHighway)
        XCTAssertEqual(RoutePreference.parse("nhanh nhất"), .fastest)
        XCTAssertNil(RoutePreference.parse("không rõ"))
    }

    func testPreferenceRoundTripFromRawValue() {
        for option in RoutePreference.allCases {
            XCTAssertEqual(RoutePreference.parse(option.rawValue), option)
        }
    }
}

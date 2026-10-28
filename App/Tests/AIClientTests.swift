import XCTest
@testable import VietMap

final class AIClientTests: XCTestCase {

    // MARK: - Ghép URL

    func testBuildsChatCompletionsURL() {
        XCTAssertEqual(
            AIClient.chatCompletionsURL(baseURL: "https://api.xah.io/v1")?.absoluteString,
            "https://api.xah.io/v1/chat/completions"
        )
    }

    func testHandlesTrailingSlash() {
        XCTAssertEqual(
            AIClient.chatCompletionsURL(baseURL: "https://api.xah.io/v1/")?.absoluteString,
            "https://api.xah.io/v1/chat/completions"
        )
    }

    func testKeepsFullEndpoint() {
        XCTAssertEqual(
            AIClient.chatCompletionsURL(baseURL: "https://api.xah.io/v1/chat/completions")?.absoluteString,
            "https://api.xah.io/v1/chat/completions"
        )
    }

    func testAddsHTTPSWhenSchemeMissing() {
        XCTAssertEqual(
            AIClient.chatCompletionsURL(baseURL: "api.xah.io/v1")?.absoluteString,
            "https://api.xah.io/v1/chat/completions"
        )
    }

    func testReturnsNilForEmptyBaseURL() {
        XCTAssertNil(AIClient.chatCompletionsURL(baseURL: "   "))
    }

    func testKeepsLocalHTTPForOllama() {
        XCTAssertEqual(
            AIClient.chatCompletionsURL(baseURL: "http://192.168.1.10:11434/v1")?.absoluteString,
            "http://192.168.1.10:11434/v1/chat/completions"
        )
    }

    // MARK: - Bóc JSON khỏi câu trả lời

    func testExtractsJSONFromMarkdownFence() {
        let text = """
        ```json
        {"origin": "Cầu Giấy", "destination": "Hồ Tây"}
        ```
        """
        XCTAssertEqual(AIClient.extractJSONObject(from: text),
                       #"{"origin": "Cầu Giấy", "destination": "Hồ Tây"}"#)
    }

    func testExtractsJSONWithPreamble() {
        let text = "Đây là kết quả: {\"destination\": \"Hồ Tây\"} — chúc bạn đi vui vẻ."
        XCTAssertEqual(AIClient.extractJSONObject(from: text), #"{"destination": "Hồ Tây"}"#)
    }

    func testReturnsNilWhenNoJSON() {
        XCTAssertNil(AIClient.extractJSONObject(from: "Xin chào, tôi là trợ lý."))
        XCTAssertNil(AIClient.extractJSONObject(from: ""))
    }

    // MARK: - Đọc phản hồi

    func testExtractContentStandard() throws {
        let json = #"{"choices":[{"message":{"role":"assistant","content":"Xin chào"}}]}"#
        XCTAssertEqual(try AIClient.extractContent(from: Data(json.utf8)), "Xin chào")
    }

    func testExtractContentFromPartsArray() throws {
        let json = #"{"choices":[{"message":{"content":[{"type":"text","text":"Xin "},{"type":"text","text":"chào"}]}}]}"#
        XCTAssertEqual(try AIClient.extractContent(from: Data(json.utf8)), "Xin chào")
    }

    func testExtractContentFromLegacyTextField() throws {
        let json = #"{"choices":[{"text":"Kết quả cũ"}]}"#
        XCTAssertEqual(try AIClient.extractContent(from: Data(json.utf8)), "Kết quả cũ")
    }

    func testExtractContentThrowsWhenEmpty() {
        let json = #"{"choices":[{"message":{"content":""}}]}"#
        XCTAssertThrowsError(try AIClient.extractContent(from: Data(json.utf8)))
    }

    func testExtractContentThrowsWhenNotJSON() {
        XCTAssertThrowsError(try AIClient.extractContent(from: Data("not json".utf8)))
    }

    func testErrorMessageReadsNestedError() {
        let json = #"{"error":{"message":"Invalid API key","type":"auth"}}"#
        XCTAssertEqual(AIClient.errorMessage(from: Data(json.utf8)), "Invalid API key")
    }

    func testErrorMessageFallsBackToRawBody() {
        XCTAssertEqual(AIClient.errorMessage(from: Data("oops".utf8)), "oops")
    }

    // MARK: - Cấu hình

    func testConfigRequiresAllFields() {
        var config = AIConfig(baseURL: "https://api.xah.io/v1", model: "gpt-4o-mini", apiKey: "", temperature: 0.2)
        XCTAssertFalse(config.isConfigured)

        config.apiKey = "sk-test"
        XCTAssertTrue(config.isConfigured)
        XCTAssertEqual(config.chatCompletionsURL?.absoluteString,
                       "https://api.xah.io/v1/chat/completions")

        config.baseURL = ""
        XCTAssertFalse(config.isConfigured)
    }
}

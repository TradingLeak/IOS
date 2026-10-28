import Foundation

struct AIMessage {
    let role: String      // "system" | "user" | "assistant"
    let content: String

    init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    static func system(_ text: String) -> AIMessage { AIMessage(role: "system", content: text) }
    static func user(_ text: String) -> AIMessage { AIMessage(role: "user", content: text) }
    static func assistant(_ text: String) -> AIMessage { AIMessage(role: "assistant", content: text) }
}

enum AIError: LocalizedError {
    case notConfigured
    case badURL(String)
    case http(Int, String)
    case empty
    case invalidJSON
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Chưa cấu hình AI. Vào Cài đặt để nhập base URL, model và API key."
        case .badURL(let value):
            return "Base URL không hợp lệ: \(value)"
        case .http(let code, let message):
            switch code {
            case 401, 403:
                return "API key bị từ chối (HTTP \(code)). Kiểm tra lại key trong Cài đặt.\n\(message)"
            case 404:
                return "Không tìm thấy endpoint (HTTP 404). Kiểm tra base URL và tên model.\n\(message)"
            case 429:
                return "Hết hạn mức hoặc gọi quá nhanh (HTTP 429). Thử lại sau ít phút.\n\(message)"
            default:
                return "Máy chủ AI trả lỗi HTTP \(code).\n\(message)"
            }
        case .empty:
            return "AI trả về nội dung rỗng."
        case .invalidJSON:
            return "AI trả về dữ liệu không phải JSON hợp lệ."
        case .network(let message):
            return "Không kết nối được tới máy chủ AI: \(message)"
        }
    }
}

/// Client gọi API chuẩn OpenAI (`POST {base_url}/chat/completions`).
/// Dùng được với ckey.vn, OpenAI, OpenRouter, Groq, Ollama, LM Studio…
/// chỉ bằng cách đổi base URL + model.
final class AIClient {
    private let session: URLSession

    init(session: URLSession = AIClient.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    // MARK: - URL

    /// Ghép base URL thành endpoint chat/completions.
    /// Chấp nhận cả "https://api.xah.io/v1", "https://api.xah.io/v1/" và URL đầy đủ.
    static func chatCompletionsURL(baseURL: String) -> URL? {
        var raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.lowercased().hasPrefix("http://") && !raw.lowercased().hasPrefix("https://") {
            raw = "https://" + raw
        }
        while raw.hasSuffix("/") {
            raw.removeLast()
        }
        if raw.hasSuffix("/chat/completions") {
            return URL(string: raw)
        }
        return URL(string: raw + "/chat/completions")
    }

    // MARK: - Chat

    func chat(config: AIConfig,
              messages: [AIMessage],
              temperature: Double? = nil,
              maxTokens: Int? = nil,
              jsonMode: Bool = false) async throws -> String {

        guard config.isConfigured else { throw AIError.notConfigured }
        guard let url = config.chatCompletionsURL else { throw AIError.badURL(config.baseURL) }

        var body: [String: Any] = [
            "model": config.trimmedModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": temperature ?? config.temperature,
            "stream": false
        ]
        if let maxTokens { body["max_tokens"] = maxTokens }
        if jsonMode { body["response_format"] = ["type": "json_object"] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(config.trimmedKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIError.network("Phản hồi không hợp lệ từ máy chủ.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(http.statusCode, Self.errorMessage(from: data))
        }
        return try Self.extractContent(from: data)
    }

    /// Kiểm tra nhanh base URL + key + model có hoạt động không.
    func ping(config: AIConfig) async -> Result<String, Error> {
        do {
            let reply = try await chat(config: config,
                                       messages: [.user("Trả lời đúng một từ: OK")],
                                       temperature: 0,
                                       maxTokens: 16)
            let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(trimmed.isEmpty ? "OK" : trimmed)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Parsing (có thể test offline)

    /// Lấy nội dung trả lời, chấp nhận nhiều biến thể của các gateway.
    static func extractContent(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidJSON
        }

        if let choices = json["choices"] as? [[String: Any]], let first = choices.first {
            if let message = first["message"] as? [String: Any] {
                if let content = message["content"] as? String,
                   !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return content
                }
                if let parts = message["content"] as? [[String: Any]] {
                    let text = parts.compactMap { $0["text"] as? String }.joined()
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return text
                    }
                }
                if let reasoning = message["reasoning_content"] as? String,
                   !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return reasoning
                }
            }
            if let text = first["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }

        if let text = json["response"] as? String, !text.isEmpty { return text }
        if let text = json["content"] as? String, !text.isEmpty { return text }

        throw AIError.empty
    }

    static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            if let message = json["message"] as? String { return message }
            if let error = json["error"] as? String { return error }
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(không có nội dung)" : String(trimmed.prefix(300))
    }

    /// Bóc đối tượng JSON ra khỏi câu trả lời (bỏ ```json … ``` hoặc lời dẫn).
    static func extractJSONObject(from text: String) -> String? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if let fence = cleaned.range(of: "```", options: .backwards) {
                cleaned = String(cleaned[cleaned.startIndex..<fence.lowerBound])
            }
        }

        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}"),
              start < end else {
            return nil
        }
        return String(cleaned[start...end])
    }
}

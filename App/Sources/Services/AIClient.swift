import Foundation

// MARK: - Cấu hình AI

/// Một nhà cung cấp tương thích chuẩn OpenAI (`POST {base}/chat/completions`).
struct AIProviderPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let baseURL: String
    let model: String
    let note: String

    static let all: [AIProviderPreset] = [
        AIProviderPreset(id: "ckey",
                         name: "Ckey.vn (mặc định)",
                         baseURL: "https://api.xah.io/v1",
                         model: "gpt-4o-mini",
                         note: "Tạo key tại ckey.vn · hỗ trợ nhiều model"),
        AIProviderPreset(id: "openai",
                         name: "OpenAI",
                         baseURL: "https://api.openai.com/v1",
                         model: "gpt-4o-mini",
                         note: "Key bắt đầu bằng sk-…"),
        AIProviderPreset(id: "groq",
                         name: "Groq",
                         baseURL: "https://api.groq.com/openai/v1",
                         model: "llama-3.3-70b-versatile",
                         note: "Nhanh, có gói miễn phí"),
        AIProviderPreset(id: "openrouter",
                         name: "OpenRouter",
                         baseURL: "https://openrouter.ai/api/v1",
                         model: "openai/gpt-4o-mini",
                         note: "Một key dùng nhiều model"),
        AIProviderPreset(id: "ollama",
                         name: "Ollama (máy trong LAN)",
                         baseURL: "http://192.168.1.10:11434/v1",
                         model: "qwen2.5",
                         note: "Chạy offline trong nhà, không gửi dữ liệu đi"),
        AIProviderPreset(id: "lmstudio",
                         name: "LM Studio (máy trong LAN)",
                         baseURL: "http://192.168.1.10:1234/v1",
                         model: "local-model",
                         note: "Cần bật server trong LM Studio")
    ]
}

/// Cấu hình AI do người dùng nhập: base URL, model, key, mức sáng tạo.
struct AIConfig: Equatable {
    var baseURL: String = AIConfig.defaultBaseURL
    var model: String = AIConfig.defaultModel
    var apiKey: String = ""
    var temperature: Double = 0.2
    /// Bật/tắt toàn bộ phần AI (khi tắt, app dùng bộ phân tích offline).
    var enabled: Bool = true
    /// AI được phép can thiệp sâu: sắp xếp/chọn tuyến, thêm điểm dừng, đổi phương tiện.
    var deepPlanning: Bool = true

    static let defaultBaseURL = "https://api.xah.io/v1"
    static let defaultModel = "gpt-4o-mini"

    var trimmedBaseURL: String { baseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedModel: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Có đủ thông tin để gọi mạng hay không.
    var isConfigured: Bool {
        enabled && !trimmedKey.isEmpty && !trimmedBaseURL.isEmpty && !trimmedModel.isEmpty
    }

    /// Đang bật AI nhưng thiếu key → UI nhắc người dùng.
    var needsKey: Bool { enabled && trimmedKey.isEmpty }

    var chatCompletionsURL: URL? {
        AIClient.chatCompletionsURL(baseURL: trimmedBaseURL)
    }

    var host: String {
        guard let url = AIClient.chatCompletionsURL(baseURL: trimmedBaseURL) else {
            return trimmedBaseURL.isEmpty ? "chưa đặt" : trimmedBaseURL
        }
        return url.host ?? url.absoluteString
    }

    mutating func apply(_ preset: AIProviderPreset) {
        baseURL = preset.baseURL
        model = preset.model
    }
}

// MARK: - Tin nhắn

/// Một lượt chat theo chuẩn OpenAI.
struct AIChatTurn {
    enum Role: String {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String

    static func system(_ text: String) -> AIChatTurn { AIChatTurn(role: .system, content: text) }
    static func user(_ text: String) -> AIChatTurn { AIChatTurn(role: .user, content: text) }
    static func assistant(_ text: String) -> AIChatTurn { AIChatTurn(role: .assistant, content: text) }
}

// MARK: - Lỗi

enum AIError: LocalizedError, Equatable {
    case notConfigured
    case badURL(String)
    case http(status: Int, message: String)
    case emptyReply
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Chưa cấu hình AI. Mở Cài đặt → Trợ lý AI để nhập base URL và API key."
        case .badURL(let text):
            return "Base URL không hợp lệ: “\(text)”. Ví dụ đúng: https://api.xah.io/v1"
        case .http(let status, let message):
            switch status {
            case 401, 403:
                return "API key bị từ chối (HTTP \(status)). Kiểm tra lại key và base URL. \(message)"
            case 404:
                return "Không thấy endpoint (HTTP 404). Base URL thường phải có /v1. \(message)"
            case 429:
                return "Hết hạn mức hoặc gọi quá nhanh (HTTP 429). Thử lại sau ít phút. \(message)"
            case 500...599:
                return "Máy chủ AI đang lỗi (HTTP \(status)). Đang dùng phương án offline. \(message)"
            default:
                return "Máy chủ AI trả lỗi HTTP \(status). \(message)"
            }
        case .emptyReply:
            return "AI trả về nội dung rỗng. Thử lại hoặc đổi model."
        case .decoding(let message):
            return "Không đọc được phản hồi của AI: \(message)"
        }
    }
}

// MARK: - Client

/// Gọi API kiểu OpenAI: `POST {base}/chat/completions`.
/// Chỉ dùng `URLSession` + `Codable`, không phụ thuộc thư viện ngoài.
struct AIClient {

    var session: URLSession = .shared
    var timeout: TimeInterval = 45

    // MARK: Dựng URL

    /// Chuẩn hoá base URL người dùng nhập và trả về endpoint chat hoàn chỉnh.
    ///
    /// Chấp nhận: `api.xah.io/v1`, `https://api.xah.io/v1/`,
    /// `https://api.xah.io/v1/chat/completions`.
    static func chatCompletionsURL(baseURL: String) -> URL? {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }

        if text.lowercased().hasSuffix("/chat/completions") {
            return URL(string: text)
        }
        return URL(string: text + "/chat/completions")
    }

    // MARK: Gọi API

    func chat(config: AIConfig,
              messages: [AIChatTurn],
              temperature: Double? = nil,
              maxTokens: Int = 500) async throws -> String {

        guard config.isConfigured else { throw AIError.notConfigured }
        guard let url = Self.chatCompletionsURL(baseURL: config.trimmedBaseURL) else {
            throw AIError.badURL(config.trimmedBaseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("VietMap-iOS/3", forHTTPHeaderField: "User-Agent")

        let body = RequestBody(
            model: config.trimmedModel,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            temperature: temperature ?? config.temperature,
            max_tokens: maxTokens,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode,
                               message: Self.errorMessage(from: data) ?? "")
        }

        let content = try Self.extractContent(from: data)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.emptyReply }
        return trimmed
    }

    /// Kiểm tra kết nối: gửi một câu rất ngắn và trả lời của model.
    func ping(config: AIConfig) async -> Result<String, Error> {
        do {
            let reply = try await chat(
                config: config,
                messages: [
                    .system("Bạn là trợ lý dẫn đường. Trả lời cực ngắn, tiếng Việt."),
                    .user("Trả lời đúng một từ: OK")
                ],
                temperature: 0,
                maxTokens: 24
            )
            return .success(String(reply.prefix(80)))
        } catch {
            return .failure(error)
        }
    }

    // MARK: Đọc phản hồi

    struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: Content?

                enum CodingKeys: String, CodingKey { case content }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    content = try? container.decode(Content.self, forKey: .content)
                }
            }

            let message: Message?
            let text: String?
        }

        let choices: [Choice]?
    }

    /// `content` có thể là chuỗi hoặc mảng phần (một số nhà cung cấp trả mảng).
    enum Content: Decodable {
        case text(String)
        case parts([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
                return
            }
            if let items = try? container.decode([Part].self) {
                self = .parts(items.compactMap { $0.value })
                return
            }
            self = .text("")
        }

        struct Part: Decodable {
            let text: String?
            let content: String?

            var value: String? { text ?? content }
        }

        private var partsValue: [String] {
            if case .parts(let values) = self { return values }
            return []
        }

        var plainText: String {
            switch self {
            case .text(let text): return text
            case .parts: return partsValue.joined()
            }
        }
    }

    static func extractContent(from data: Data) throws -> String {
        guard let body = try? JSONDecoder().decode(ResponseBody.self, from: data) else {
            throw AIError.decoding("phản hồi không phải JSON hợp lệ")
        }
        guard let choice = body.choices?.first else {
            throw AIError.decoding("thiếu trường choices")
        }
        if let text = choice.message?.content?.plainText, !text.isEmpty {
            return text
        }
        if let text = choice.text, !text.isEmpty { return text }
        throw AIError.emptyReply
    }

    static func errorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable {
            struct Detail: Decodable { let message: String? }
            let error: Detail?
            let message: String?
        }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            if let message = body.error?.message, !message.isEmpty { return message }
            if let message = body.message, !message.isEmpty { return message }
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return String(text.prefix(200))
    }

    /// Lấy **object JSON đầu tiên** trong câu trả lời (AI hay bọc trong ```json … ```).
    static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]

            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                switch character {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...index])
                    }
                default: break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Giải mã JSON mà AI trả về (bỏ ```json … ```, cắt object đầu tiên).
    static func decodeJSON<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let candidate = extractJSONObject(from: text) ?? text
        guard let data = candidate.data(using: .utf8) else {
            throw AIError.decoding("không chuyển được sang UTF-8")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AIError.decoding(String(candidate.prefix(120)))
        }
    }

    // MARK: Body

    private struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double
        let max_tokens: Int
        let stream: Bool
    }
}

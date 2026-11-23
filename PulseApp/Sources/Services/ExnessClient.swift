import Foundation

/// Lỗi API chuẩn hoá: giữ HTTP status + mã lỗi (`1001`, `ValidationError`, `REQUEST_RATE_LIMIT`…).
struct ExnessAPIError: Error, LocalizedError {
    let status: Int
    let code: String
    let message: String
    var retryAfter: String?

    var errorDescription: String? {
        "[\(code)] \(message)"
    }

    /// Thông điệp thân thiện với người dùng tiếng Việt (Partnership + Trader API).
    var localizedMessage: String {
        switch code {
        case "1000":
            return "API key không hợp lệ, đã hết hạn hoặc không được phép truy cập từ IP này."
        case "1001":
            return "Chữ ký số không hợp lệ. Kiểm tra lại private key và giờ trên thiết bị."
        case "1002":
            return "API key không có quyền cần thiết. Tạo key với scope Read-only hoặc Full access."
        case "1003", "429", "REQUEST_RATE_LIMIT":
            return "Truy vấn quá nhanh (rate limit). Vui lòng chờ một chút rồi thử lại."
        case "2000":
            return "Không tìm thấy tài khoản giao dịch. Kiểm tra Account ID và API key."
        case "2001":
            return "Tài khoản giao dịch đã bị vô hiệu hoá."
        case "2002":
            return "Tài khoản chỉ cho phép đóng lệnh (close-only)."
        case "3000", "3001":
            return "Tham số yêu cầu không hợp lệ. Kiểm tra lại mã, khung thời gian và khoảng ngày."
        case "4003", "MARKET_SESSION_CLOSED":
            return "Thị trường đang đóng cửa (cuối tuần hoặc ngoài phiên)."
        case "MARKET_NO_QUOTES":
            return "Chưa có báo giá cho mã này."
        case "MARKET_INSTRUMENT_NOT_FOUND":
            return "Không tìm thấy mã này trên tài khoản."
        case "DECODE_ERROR":
            return "Dữ liệu API không đúng định dạng dự kiến."
        case "HTTP_400":
            return "Yêu cầu không hợp lệ (HTTP 400). Kiểm tra mã, khung thời gian và khoảng ngày."
        case "HTTP_401", "HTTP_403":
            return "API key hoặc chữ ký không được chấp nhận. Kiểm tra API key, private key và scope của key (Trader API cần scope Trading)."
        case "HTTP_404":
            return "Máy chủ không có đường dẫn này (HTTP 404). Với Trader API, URL nhập phải là gateway trong DNS widget; bấm “Lưu & kiểm tra kết nối” để app tự lấy access point trước khi gọi dữ liệu."
        default:
            return message
        }
    }

    var isRetryable: Bool {
        status == 429 || status >= 500
    }
}

/// Client gọi API Exness (Partnership hoặc Trader) với chữ ký EXN-*.
final class ExnessClient {
    let credentials: ExnessCredentials
    private let session: URLSession
    private let decoder: JSONDecoder

    init(credentials: ExnessCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = jsonDecoder
    }

    // MARK: - GET

    func get<T: Decodable>(_ type: T.Type, path: String, query: [(String, String?)] = []) async throws -> T {
        let data = try await data(path: path, query: query)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ExnessAPIError(status: 200,
                                 code: "DECODE_ERROR",
                                 message: "Dữ liệu API không đúng định dạng dự kiến.")
        }
    }

    /// GET trả về dữ liệu thô (dùng cho JSON không cố định schema như danh sách mã).
    func data(path: String, query: [(String, String?)] = []) async throws -> Data {
        let pathAndQuery = Self.pathAndQuery(path, query: query)
        let request = try makeRequest(pathAndQuery: pathAndQuery, method: "GET")
        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExnessAPIError(status: 0, code: "NO_HTTP_RESPONSE", message: "Máy chủ không trả phản hồi HTTP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.parseError(data: body, status: http.statusCode, headers: http.allHeaderFields)
        }
        return body
    }

    // MARK: - Request

    func makeRequest(pathAndQuery: String, method: String) throws -> URLRequest {
        if let message = credentials.hostValidationError {
            throw ExnessCredentialsError.invalidHost(message)
        }
        let base = credentials.normalizedBaseURL
        guard let url = URL(string: base + pathAndQuery) else {
            throw ExnessCredentialsError.invalidHost("Không tạo được URL từ API host đã nhập.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let headers = try ExnessSigner.signedHeaders(credentials: credentials,
                                                      method: method,
                                                      pathAndQuery: pathAndQuery)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    // MARK: - Query

    /// Ghép path + query theo đúng thứ tự truyền vào. Chuỗi này cũng là giá trị
    /// được ký trong `path` của EXN-DATA, nên không được sắp xếp lại sau đó.
    static func pathAndQuery(_ path: String, query: [(String, String?)]) -> String {
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        let pairs = query.compactMap { item -> String? in
            let (key, value) = item
            guard let value, !value.isEmpty else { return nil }
            return "\(encode(key))=\(encode(value))"
        }
        guard !pairs.isEmpty else { return normalizedPath }
        return normalizedPath + "?" + pairs.joined(separator: "&")
    }

    /// Mã hoá percent theo RFC 3986, giữ nguyên dấu phẩy cho các filter dạng list.
    static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~,")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Error

    static func parseError(data: Data, status: Int, headers: [AnyHashable: Any]) -> ExnessAPIError {
        var code = "HTTP_\(status)"
        var message = "Yêu cầu thất bại (HTTP \(status))."
        var retryAfter: String?

        for (key, value) in headers {
            if let keyString = key as? String, keyString.lowercased() == "retry-after", let text = value as? String {
                retryAfter = text
            }
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let numeric = json["code"] as? Int {
                code = String(numeric)
                let name = json["error_message"] as? String ?? json["error"] as? String ?? "ERROR_\(numeric)"
                message = name
                if let description = json["description"] as? String, !description.isEmpty {
                    message += " — " + description
                }
            } else if let stringCode = json["code"] as? String {
                code = stringCode
                if let text = (json["message"] as? String) ?? (json["error_message"] as? String) {
                    message = text
                }
                if let details = json["details"] as? String, !details.isEmpty {
                    message += " — " + details
                }
            } else if let name = json["error"] as? String {
                code = name
                message = json["error_description"] as? String ?? name
            }
        } else if status == 401 || status == 403 {
            message = "API key hoặc chữ ký không được chấp nhận (HTTP \(status))."
        }

        return ExnessAPIError(status: status, code: code, message: message, retryAfter: retryAfter)
    }

    /// Thông điệp lỗi dùng chung cho UI.
    static func message(for error: Error) -> String {
        if let apiError = error as? ExnessAPIError {
            return apiError.localizedMessage
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Không có kết nối Internet."
            case .timedOut:
                return "Hết thời gian chờ phản hồi từ máy chủ."
            case .cannotFindHost, .cannotConnectToHost, .secureConnectionFailed:
                return "Không kết nối được tới API host. Kiểm tra lại host (phải là HTTPS) và mạng."
            default:
                return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

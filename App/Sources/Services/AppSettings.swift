import Foundation
import Combine

/// Cấu hình AI: tương thích chuẩn OpenAI (chat/completions),
/// nên đổi nhà cung cấp chỉ cần đổi base URL + model.
struct AIConfig {
    var baseURL: String
    var model: String
    var apiKey: String
    var temperature: Double

    /// ckey.vn cung cấp endpoint tương thích OpenAI.
    static let ckeyBaseURL = "https://api.xah.io/v1"
    static let defaultModel = "gpt-4o-mini"

    var trimmedBaseURL: String { baseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedModel: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isConfigured: Bool {
        !trimmedKey.isEmpty && !trimmedBaseURL.isEmpty && !trimmedModel.isEmpty
    }

    var chatCompletionsURL: URL? {
        AIClient.chatCompletionsURL(baseURL: trimmedBaseURL)
    }
}

/// Cài đặt người dùng: base URL/model nằm trong UserDefaults,
/// API key nằm trong Keychain (không bao giờ ghi vào repo hay file log).
@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let baseURL = "vietmap.ai.baseURL"
        static let model = "vietmap.ai.model"
        static let temperature = "vietmap.ai.temperature"
        static let apiKey = "ai.api.key"
        static let useAI = "vietmap.ai.enabled"
        static let mapProvider = "vietmap.map.provider"
        static let mapType = "vietmap.map.type"
        static let traffic = "vietmap.map.traffic"
        static let pois = "vietmap.map.pois"
        static let voiceGuidance = "vietmap.nav.voice"
        static let alertBeep = "vietmap.nav.alertBeep"
    }

    @Published var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Keys.baseURL) }
    }
    @Published var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }
    @Published var temperature: Double {
        didSet { defaults.set(temperature, forKey: Keys.temperature) }
    }
    @Published var apiKey: String {
        didSet { KeychainStore.save(apiKey, for: Keys.apiKey) }
    }
    @Published var useAI: Bool {
        didSet { defaults.set(useAI, forKey: Keys.useAI) }
    }
    @Published var mapProvider: MapProvider {
        didSet { defaults.set(mapProvider.rawValue, forKey: Keys.mapProvider) }
    }
    @Published var mapTypeIndex: Int {
        didSet { defaults.set(mapTypeIndex, forKey: Keys.mapType) }
    }
    @Published var showTraffic: Bool {
        didSet { defaults.set(showTraffic, forKey: Keys.traffic) }
    }
    @Published var showPOIs: Bool {
        didSet { defaults.set(showPOIs, forKey: Keys.pois) }
    }
    /// Giọng nói tiếng Việt khi chỉ đường & đọc cảnh báo.
    @Published var voiceGuidance: Bool {
        didSet { defaults.set(voiceGuidance, forKey: Keys.voiceGuidance) }
    }
    /// Tiếng "tink" khi xuất hiện card camera/biển báo mới.
    @Published var alertBeep: Bool {
        didSet { defaults.set(alertBeep, forKey: Keys.alertBeep) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let bundledBaseURL = AppSettings.bundledValue("AIBaseURL")
        let bundledModel = AppSettings.bundledValue("AIModel")
        let bundledKey = AppSettings.bundledValue("AIApiKey")

        baseURL = defaults.string(forKey: Keys.baseURL) ?? bundledBaseURL ?? AIConfig.ckeyBaseURL
        model = defaults.string(forKey: Keys.model) ?? bundledModel ?? AIConfig.defaultModel

        let savedTemperature = defaults.object(forKey: Keys.temperature) as? Double
        temperature = savedTemperature ?? 0.2

        let savedKey = KeychainStore.read(Keys.apiKey)
        apiKey = savedKey.isEmpty ? (bundledKey ?? "") : savedKey

        useAI = defaults.object(forKey: Keys.useAI) as? Bool ?? true
        mapProvider = MapProvider.savedValue(defaults.string(forKey: Keys.mapProvider))
        mapTypeIndex = defaults.object(forKey: Keys.mapType) as? Int ?? 0
        showTraffic = defaults.object(forKey: Keys.traffic) as? Bool ?? false
        showPOIs = defaults.object(forKey: Keys.pois) as? Bool ?? true
        voiceGuidance = defaults.object(forKey: Keys.voiceGuidance) as? Bool ?? true
        alertBeep = defaults.object(forKey: Keys.alertBeep) as? Bool ?? true
    }

    var config: AIConfig {
        AIConfig(baseURL: baseURL, model: model, apiKey: apiKey, temperature: temperature)
    }

    /// Đặt nhanh cấu hình theo nhà cung cấp.
    func applyPreset(baseURL: String, model: String) {
        self.baseURL = baseURL
        self.model = model
    }

    func clearAPIKey() {
        apiKey = ""
    }

    /// Giá trị nhúng lúc build (từ GitHub Secrets). Trả nil nếu chưa cấu hình.
    static func bundledValue(_ key: String, bundle: Bundle = .main) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("$(") { return nil }
        return trimmed
    }
}

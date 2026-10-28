import Foundation
import Combine

/// Cài đặt người dùng: lưu trong UserDefaults; API key VietMap nằm trong Keychain
/// (không bao giờ ghi vào repo hay file log).
@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let mapType = "vietmap.map.type"
        static let traffic = "vietmap.map.traffic"
        static let pois = "vietmap.map.pois"

        static let voiceAlerts = "vietmap.alert.voice"
        static let alertPins = "vietmap.alert.pins"
        static let tolerance = "vietmap.alert.tolerance"
        static let alertKinds = "vietmap.alert.kinds"
        static let defaultMode = "vietmap.route.mode"
        static let alertsImported = "vietmap.alert.importedCount"
        static let vehicleClass = "vietmap.alert.vehicleClass"
        static let navigationPitch = "vietmap.map.navigationPitch"
        static let followOnStart = "vietmap.map.followOnStart"

        // AI
        static let aiBaseURL = "vietmap.ai.baseURL"
        static let aiModel = "vietmap.ai.model"
        static let aiTemperature = "vietmap.ai.temperature"
        static let aiEnabled = "vietmap.ai.enabled"
        static let aiDeep = "vietmap.ai.deep"
        static let aiPreference = "vietmap.route.preference"
        /// Key nằm trong Keychain, không bao giờ ghi vào UserDefaults.
        static let aiKey = "ai.api.key"
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

    // MARK: Trợ lý AI (Ckey.vn hoặc base URL tuỳ chỉnh)

    /// Base URL kiểu OpenAI. Mặc định Ckey.vn: `https://api.xah.io/v1`.
    @Published var aiBaseURL: String {
        didSet { defaults.set(aiBaseURL, forKey: Keys.aiBaseURL) }
    }
    /// Tên model — gõ tay được, không giới hạn danh sách.
    @Published var aiModel: String {
        didSet { defaults.set(aiModel, forKey: Keys.aiModel) }
    }
    @Published var aiTemperature: Double {
        didSet { defaults.set(aiTemperature, forKey: Keys.aiTemperature) }
    }
    @Published var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: Keys.aiEnabled) }
    }
    /// Cho AI can thiệp sâu: chọn tuyến, thêm điểm dừng, đổi mức ưu tiên.
    @Published var aiDeepPlanning: Bool {
        didSet { defaults.set(aiDeepPlanning, forKey: Keys.aiDeep) }
    }
    /// API key AI (Keychain).
    @Published var aiAPIKey: String {
        didSet { KeychainStore.save(aiAPIKey, for: Keys.aiKey) }
    }
    /// Mức ưu tiên chọn tuyến mặc định.
    @Published var routePreference: RoutePreference {
        didSet { defaults.set(routePreference.rawValue, forKey: Keys.aiPreference) }
    }

    // MARK: Cảnh báo giao thông

    @Published var voiceAlerts: Bool {
        didSet { defaults.set(voiceAlerts, forKey: Keys.voiceAlerts) }
    }
    @Published var showAlertPins: Bool {
        didSet { defaults.set(showAlertPins, forKey: Keys.alertPins) }
    }
    @Published var overspeedTolerance: Int {
        didSet { defaults.set(overspeedTolerance, forKey: Keys.tolerance) }
    }
    /// Loại cảnh báo người dùng muốn nhận.
    @Published var alertKinds: Set<AlertKind> {
        didSet {
            defaults.set(alertKinds.map(\.rawValue).sorted(), forKey: Keys.alertKinds)
        }
    }
    /// Nhóm xe hai bánh — đổi bảng tốc độ mặc định (thanh tốc độ + biển báo trên bản đồ).
    @Published var vehicleClass: VehicleClass {
        didSet { defaults.set(vehicleClass.rawValue, forKey: Keys.vehicleClass) }
    }
    /// Bản đồ nghiêng 3D khi dẫn đường (tắt = chế độ 2D nhìn từ trên xuống).
    @Published var navigationPitch3D: Bool {
        didSet { defaults.set(navigationPitch3D, forKey: Keys.navigationPitch) }
    }
    /// Tự bám theo vị trí khi bắt đầu dẫn đường.
    @Published var followUserInNavigation: Bool {
        didSet { defaults.set(followUserInNavigation, forKey: Keys.followOnStart) }
    }
    /// Phương tiện mặc định khi mở app.
    @Published var defaultMode: TravelMode {
        didSet { defaults.set(defaultMode.rawValue, forKey: Keys.defaultMode) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        aiBaseURL = defaults.string(forKey: Keys.aiBaseURL) ?? AIConfig.defaultBaseURL
        aiModel = defaults.string(forKey: Keys.aiModel) ?? AIConfig.defaultModel
        aiTemperature = defaults.object(forKey: Keys.aiTemperature) as? Double ?? 0.2
        aiEnabled = defaults.object(forKey: Keys.aiEnabled) as? Bool ?? true
        aiDeepPlanning = defaults.object(forKey: Keys.aiDeep) as? Bool ?? true
        aiAPIKey = KeychainStore.read(Keys.aiKey)
        routePreference = RoutePreference(rawValue: defaults.string(forKey: Keys.aiPreference) ?? "")
            ?? .fastest

        mapTypeIndex = defaults.object(forKey: Keys.mapType) as? Int ?? 0
        showTraffic = defaults.object(forKey: Keys.traffic) as? Bool ?? false
        showPOIs = defaults.object(forKey: Keys.pois) as? Bool ?? true

        voiceAlerts = defaults.object(forKey: Keys.voiceAlerts) as? Bool ?? true
        showAlertPins = defaults.object(forKey: Keys.alertPins) as? Bool ?? true
        overspeedTolerance = defaults.object(forKey: Keys.tolerance) as? Int ?? 5

        let savedKinds = defaults.stringArray(forKey: Keys.alertKinds)
        let kinds = savedKinds?.compactMap { AlertKind(rawValue: $0) } ?? AlertKind.allCases
        alertKinds = Set(kinds.isEmpty ? AlertKind.allCases : kinds)

        vehicleClass = VehicleClass(rawValue: defaults.string(forKey: Keys.vehicleClass) ?? "") ?? .motorcycle
        navigationPitch3D = defaults.object(forKey: Keys.navigationPitch) as? Bool ?? true
        followUserInNavigation = defaults.object(forKey: Keys.followOnStart) as? Bool ?? true
        defaultMode = TravelMode(rawValue: defaults.string(forKey: Keys.defaultMode) ?? "") ?? .motorcycle
    }

    /// Cấu hình AI hiện tại (ghép từ các trường ở trên).
    var aiConfig: AIConfig {
        AIConfig(baseURL: aiBaseURL,
                 model: aiModel,
                 apiKey: aiAPIKey,
                 temperature: aiTemperature,
                 enabled: aiEnabled,
                 deepPlanning: aiDeepPlanning)
    }

    var hasAIKey: Bool {
        !aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Tên hiển thị nhà cung cấp dựa trên base URL.
    var aiProviderName: String {
        let url = aiBaseURL.lowercased()
        if url.contains("xah.io") || url.contains("ckey") { return "Ckey.vn" }
        if url.contains("openai.com") { return "OpenAI" }
        if url.contains("groq.com") { return "Groq" }
        if url.contains("openrouter") { return "OpenRouter" }
        if url.contains("11434") { return "Ollama" }
        if url.contains("1234") { return "LM Studio" }
        return aiConfig.host
    }

    func applyAIPreset(_ preset: AIProviderPreset) {
        aiBaseURL = preset.baseURL
        aiModel = preset.model
        aiEnabled = true
    }

    var alertPreferences: AlertPreferences {
        var preferences = AlertPreferences()
        preferences.voiceEnabled = voiceAlerts
        preferences.showOnMap = showAlertPins
        preferences.overspeedTolerance = overspeedTolerance
        preferences.enabledKinds = alertKinds
        preferences.vehicleClass = vehicleClass
        return preferences
    }

    func toggleAlertKind(_ kind: AlertKind) {
        if alertKinds.contains(kind) {
            alertKinds.remove(kind)
        } else {
            alertKinds.insert(kind)
        }
    }

    func setAlertKinds(_ kinds: [AlertKind], enabled: Bool) {
        for kind in kinds {
            if enabled {
                alertKinds.insert(kind)
            } else {
                alertKinds.remove(kind)
            }
        }
    }


}

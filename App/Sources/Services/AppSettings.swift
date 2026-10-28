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

        static let vietmapKey = "vietmap.api.key"
        static let voiceAlerts = "vietmap.alert.voice"
        static let hudAutoOpen = "vietmap.alert.hud"
        static let alertPins = "vietmap.alert.pins"
        static let tolerance = "vietmap.alert.tolerance"
        static let alertKinds = "vietmap.alert.kinds"
        static let defaultMode = "vietmap.route.mode"
        static let alertsImported = "vietmap.alert.importedCount"
        static let vehicleClass = "vietmap.alert.vehicleClass"
        static let navigationPitch = "vietmap.map.navigationPitch"
        static let followOnStart = "vietmap.map.followOnStart"
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

    // MARK: Cảnh báo giao thông

    /// API key VietMap (Keychain) — bật hồ sơ dẫn đường xe máy thật.
    @Published var vietmapAPIKey: String {
        didSet { KeychainStore.save(vietmapAPIKey, for: Keys.vietmapKey) }
    }
    @Published var voiceAlerts: Bool {
        didSet { defaults.set(voiceAlerts, forKey: Keys.voiceAlerts) }
    }
    @Published var hudAutoOpen: Bool {
        didSet { defaults.set(hudAutoOpen, forKey: Keys.hudAutoOpen) }
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
    /// Nhóm xe hai bánh — đổi bảng tốc độ mặc định trong HUD.
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

        mapTypeIndex = defaults.object(forKey: Keys.mapType) as? Int ?? 0
        showTraffic = defaults.object(forKey: Keys.traffic) as? Bool ?? false
        showPOIs = defaults.object(forKey: Keys.pois) as? Bool ?? true

        vietmapAPIKey = KeychainStore.read(Keys.vietmapKey)
        voiceAlerts = defaults.object(forKey: Keys.voiceAlerts) as? Bool ?? true
        hudAutoOpen = defaults.object(forKey: Keys.hudAutoOpen) as? Bool ?? true
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

    /// API key VietMap đã chuẩn hoá (rỗng = chưa có).
    var vietmapKey: String {
        vietmapAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasVietMapKey: Bool { !vietmapKey.isEmpty }

    var alertPreferences: AlertPreferences {
        var preferences = AlertPreferences()
        preferences.voiceEnabled = voiceAlerts
        preferences.hudAutoOpen = hudAutoOpen
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

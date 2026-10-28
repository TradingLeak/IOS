import Foundation

/// Thông tin build được nhúng vào Info.plist lúc compile.
/// Đọc an toàn: nếu giá trị rỗng hoặc chưa được thay thế (`$(...)`) thì trả về fallback.
struct BuildInfo {
    let displayName: String
    let version: String
    let buildNumber: String
    let bundleIdentifier: String
    let minimumOS: String
    let buildDate: String
    let gitCommit: String
    let isSigned: Bool
    let architecture: String

    static let current = BuildInfo(bundle: .main)

    init(bundle: Bundle) {
        let info = bundle.infoDictionary ?? [:]

        func string(_ key: String, fallback: String = "—") -> String {
            guard let raw = info[key] as? String else { return fallback }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("$(") { return fallback }
            return trimmed
        }

        displayName = string("CFBundleDisplayName", fallback: string("CFBundleName", fallback: "App"))
        version = string("CFBundleShortVersionString")
        buildNumber = string("CFBundleVersion")
        bundleIdentifier = string("CFBundleIdentifier")
        minimumOS = string("MinimumOSVersion")
        gitCommit = string("GitCommit", fallback: "local")
        isSigned = bundle.path(forResource: "embedded", ofType: "mobileprovision") != nil

        let rawDate = string("BuildDate", fallback: "")
        buildDate = BuildInfo.prettyDate(from: rawDate)

        #if arch(arm64)
        architecture = "arm64"
        #elseif arch(x86_64)
        architecture = "x86_64"
        #else
        architecture = "unknown"
        #endif
    }

    private static func prettyDate(from raw: String) -> String {
        guard !raw.isEmpty else { return "không rõ" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let date = parser.date(from: raw) else { return raw }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm dd/MM/yyyy"
        return formatter.string(from: date) + " (UTC)"
    }
}

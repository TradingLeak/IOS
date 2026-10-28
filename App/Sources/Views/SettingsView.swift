import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: MapViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var showAPIKey = false
    @State private var showVietMapKey = false
    @State private var testState: TestState = .idle
    @State private var showAlertsManager = false

    private let client = AIClient()

    enum TestState {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    aiCard
                    presetsCard
                    routingCard
                    alertsCard
                    mapCard
                    dataCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .sheet(isPresented: $showAlertsManager) {
                AlertsSheet(model: model, settings: settings)
            }
        }
    }

    // MARK: - AI

    private var aiCard: some View {
        SectionCard(title: "Kết nối AI", symbol: "sparkles") {
            VStack(alignment: .leading, spacing: 14) {
                labeledField(title: "Base URL") {
                    TextField("https://api.xah.io/v1", text: $settings.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(size: 14, design: .monospaced))
                }

                labeledField(title: "Model") {
                    TextField("gpt-4o-mini", text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))
                }

                labeledField(title: "API key") {
                    HStack(spacing: 8) {
                        Group {
                            if showAPIKey {
                                TextField("sk-…", text: $settings.apiKey)
                            } else {
                                SecureField("sk-…", text: $settings.apiKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))

                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Key được lưu trong Keychain của máy, không gửi đi đâu ngoài máy chủ AI bạn cấu hình.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Độ sáng tạo (temperature)")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(String(format: "%.1f", settings.temperature))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.temperature, in: 0...1, step: 0.1)
                        .tint(AppTheme.accent)
                }

                HStack(spacing: 10) {
                    Button {
                        runTest()
                    } label: {
                        HStack(spacing: 6) {
                            if case .testing = testState {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.horizontal.circle.fill")
                            }
                            Text("Kiểm tra kết nối")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .primaryGradientBackground(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(!settings.config.isConfigured || isTesting)

                    Button {
                        settings.apiKey = ""
                        testState = .idle
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.danger)
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.danger.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Xoá API key")
                }

                switch testState {
                case .idle:
                    EmptyView()
                case .testing:
                    InfoBanner(kind: .info, text: "Đang gọi thử \(settings.model)…")
                case .success(let reply):
                    InfoBanner(kind: .success, text: "Kết nối OK. Model trả lời: “\(reply)”")
                case .failure(let message):
                    InfoBanner(kind: .error, text: message)
                }
            }
        }
    }

    private var presetsCard: some View {
        SectionCard(title: "Cấu hình nhanh", symbol: "bolt.fill") {
            VStack(spacing: 8) {
                presetRow(title: "ckey.vn (mặc định)",
                          detail: AIConfig.ckeyBaseURL + " · gpt-4o-mini",
                          baseURL: AIConfig.ckeyBaseURL,
                          modelName: AIConfig.defaultModel)
                presetRow(title: "OpenAI",
                          detail: "https://api.openai.com/v1 · gpt-4o-mini",
                          baseURL: "https://api.openai.com/v1",
                          modelName: "gpt-4o-mini")
                presetRow(title: "Groq",
                          detail: "https://api.groq.com/openai/v1 · llama-3.3-70b-versatile",
                          baseURL: "https://api.groq.com/openai/v1",
                          modelName: "llama-3.3-70b-versatile")
                presetRow(title: "Ollama trên máy (LAN)",
                          detail: "http://192.168.1.10:11434/v1 · qwen2.5",
                          baseURL: "http://192.168.1.10:11434/v1",
                          modelName: "qwen2.5")
            }
        }
    }

    private func presetRow(title: String, detail: String, baseURL: String, modelName: String) -> some View {
        Button {
            settings.applyPreset(baseURL: baseURL, model: modelName)
            testState = .idle
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: settings.baseURL == baseURL ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(settings.baseURL == baseURL ? AppTheme.accent : Color.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.subtleFill)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dẫn đường xe máy

    private var routingCard: some View {
        SectionCard(title: "Dẫn đường xe máy", symbol: "scooter") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Maps không có hồ sơ xe máy. Nhập API key VietMap để có tuyến xe máy thật "
                         + "(đi đúng đường cho phép, tránh cao tốc):")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Đăng ký key VietMap (có gói miễn phí) →",
                         destination: URL(string: "https://maps.vietmap.vn/console-v2/register")!)
                        .font(.system(size: 11, weight: .semibold))
                }

                labeledField(title: "VietMap API key") {
                    HStack(spacing: 8) {
                        Group {
                            if showVietMapKey {
                                TextField("vietmap key", text: $settings.vietmapAPIKey)
                            } else {
                                SecureField("vietmap key", text: $settings.vietmapAPIKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))

                        Button {
                            showVietMapKey.toggle()
                        } label: {
                            Image(systemName: showVietMapKey ? "eye.slash" : "eye")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                InfoBanner(kind: settings.hasVietMapKey ? .success : .info,
                           text: settings.hasVietMapKey
                           ? "Đang dùng VietMap Route v4 (vehicle=motorcycle)."
                           : "Chưa có key → app ước lượng tuyến xe máy từ Apple Maps và cảnh báo nếu có cao tốc.")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Phương tiện mặc định")
                        .font(.system(size: 12, weight: .medium))
                    TravelModePicker(selection: $settings.defaultMode)
                }
            }
        }
    }

    // MARK: - Cảnh báo & HUD

    private var alertsCard: some View {
        SectionCard(title: "Cảnh báo & HUD", symbol: "exclamationmark.shield") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $settings.voiceAlerts) {
                    Label("Đọc cảnh báo bằng giọng tiếng Việt", systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)

                Toggle(isOn: $settings.hudAutoOpen) {
                    Label("Tự mở HUD tốc độ khi bắt đầu dẫn đường", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)

                Toggle(isOn: $settings.showAlertPins) {
                    Label("Hiện camera/cảnh báo trên bản đồ", systemImage: "camera.fill")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Ngưỡng báo vượt tốc độ")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("+\(settings.overspeedTolerance) km/h")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Stepper("", value: $settings.overspeedTolerance, in: 0...20)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Loại cảnh báo")
                        .font(.system(size: 12, weight: .medium))
                    kindChips(AlertKind.cameraKinds)
                    kindChips(AlertKind.speedKinds)
                    kindChips(AlertKind.otherKinds)
                }

                Button {
                    showAlertsManager = true
                } label: {
                    HStack {
                        Label("Quản lý dữ liệu cảnh báo", systemImage: "externaldrive.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(model.alertDatabase.count)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.subtleFill)
                    )
                }
                .buttonStyle(.plain)

                Text("Giới hạn tốc độ lấy theo biển báo/vùng đã nhập, dữ liệu OpenStreetMap, "
                     + "sau đó mới tới bảng mặc định của Thông tư 38/2024/TT-BGTVT. "
                     + "Cảnh báo chỉ để tham khảo — luôn tuân theo biển báo tại chỗ.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func kindChips(_ kinds: [AlertKind]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(kinds) { kind in
                    AlertKindChip(kind: kind, isOn: settings.alertKinds.contains(kind)) {
                        settings.toggleAlertKind(kind)
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    // MARK: - Map

    private var mapCard: some View {
        SectionCard(title: "Bản đồ", symbol: "map") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Kiểu bản đồ", selection: $settings.mapTypeIndex) {
                    Text("Tiêu chuẩn").tag(0)
                    Text("Vệ tinh lai").tag(1)
                    Text("Vệ tinh").tag(2)
                    Text("Tối giản").tag(3)
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $settings.showTraffic) {
                    Label("Hiện mật độ giao thông", systemImage: "car.2.fill")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)

                Toggle(isOn: $settings.showPOIs) {
                    Label("Hiện địa điểm của Apple Maps", systemImage: "mappin.and.ellipse")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)
            }
        }
    }

    // MARK: - Data

    private var dataCard: some View {
        SectionCard(title: "Dữ liệu", symbol: "externaldrive.fill") {
            VStack(spacing: 8) {
                Button {
                    model.clearHistory()
                } label: {
                    HStack {
                        Label("Xoá lịch sử tìm kiếm", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 13))
                        Spacer()
                        Text("\(model.recents.count)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.subtleFill)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    model.clearFavorites()
                } label: {
                    HStack {
                        Label("Xoá địa điểm yêu thích", systemImage: "star.slash")
                            .font(.system(size: 13))
                        Spacer()
                        Text("\(model.favorites.count)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.subtleFill)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        SectionCard(title: "Về ứng dụng", symbol: "info.circle") {
            VStack(alignment: .leading, spacing: 6) {
                infoRow("Phiên bản", "\(AppInfo.current.version) (\(AppInfo.current.build))")
                infoRow("Bundle ID", AppInfo.current.bundleIdentifier)
                infoRow("Commit", AppInfo.current.commit)
                infoRow("Bản đồ", "Apple Maps (MapKit)")
                infoRow("Xe máy", settings.hasVietMapKey ? "VietMap Route v4" : "ước lượng Apple Maps")
                infoRow("Cảnh báo", "\(model.alertDatabase.count) điểm")
                infoRow("AI", settings.config.isConfigured ? settings.model : "chưa cấu hình")

                Text("Bản IPA này không có chữ ký Apple: dùng TrollStore (iOS ≤ 17.0) "
                     + "hoặc ký lại bằng Apple ID miễn phí (Sideloadly/SideStore) để cài.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Field

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.subtleFill)
                )
        }
    }

    private var isTesting: Bool {
        if case .testing = testState { return true }
        return false
    }

    private func runTest() {
        testState = .testing
        let config = settings.config
        Task {
            let result = await client.ping(config: config)
            switch result {
            case .success(let reply):
                testState = .success(String(reply.prefix(60)))
            case .failure(let error):
                testState = .failure(error.localizedDescription)
            }
        }
    }
}

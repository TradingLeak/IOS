import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: MapViewModel
    @ObservedObject var offlineMaps: OfflineMapStore = .shared
    @State private var showsOfflineDownload = false
    /// HUD speedmap (tuỳ chọn) — hiển thị chẩn đoán dữ liệu .bin trong app.
    var hud: SpeedmapController? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var showAPIKey = false
    @State private var testState: TestState = .idle
    @State private var selfTestText: String?

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
                    mapCard
                    navCard
                    dataCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .onAppear { runSpeedmapSelfTestIfNeeded() }
            .onChange(of: settings.mapProvider) { provider in
                if provider == .openStreetMap, !offlineMaps.isReady { showsOfflineDownload = true }
            }
            .sheet(isPresented: $showsOfflineDownload) {
                OfflineMapDownloadView(store: offlineMaps) { settings.mapProvider = .apple }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
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

    // MARK: - Map

    private var mapCard: some View {
        SectionCard(title: "Bản đồ", symbol: "map") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Nguồn bản đồ", selection: $settings.mapProvider) {
                    ForEach(MapProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                Button { showsOfflineDownload = true } label: {
                    Label(offlineMaps.isReady ? "Quản lý gói Việt Nam đã tải" : "Tải bản đồ Việt Nam offline",
                          systemImage: "arrow.down.circle")
                }

                Picker("Kiểu bản đồ", selection: $settings.mapTypeIndex) {
                    Text("Tiêu chuẩn").tag(0)
                    Text("Vệ tinh lai").tag(1)
                    Text("Vệ tinh").tag(2)
                    Text("Tối giản").tag(3)
                }
                .pickerStyle(.segmented)
                .disabled(settings.mapProvider != .apple)

                Toggle(isOn: $settings.showTraffic) {
                    Label("Hiện mật độ giao thông", systemImage: "car.2.fill")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)
                .disabled(settings.mapProvider != .apple)

                Toggle(isOn: $settings.showPOIs) {
                    Label("Hiện địa điểm của Apple Maps", systemImage: "mappin.and.ellipse")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)
                .disabled(settings.mapProvider != .apple)
                if settings.mapProvider == .openStreetMap {
                    Link("© OpenStreetMap contributors", destination: OpenStreetMapOverlay.copyrightURL)
                        .font(.system(size: 12, weight: .semibold))
                    Text("Bản đồ OSM chỉ đọc từ gói Việt Nam đã tải trên iPhone, không tải tile trực tuyến. Nhãn/POI nằm sẵn trong tile. Tìm kiếm và tính tuyến vẫn dùng Apple Maps; cảnh báo VietHUD không đổi.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Chỉ đường & cảnh báo

    private var navCard: some View {
        SectionCard(title: "Chỉ đường & cảnh báo", symbol: "speaker.wave.2.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $settings.voiceGuidance) {
                    Label("Giọng nói tiếng Việt", systemImage: "waveform")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)

                Toggle(isOn: $settings.alertBeep) {
                    Label("Tiếng báo khi gặp camera/biển báo", systemImage: "bell.badge.fill")
                        .font(.system(size: 13))
                }
                .tint(AppTheme.accent)

                Divider().overlay(AppTheme.subtleFill)

                if let hud, let meta = hud.metadata {
                    infoRow("Speedmap", "\(meta.mapVersion) · \(meta.region)")
                    infoRow("Mạng đường", "\(meta.segmentCount.formatted()) đoạn · \(meta.tileCount.formatted()) tile")
                    infoRow("Nguồn dữ liệu", meta.attribution)
                if let selfTestText {
                    infoRow("Tự kiểm tra", selfTestText)
                }
                if let source = hud.database?.sourceDirectory.path {
                    infoRow("Nơi nạp file", source)
                }
                } else {
                    Text("Chưa nạp được 7 file speedmap (.bin) — cảnh báo biển báo sẽ ẩn.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func runSpeedmapSelfTestIfNeeded() {
        guard selfTestText == nil, let hud, hud.isReady else { return }
        if let passed = hud.runSelfTest() {
            selfTestText = passed ? "PASS (khớp điểm thử)" : "FAIL"
        } else {
            selfTestText = "metadata không có điểm thử"
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
                infoRow("Bản đồ nền", settings.mapProvider.title)
                infoRow("Tìm kiếm / tính tuyến", "Apple Maps")
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

import SwiftUI

/// Mục **Cài đặt → Trợ lý AI**: chọn nhà cung cấp, base URL tự nhập, model, key, mức can thiệp.
///
/// Nguyên tắc: không có key vẫn dùng được app — bộ phân tích tiếng Việt trên máy
/// (`RouteIntentParser`) đảm nhiệm việc hiểu câu lệnh, chỉ phần nhận xét/narration mới cần AI.
@MainActor
struct AISettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: MapViewModel

    @State private var showKey = false
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, running, ok(String), failed(String)
    }

    var body: some View {
        SectionCard(title: "Trợ lý AI", symbol: "sparkles") {
            VStack(alignment: .leading, spacing: 14) {
                header
                toggleRow(title: "Bật trợ lý AI",
                          detail: "Hiểu câu lệnh tiếng Việt, chọn tuyến và giải thích vì sao.",
                          isOn: $settings.aiEnabled)
                if settings.aiEnabled {
                    deepRow
                    presetPicker
                    baseURLField
                    modelField
                    keyField
                    temperatureRow
                    testRow
                }
                fallbackNote
            }
        }
    }

    // MARK: - Đầu mục

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: settings.hasAIKey ? "checkmark.seal.fill" : "questionmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settings.hasAIKey ? AppTheme.success : AppTheme.warning)
            Text(settings.hasAIKey
                 ? "\(settings.aiProviderName) đã sẵn sàng"
                 : "Chưa có API key — app vẫn tìm tuyến được")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Link("Tạo key Ckey.vn →", destination: URL(string: "https://ckey.vn")!)
                .font(.system(size: 10, weight: .semibold))
        }
    }

    private var deepRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            toggleRow(title: "Cho AI can thiệp sâu",
                      detail: "AI được chọn tuyến, thêm điểm dừng và đổi phương tiện — không chỉ góp ý.",
                      isOn: $settings.aiDeepPlanning)
            HStack(spacing: 5) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 9, weight: .bold))
                Text("Toạ độ và đường đi vẫn do MapKit tính, AI không tự bịa đường.")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
        }
    }

    // MARK: - Nhà cung cấp

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NHÀ CUNG CẤP")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 7)], spacing: 7) {
                ForEach(AIProviderPreset.all) { preset in
                    Button {
                        settings.applyAIPreset(preset)
                        testState = .idle
                        pushToModel()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text(preset.model)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isCurrentPreset(preset) ? AppTheme.accent.opacity(0.14) : AppTheme.subtleFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isCurrentPreset(preset) ? AppTheme.accent.opacity(0.55) : Color.clear,
                                        lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Ckey.vn là mặc định — base https://api.xah.io/v1, cùng chuẩn OpenAI nên đổi nhà cung cấp rất nhanh.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func isCurrentPreset(_ preset: AIProviderPreset) -> Bool {
        settings.aiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ==
            preset.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Base URL / model

    private var baseURLField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("BASE URL (tự nhập)")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)

            TextField("https://api.xah.io/v1", text: $settings.aiBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.subtleFill)
                )
                .onChange(of: settings.aiBaseURL) { _ in
                    testState = .idle
                    pushToModel()
                }

            if let endpoint = settings.aiConfig.chatCompletionsURL {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8, weight: .bold))
                    Text(endpoint.absoluteString)
                        .font(.system(size: 9, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
            } else {
                Text("Base URL chưa hợp lệ.")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.danger)
            }
        }
    }

    private var modelField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MODEL")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            TextField("gpt-4o-mini", text: $settings.aiModel)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.subtleFill)
                )
                .onChange(of: settings.aiModel) { _ in
                    testState = .idle
                    pushToModel()
                }
        }
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("API KEY")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Group {
                    if showKey {
                        TextField("dán key vào đây", text: $settings.aiAPIKey)
                    } else {
                        SecureField("dán key vào đây", text: $settings.aiAPIKey)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.subtleFill)
                )
                .onChange(of: settings.aiAPIKey) { _ in
                    testState = .idle
                    pushToModel()
                }

                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(AppTheme.subtleFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showKey ? "Ẩn key" : "Hiện key")
            }

            Text("Key lưu trong Keychain của máy, không ghi vào tệp cài đặt và không gửi cho ai ngoài nhà cung cấp bạn chọn.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var temperatureRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Mức sáng tạo")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Text(String(format: "%.1f", settings.aiTemperature))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $settings.aiTemperature, in: 0...1, step: 0.1)
                .onChange(of: settings.aiTemperature) { _ in pushToModel() }
            Text("Thấp (0.2) cho dẫn đường chính xác; cao hơn để AI viết lời giải thích tự nhiên hơn.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Kiểm tra kết nối

    private var testRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await runTest() }
            } label: {
                HStack(spacing: 6) {
                    if testState == .running {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "bolt.horizontal.circle")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text("Kiểm tra kết nối")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(AppTheme.accent.opacity(0.14)))
                .foregroundStyle(AppTheme.accentDeep)
            }
            .buttonStyle(.plain)
            .disabled(testState == .running || !settings.aiConfig.isConfigured)

            switch testState {
            case .idle:
                EmptyView()
            case .running:
                Text("Đang gửi một câu thử tới \(settings.aiConfig.host)…")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            case .ok(let reply):
                Label("Kết nối tốt · AI trả lời: \(reply)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.success)
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func runTest() async {
        testState = .running
        let result = await AIClient().ping(config: settings.aiConfig)
        switch result {
        case .success(let reply):
            testState = .ok(reply)
        case .failure(let error):
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            testState = .failed(message)
        }
    }

    // MARK: - Phương án không có AI

    private var fallbackNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 10, weight: .bold))
                Text("Khi không có AI")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(AppTheme.warning)

            Text("App luôn có bộ phân tích tiếng Việt trên máy: vẫn hiểu “xe máy”, “tránh cao tốc”, "
                 + "“ít camera”, “ghé cây xăng”, vẫn xếp hạng tuyến theo điểm 0–100 và cảnh báo tốc độ. "
                 + "AI chỉ thêm phần đọc câu lệnh tự do và lời giải thích.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Tiện ích

    private func toggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(AppTheme.accent)
        .onChange(of: isOn.wrappedValue) { _ in pushToModel() }
    }

    private func pushToModel() {
        model.aiConfig = settings.aiConfig
        model.preference = settings.routePreference
    }
}

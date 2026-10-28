import SwiftUI

@MainActor
struct AIAssistantSheet: View {
    @ObservedObject var model: MapViewModel
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void

    @State private var input = ""
    @State private var showSettings = false
    @FocusState private var isFocused: Bool

    private let suggestions = [
        "Đi từ Cầu Giấy đến Hồ Tây",
        "Chỉ đường đi bộ từ Hồ Hoàn Kiếm đến Nhà thờ Lớn",
        "Từ sân bay Nội Bài về trung tâm Hà Nội",
        "Đi xe buýt từ Bến Thành đến Suối Tiên",
        "Từ Đà Nẵng đến Hội An, ghé Ngũ Hành Sơn"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !settings.config.isConfigured {
                    InfoBanner(kind: .warning,
                               text: "Chưa có API key. Bạn vẫn dùng được bộ phân tích offline (hiểu câu cơ bản), "
                                   + "hoặc nhập key để AI hiểu câu tự nhiên tốt hơn.")
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .onTapGesture { showSettings = true }
                }

                transcriptView
                suggestionRow
                inputBar
            }
            .navigationTitle("Trợ lý chỉ đường")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { onClose() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings, model: model)
        }
    }

    // MARK: - Transcript

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.transcript) { message in
                        bubble(message)
                    }
                    if model.aiThinking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Đang tìm tuyến…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: model.transcript.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: model.aiThinking) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func bubble(_ message: AIChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.text)
                .font(.system(size: 14))
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(message.role == .user
                              ? AnyShapeStyle(AppTheme.accentGradient)
                              : AnyShapeStyle(message.isError ? AppTheme.danger.opacity(0.12) : AppTheme.card))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: message.role == .user ? 0 : 1)
                )
                .fixedSize(horizontal: false, vertical: true)

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    // MARK: - Suggestions & input

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { text in
                    Button {
                        send(text)
                    } label: {
                        Text(text)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(AppTheme.subtleFill)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.aiThinking)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ví dụ: đi từ Cầu Giấy đến Hồ Tây…", text: $input, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(1...3)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.subtleFill)
                )

            Button {
                send(input)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppTheme.accentGradient))
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.aiThinking)
            .opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.aiThinking ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        input = ""
        isFocused = false
        Task { await model.askAI(prompt) }
    }
}

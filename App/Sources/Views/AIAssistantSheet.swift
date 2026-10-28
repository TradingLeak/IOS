import SwiftUI

/// Cửa sổ trợ lý AI: hiểu câu tiếng Việt, dựng kế hoạch chuyến đi và giải thích tuyến.
///
/// AI chỉ trả **ý định + nhận xét**; toạ độ và tuyến đường vẫn do MapKit/VietMap tính,
/// nên không bao giờ có chuyện AI bịa ra con đường không tồn tại.
@MainActor
struct AIAssistantSheet: View {
    @ObservedObject var model: MapViewModel
    @ObservedObject var settings: AppSettings
    var onOpenSettings: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "đi xe máy từ Cầu Giấy đến Hồ Hoàn Kiếm, tránh cao tốc",
        "ô tô từ Ngã tư Sở đến sân bay Nội Bài, ít camera nhất",
        "đi bộ từ Hồ Tây đến phố cổ, ghé cà phê",
        "xe máy từ Đà Nẵng đến Hội An lúc 8 giờ sáng"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            providerCard

                            if model.transcript.isEmpty {
                                emptyState
                            } else {
                                ForEach(model.transcript) { bubble in
                                    bubbleView(bubble)
                                        .id(bubble.id)
                                }
                            }

                            if model.aiThinking {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("AI đang đọc câu lệnh và tính kế hoạch…")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.leading, 4)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: model.transcript.count) { _ in
                        if let last = model.transcript.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                composer
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Trợ lý AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        dismiss()
                        onOpenSettings?()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Cài đặt AI")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Trạng thái nhà cung cấp

    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.aiConfig.isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.aiConfig.isConfigured ? AppTheme.success : AppTheme.warning)
                Text(model.aiConfig.isConfigured
                     ? "\(settings.aiProviderName) · \(settings.aiModel)"
                     : (settings.aiEnabled ? "Chưa có API key AI" : "AI đang tắt"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                if model.aiConfig.isConfigured, model.aiConfig.deepPlanning {
                    Text("can thiệp sâu")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppTheme.accent.opacity(0.15)))
                        .foregroundStyle(AppTheme.accent)
                }
            }

            Text(settings.aiBaseURL)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !model.aiConfig.isConfigured {
                Text(settings.aiEnabled
                     ? "Nhập API key trong Cài đặt → Trợ lý AI. Không có key, app vẫn tìm tuyến bằng bộ phân tích tiếng Việt trên máy."
                     : "Bật AI trong Cài đặt để hiểu câu lệnh tự nhiên và để AI chọn tuyến giúp bạn.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                )
        )
    }

    // MARK: - Gợi ý

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nói kiểu bạn hay nói")
                .font(.system(size: 14, weight: .semibold))

            Text("AI hiểu phương tiện, điểm đi/đến, nơi muốn ghé, giờ khởi hành và mức ưu tiên "
                 + "(nhanh nhất / ít camera / tránh cao tốc). Sau đó app mới tính tuyến thật.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    input = suggestion
                    send()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                        Text(suggestion)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
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

    // MARK: - Bong bóng chat

    private func bubbleView(_ bubble: AIChatBubble) -> some View {
        HStack {
            if bubble.role == .user { Spacer(minLength: 40) }
            Text(bubble.text)
                .font(.system(size: 13))
                .foregroundStyle(bubble.role == .user ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(bubble.role == .user
                              ? AnyShapeStyle(AppTheme.accentGradient)
                              : AnyShapeStyle(bubble.isError
                                              ? AppTheme.danger.opacity(0.12)
                                              : AppTheme.card))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(bubble.role == .user ? Color.clear : AppTheme.cardStroke, lineWidth: 1)
                )
                .fixedSize(horizontal: false, vertical: true)
            if bubble.role == .assistant { Spacer(minLength: 40) }
        }
    }

    // MARK: - Ô nhập

    private var composer: some View {
        VStack(spacing: 8) {
            if let plan = model.aiPlan {
                planSummary(plan)
            }

            HStack(spacing: 8) {
                TextField("Ví dụ: đi xe máy từ Cầu Giấy đến Hồ Tây, tránh cao tốc", text: $input, axis: .vertical)
                    .focused($inputFocused)
                    .lineLimit(1...3)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppTheme.cardStroke, lineWidth: 1)
                            )
                    )
                    .submitLabel(.send)
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: model.aiThinking ? "hourglass" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            Circle().fill(input.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? AnyShapeStyle(Color.gray.opacity(0.4))
                                          : AnyShapeStyle(AppTheme.accentGradient))
                        )
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || model.aiThinking)
                .accessibilityLabel("Gửi câu lệnh cho AI")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private func planSummary(_ plan: RoutePlan) -> some View {
        HStack(spacing: 8) {
            Image(systemName: plan.mode.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            Text(planTitle(plan))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if !plan.waypoints.isEmpty {
                Text("\(plan.waypoints.count) điểm dừng")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppTheme.accent.opacity(0.14)))
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }

    private func planTitle(_ plan: RoutePlan) -> String {
        let from = plan.origin?.name ?? "vị trí hiện tại"
        return "\(plan.mode.shortTitle) · \(from) → \(plan.destination.name)"
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.aiThinking else { return }
        input = ""
        inputFocused = false
        Task { await model.askAI(text) }
    }
}

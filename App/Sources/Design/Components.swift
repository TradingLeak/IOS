import SwiftUI
import UIKit

// MARK: - Nút tròn nổi (dùng cho locate / layers / zoom)

struct FloatingIconButton: View {
    let symbol: String
    var active: Bool = false
    var badge: String? = nil
    var accessibilityLabel: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(active ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(AppTheme.card))
                    .overlay(Circle().stroke(AppTheme.cardStroke, lineWidth: 1))
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(active ? Color.white : Color.primary)
            }
            .frame(width: 46, height: 46)
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.danger))
                        .offset(x: 4, y: -4)
                }
            }
            .softShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Nút chính

struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .primaryGradientBackground(cornerRadius: 16)
            .opacity(isEnabled && !isLoading ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chip lọc / danh mục

struct FilterChip: View {
    let title: String
    var symbol: String? = nil
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(AppTheme.card))
                    .overlay(Capsule().stroke(AppTheme.cardStroke, lineWidth: 1))
            )
            .softShadow()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Khối nội dung có tiêu đề

struct SectionCard<Content: View>: View {
    var title: String?
    var symbol: String?
    let content: Content

    init(title: String? = nil, symbol: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingCard()
    }
}

// MARK: - Ô nhập liệu kiểu "viên thuốc"

struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    var symbol: String = "magnifyingglass"
    var onSubmit: (() -> Void)? = nil
    var onClear: (() -> Void)? = nil
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .submitLabel(.search)
                .autocorrectionDisabled()
                .modifier(OptionalFocus(focus: focus))
                .onSubmit { onSubmit?() }
            if !text.isEmpty {
                Button {
                    text = ""
                    onClear?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AppTheme.subtleFill)
        )
    }
}

/// Chỉ gắn .focused() khi thực sự có FocusState được truyền vào.
private struct OptionalFocus: ViewModifier {
    var focus: FocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let focus {
            content.focused(focus)
        } else {
            content
        }
    }
}

// MARK: - Banner thông báo

struct InfoBanner: View {
    enum Kind { case info, success, warning, error }

    let kind: Kind
    let text: String

    private var color: Color {
        switch kind {
        case .info: return AppTheme.accent
        case .success: return AppTheme.success
        case .warning: return AppTheme.warning
        case .error: return AppTheme.danger
        }
    }

    private var symbol: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.12))
        )
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

// MARK: - Nút chọn chế độ di chuyển

struct TravelModePicker: View {
    @Binding var selection: TravelMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TravelMode.allCases) { mode in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selection = mode }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 14, weight: .semibold))
                        Text(mode.shortTitle)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selection == mode ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selection == mode
                                  ? AnyShapeStyle(AppTheme.accentGradient)
                                  : AnyShapeStyle(Color.clear))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AppTheme.subtleFill)
        )
    }
}

// MARK: - Ô số liệu nhỏ

struct StatTile: View {
    let value: String
    let label: String
    var symbol: String? = nil
    var tint: Color = AppTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Chia sẻ tệp (AirDrop / Lưu vào Files)

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

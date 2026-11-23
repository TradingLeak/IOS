import SwiftUI

// MARK: - Panel có tiêu đề

struct PulsePanelCard<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var tint: Color = PulseTheme.teal
    var trailing: AnyView? = nil
    private let content: () -> Content

    init(title: String,
         subtitle: String? = nil,
         symbol: String? = nil,
         tint: Color = PulseTheme.teal,
         trailing: AnyView? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        if let symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(tint)
                        }
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PulseTheme.textPrimary)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(PulseTheme.textSecondary)
                    }
                }
                Spacer()
                if let trailing {
                    trailing
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseCard()
    }
}

// MARK: - Nhãn trạng thái

struct PulseStatusPill: View {
    let text: String
    var color: Color = PulseTheme.success
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            }
            Text(text.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

// MARK: - Chip lọc

struct PulseFilterChip: View {
    let title: String
    var isSelected: Bool
    var tint: Color = PulseTheme.teal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.black : PulseTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.06)))
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : PulseTheme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Icon trong vòng tròn

struct PulseIconBadge: View {
    let symbol: String
    var tint: Color = PulseTheme.teal
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.14)))
    }
}

// MARK: - Trạng thái rỗng / lỗi / đang tải

struct PulseEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(PulseTheme.textTertiary)
                .frame(height: 38)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PulseTheme.textSecondary)
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(PulseTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

struct PulseErrorState: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(PulseTheme.warning)
            Text("Không tải được dữ liệu")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PulseTheme.textPrimary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(PulseTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                PulsePrimaryButton(title: "Thử lại", action: retry)
                    .frame(width: 140)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct PulseLoading: View {
    var title: String = "Đang tải dữ liệu"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(PulseTheme.teal)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(PulseTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Nút

struct PulsePrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var isLoading: Bool = false
    var isEnabled: Bool = true
    var tint: Color = PulseTheme.teal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.black)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(tint)
            )
            .opacity(isEnabled && !isLoading ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

struct PulseSecondaryButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = PulseTheme.teal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(tint.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tiêu đề mục

struct PulseSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(PulseTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(PulseTheme.textSecondary)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

// MARK: - Toast (cảnh báo giá kích hoạt)

struct PulseToastView: View {
    let title: String
    let message: String
    var tint: Color = PulseTheme.teal
    var symbol: String = "bell.badge.fill"
    var onTap: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            PulseIconBadge(symbol: symbol, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PulseTheme.textPrimary)
                    .lineLimit(1)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(PulseTheme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PulseTheme.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PulseTheme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tint.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Ô nhập liệu

struct PulseFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 14))
            .foregroundStyle(PulseTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(PulseTheme.stroke, lineWidth: 1)
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}

extension View {
    func pulseField() -> some View {
        modifier(PulseFieldStyle())
    }
}

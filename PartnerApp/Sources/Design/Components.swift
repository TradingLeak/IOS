import SwiftUI

// MARK: - Thẻ KPI (số lớn)

struct KpiCard: View {
    let title: String
    let value: String
    var caption: String? = nil
    var symbol: String = "chart.bar.fill"
    var tint: Color = PartnerTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(tint.opacity(0.14)))
                Spacer()
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PartnerTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PartnerTheme.textSecondary)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PartnerTheme.textTertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(PartnerTheme.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PartnerTheme.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Panel có tiêu đề

struct PanelCard<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var trailing: AnyView? = nil
    private let content: () -> Content

    init(title: String,
         subtitle: String? = nil,
         symbol: String? = nil,
         trailing: AnyView? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(PartnerTheme.accent)
                        }
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PartnerTheme.textPrimary)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(PartnerTheme.textSecondary)
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
        .partnerCard()
    }
}

// MARK: - Nhãn trạng thái

struct StatusPill: View {
    let text: String
    var color: Color = PartnerTheme.success

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

// MARK: - Trạng thái rỗng / lỗi / đang tải

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(PartnerTheme.textTertiary)
                .frame(height: 38)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PartnerTheme.textSecondary)
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(PartnerTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(PartnerTheme.warning)
            Text("Không tải được dữ liệu")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PartnerTheme.textPrimary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(PartnerTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button(action: retry) {
                    Text("Thử lại")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(PartnerTheme.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct LoadingCard: View {
    var title: String = "Đang tải dữ liệu"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(PartnerTheme.accent)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(PartnerTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Nút chính

struct PrimaryActionButton: View {
    let title: String
    var symbol: String? = nil
    var isLoading: Bool = false
    var isEnabled: Bool = true
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
                    .fill(PartnerTheme.accent)
            )
            .opacity(isEnabled && !isLoading ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

struct SecondaryActionButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = PartnerTheme.accent
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

// MARK: - Nhãn nhỏ (badge)

struct MiniBadge: View {
    let text: String
    var tint: Color = PartnerTheme.success

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint.opacity(0.12)))
    }
}

// MARK: - Đường phân cách

struct PartnerDivider: View {
    var body: some View {
        Divider().overlay(PartnerTheme.stroke)
    }
}

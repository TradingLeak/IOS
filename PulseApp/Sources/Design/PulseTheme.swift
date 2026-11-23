import SwiftUI

/// Bảng màu của Pulse — tối kiểu "trading terminal", điểm nhấn gradient
/// teal → tím, không phụ thuộc chế độ sáng/tối của hệ thống.
enum PulseTheme {
    // Nền & bề mặt
    static let background = Color(red: 0.035, green: 0.040, blue: 0.070)
    static let surface = Color(red: 0.070, green: 0.080, blue: 0.120)
    static let surfaceRaised = Color(red: 0.110, green: 0.120, blue: 0.180)
    static let stroke = Color.white.opacity(0.08)
    static let strokeStrong = Color.white.opacity(0.16)

    // Điểm nhấn
    static let teal = Color(red: 0.20, green: 0.88, blue: 0.78)
    static let violet = Color(red: 0.55, green: 0.48, blue: 1.0)
    static let accent = teal
    static let accentSoft = teal.opacity(0.14)
    /// Màu vàng Exness dành riêng cho phần đối tác.
    static let gold = Color(red: 1.0, green: 0.831, blue: 0.0)
    static let goldSoft = gold.opacity(0.14)

    // Trạng thái
    static let success = Color(red: 0.20, green: 0.82, blue: 0.51)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.38)
    static let warning = Color(red: 1.0, green: 0.66, blue: 0.22)
    static let info = Color(red: 0.35, green: 0.66, blue: 1.0)

    // Chữ
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.40)

    // Kích thước
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14

    static let brandGradient = LinearGradient(
        colors: [teal, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.20, blue: 0.22),
            Color(red: 0.14, green: 0.10, blue: 0.30),
            Color(red: 0.04, green: 0.05, blue: 0.09)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let dangerGradient = LinearGradient(
        colors: [danger, danger.opacity(0.6)],
        startPoint: .top, endPoint: .bottom
    )

    /// Màu theo mức ảnh hưởng của sự kiện kinh tế.
    static func impactColor(_ impact: EventImpact) -> Color {
        switch impact {
        case .high: return danger
        case .medium: return warning
        case .low: return info
        case .holiday: return violet
        }
    }

    /// Màu theo nhóm mã.
    static func categoryTint(_ category: SymbolCategory) -> Color {
        switch category {
        case .forex: return info
        case .metals: return warning
        case .crypto: return violet
        case .energy: return Color(red: 1.0, green: 0.52, blue: 0.30)
        case .other: return teal
        }
    }

    /// Màu theo hướng biến động.
    static func changeColor(_ value: Double) -> Color {
        if value > 0 { return success }
        if value < 0 { return danger }
        return textSecondary
    }
}

extension View {
    /// Thẻ tối có viền mảnh.
    func pulseCard(radius: CGFloat = PulseTheme.cardRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(PulseTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(PulseTheme.stroke, lineWidth: 1)
                )
        )
    }

    /// Nền màn hình: đen navy + hai vệt sáng rất nhẹ ở góc.
    func pulseScreenBackground() -> some View {
        background(
            ZStack {
                PulseTheme.background
                RadialGradient(
                    colors: [PulseTheme.teal.opacity(0.10), .clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 460
                )
                RadialGradient(
                    colors: [PulseTheme.violet.opacity(0.14), .clear],
                    center: .bottomTrailing,
                    startRadius: 10,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        )
    }

    /// Hiệu ứng "kính" cho các panel nổi (gradient rất nhẹ phía trên).
    func pulseGlass() -> some View {
        background(
            RoundedRectangle(cornerRadius: PulseTheme.cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .background(PulseTheme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: PulseTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PulseTheme.cardRadius, style: .continuous)
                        .stroke(PulseTheme.strokeStrong, lineWidth: 1)
                )
        )
    }
}

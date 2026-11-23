import SwiftUI

/// Bảng màu của PartnerHub — giao diện tối kiểu "finance dashboard",
/// điểm nhấn vàng Exness, không phụ thuộc chế độ sáng/tối của hệ thống.
enum PartnerTheme {
    // Nền & bề mặt
    static let background = Color(red: 0.027, green: 0.031, blue: 0.043)
    static let surface = Color(red: 0.059, green: 0.067, blue: 0.082)
    static let surfaceRaised = Color(red: 0.086, green: 0.098, blue: 0.118)
    static let stroke = Color.white.opacity(0.08)
    static let strokeStrong = Color.white.opacity(0.14)

    // Điểm nhấn
    static let accent = Color(red: 1.0, green: 0.831, blue: 0.0)
    static let accentDeep = Color(red: 0.85, green: 0.62, blue: 0.0)
    static let accentSoft = accent.opacity(0.14)

    // Trạng thái
    static let success = Color(red: 0.20, green: 0.82, blue: 0.51)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.38)
    static let warning = Color(red: 1.0, green: 0.66, blue: 0.22)
    static let info = Color(red: 0.35, green: 0.66, blue: 1.0)

    // Chữ
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.60)
    static let textTertiary = Color.white.opacity(0.38)

    // Kích thước
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14

    static let accentGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.14, green: 0.12, blue: 0.03),
            Color(red: 0.05, green: 0.055, blue: 0.065)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let blueGradient = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.16, blue: 0.26),
            Color(red: 0.04, green: 0.055, blue: 0.075)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    /// Thẻ tối có viền mảnh.
    func partnerCard(radius: CGFloat = PartnerTheme.cardRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(PartnerTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(PartnerTheme.stroke, lineWidth: 1)
                )
        )
    }

    /// Nền màn hình: đen + hai vệt sáng rất nhẹ ở góc.
    func partnerScreenBackground() -> some View {
        background(
            ZStack {
                PartnerTheme.background
                RadialGradient(
                    colors: [PartnerTheme.accent.opacity(0.09), .clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 420
                )
                RadialGradient(
                    colors: [Color(red: 0.18, green: 0.55, blue: 1.0).opacity(0.08), .clear],
                    center: .bottomLeading,
                    startRadius: 10,
                    endRadius: 380
                )
            }
            .ignoresSafeArea()
        )
    }
}

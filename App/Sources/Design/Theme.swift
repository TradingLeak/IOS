import SwiftUI
import UIKit

/// Bộ màu / kích thước dùng chung cho toàn app.
/// Tự thích ứng sáng–tối, không hardcode màu trong từng view.
enum AppTheme {
    static let accent = Color(red: 0.16, green: 0.47, blue: 0.98)
    static let accentDeep = Color(red: 0.47, green: 0.25, blue: 0.95)
    static let cyan = Color(red: 0.18, green: 0.78, blue: 0.93)
    static let success = Color(red: 0.09, green: 0.68, blue: 0.45)
    static let warning = Color(red: 0.95, green: 0.60, blue: 0.08)
    static let danger = Color(red: 0.90, green: 0.25, blue: 0.28)

    static let accentGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let routeGradient = LinearGradient(
        colors: [Color(red: 0.10, green: 0.55, blue: 1.00), Color(red: 0.42, green: 0.24, blue: 0.98)],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Gradient nhấn cho cảnh báo.
    static let alertGradient = LinearGradient(
        colors: [Color(red: 0.95, green: 0.36, blue: 0.18), Color(red: 0.86, green: 0.12, blue: 0.30)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Nền của các "card nổi" trên bản đồ.
    static let card = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 0.96)
            : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.96)
    })

    static let cardStroke = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.10)
            : UIColor(white: 0.0, alpha: 0.06)
    })

    static let subtleFill = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.07)
            : UIColor(white: 0.0, alpha: 0.05)
    })

    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 16
}

extension View {
    /// Nền card + viền mảnh + bóng đổ mềm (phong cách OsmAnd/Organic Maps).
    func floatingCard(cornerRadius: CGFloat = AppTheme.cardRadius) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 8)
    }

    func softShadow() -> some View {
        shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 4)
    }

    /// Card "kính mờ" hiện đại (iOS 15+): vật liệu mờ + viền sáng mảnh.
    func glassCard(cornerRadius: CGFloat = AppTheme.cardRadius) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.04)],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    /// Nền gradient cho các nút chính.
    func primaryGradientBackground(cornerRadius: CGFloat = 16) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.accentGradient)
        )
        .shadow(color: AppTheme.accent.opacity(0.35), radius: 12, x: 0, y: 6)
    }
}

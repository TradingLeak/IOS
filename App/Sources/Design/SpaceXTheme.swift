import SwiftUI
import UIKit

// MARK: - Design system "SpaceX / Orbital" cho layer HUD & chỉ đường
//
// Bổ sung cho AppTheme hiện có (không thay đổi): dark-first, đơn sắc +
// màu tín hiệu, viền hairline, số mono, glow nhẹ. Dùng cho SpeedHudOverlay,
// NavigationHUD (P1) và các màn hình phong cách tương lai sau này.

enum SpaceXTheme {
    // MARK: Màu
    static let void = Color.black
    static let panel = Color.black.opacity(0.78)
    static let panelSolid = Color(red: 0.04, green: 0.05, blue: 0.07)
    static let hairline = Color.white.opacity(0.14)
    static let ink = Color.white
    static let inkDim = Color.white.opacity(0.60)

    static let signalRed = Color(red: 1.00, green: 0.23, blue: 0.19)    // camera, cấm vượt
    static let signalAmber = Color(red: 1.00, green: 0.62, blue: 0.04)  // giới hạn đổi, thu phí
    static let iceBlue = Color(red: 0.55, green: 0.78, blue: 1.00)      // khu dân cư, đèn
    static let traceGreen = Color(red: 0.20, green: 0.84, blue: 0.29)   // OK / đã tải
    static let dimRed = Color(red: 1.00, green: 0.23, blue: 0.19).opacity(0.30)

    // MARK: Chữ
    static func digits(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // MARK: Motion
    static let quick = Animation.easeOut(duration: 0.22)
    static let settle = Animation.easeOut(duration: 0.30)
}

// MARK: - Modifier HUD

extension View {
    /// Panel kính mờ viền hairline — nền của mọi khối HUD.
    func hudPanel(cornerRadius: CGFloat = 14) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(SpaceXTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(SpaceXTheme.hairline, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
    }

    /// Phát sáng dịu theo màu tín hiệu (viền ngoài cùng màu).
    func signalGlow(_ color: Color, radius: CGFloat = 8, opacity: Double = 0.55) -> some View {
        shadow(color: color.opacity(opacity), radius: radius)
    }
}

// MARK: - Biển báo giới hạn tốc độ (chuẩn giao thông, đối lập tối màu)

/// Vòng tròn trắng + viền đỏ + số đen — drawable duy nhất "chói" trên HUD.
struct SpeedLimitSign: View {
    let limitKmh: Int
    var diameter: CGFloat = 54

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
            Circle()
                .strokeBorder(Color(red: 0.85, green: 0.09, blue: 0.09),
                              lineWidth: max(4, diameter * 0.09))
                .padding(max(4, diameter * 0.09))
            VStack(spacing: 0) {
                Text("\(limitKmh)")
                    .font(SpaceXTheme.digits(diameter * 0.44, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text("km/h")
                    .font(.system(size: diameter * 0.16, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .offset(y: -diameter * 0.03)
            }
            .padding(.bottom, diameter * 0.02)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("Biển giới hạn tốc độ \(limitKmh) ki lô mét mỗi giờ")
    }
}

// MARK: - Đồng hồ tốc độ hiện tại (mono, glow theo vùng vượt giới hạn)

struct SpeedReadout: View {
    let speedKmh: Double
    let limitKmh: Int?

    private var overLimit: Bool {
        guard let limitKmh else { return false }
        return speedKmh > Double(limitKmh)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("\(Int(speedKmh.rounded()))")
                .font(SpaceXTheme.digits(24, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(overLimit ? SpaceXTheme.signalRed : SpaceXTheme.ink)
            Text("km/h")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SpaceXTheme.inkDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .hudPanel(cornerRadius: 12)
        .signalGlow(overLimit ? SpaceXTheme.signalRed : SpaceXTheme.iceBlue, radius: 7, opacity: overLimit ? 0.7 : 0.25)
        .accessibilityLabel("Tốc độ \(Int(speedKmh.rounded())) ki lô mét mỗi giờ")
    }
}

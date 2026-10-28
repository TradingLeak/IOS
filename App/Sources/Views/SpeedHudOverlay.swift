import SwiftUI

// MARK: - SpeedHudOverlay
//
// Layer cảnh báo trực tiếp trên màn hình bản đồ: card camera/biển báo
// (khoảng cách đếm ngược) + hàng biển giới hạn tốc độ & đồng hồ tốc độ.
// Vị trí: dưới header/chips trong VStack của MapScreen — không che bottom panel.

struct SpeedHudOverlay: View {
    @ObservedObject var controller: SpeedmapController

    var body: some View {
        VStack(spacing: 8) {
            ForEach(controller.alerts) { alert in
                alertCard(alert)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity))
            }

            if controller.speedKmh != nil || controller.speedLimitKmh != nil {
                statusRow
            }
        }
        .animation(SpaceXTheme.quick, value: controller.alerts)
    }

    // MARK: Card cảnh báo

    private func alertCard(_ alert: HazardAlert) -> some View {
        let color = alertColor(alert.kind)
        return HStack(spacing: 11) {
            Image(systemName: alertSymbol(alert.kind))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(color))
                .signalGlow(color, radius: 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(alert.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SpaceXTheme.ink)
                    .lineLimit(1)
                if let subtitle = alert.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SpaceXTheme.inkDim)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(distanceText(alert.distanceM))
                .font(SpaceXTheme.digits(19, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(SpaceXTheme.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 360, alignment: .leading)
        .hudPanel(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.55), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alert.title), \(Int(alert.distanceM.rounded())) mét")
    }

    // MARK: Biển giới hạn + tốc độ

    private var statusRow: some View {
        HStack(spacing: 10) {
            if let limit = controller.speedLimitKmh {
                SpeedLimitSign(limitKmh: limit, diameter: 50)
            }
            if let speed = controller.speedKmh {
                SpeedReadout(speedKmh: speed, limitKmh: controller.speedLimitKmh)
            }
            if let name = controller.road?.name, !name.isEmpty {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SpaceXTheme.inkDim)
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    // MARK: Map kind → màu / icon

    private func alertColor(_ kind: HazardAlert.Kind) -> Color {
        switch kind {
        case .camera, .noOvertaking:
            return SpaceXTheme.signalRed
        case .speedLimitChange, .speedLimitSign, .tollBooth:
            return SpaceXTheme.signalAmber
        case .residentArea, .trafficLight:
            return SpaceXTheme.iceBlue
        case .danger:
            return Color.white.opacity(0.75)
        }
    }

    private func alertSymbol(_ kind: HazardAlert.Kind) -> String {
        switch kind {
        case .camera: return "video.fill"
        case .speedLimitChange, .speedLimitSign: return "speedometer"
        case .residentArea: return "house.fill"
        case .noOvertaking: return "arrow.up.circle.fill"
        case .tollBooth: return "creditcard.fill"
        case .trafficLight: return "lightbulb.max.fill"
        case .danger: return "exclamationmark.triangle.fill"
        }
    }

    private func distanceText(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }
}

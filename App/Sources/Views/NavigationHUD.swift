import SwiftUI

/// Đồng hồ tốc độ dạng vòng cung kiểu VietMap: số km/h ở giữa, cung chạy theo tốc độ,
/// chuyển đỏ khi vượt giới hạn.
struct SpeedGauge: View {
    let speed: Double
    let limit: Int?
    let overLimit: Bool
    var size: CGFloat = 62

    private var fraction: Double {
        let ceiling = Double(max(30, (limit ?? 50) + 20))
        return min(1, max(0, speed / ceiling))
    }

    private var tint: Color {
        overLimit ? AppTheme.danger : AppTheme.accent
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.cardStroke, lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: fraction)

            VStack(spacing: -2) {
                Text("\(Int(speed.rounded()))")
                    .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(overLimit ? AppTheme.danger : Color.primary)
                    .contentTransition(.numericText())
                Text("km/h")
                    .font(.system(size: size * 0.15, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tốc độ \(Int(speed.rounded())) km/h")
    }
}

/// Thanh tiến trình mảnh (tới chỗ rẽ / tới cảnh báo).
struct ProgressStripe: View {
    /// 1 = còn xa, 0 = đã tới nơi.
    let fraction: Double
    let tint: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16))
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

/// Dải gợi ý làn đường: các làn vẽ cạnh nhau, làn cần đi được tô sáng.
struct LaneStrip: View {
    let guidance: LaneGuidance

    var body: some View {
        HStack(spacing: 10) {
            Text("LÀN ĐƯỜNG")
                .font(.system(size: 9.5, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .fixedSize()

            HStack(spacing: 5) {
                ForEach(0..<guidance.laneCount, id: \.self) { index in
                    let active = guidance.highlighted.contains(index)
                    Image(systemName: guidance.symbol(forLane: index))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(active ? Color.white : Color.secondary)
                        .frame(width: 28, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(active ? AnyShapeStyle(AppTheme.accentGradient)
                                             : AnyShapeStyle(AppTheme.subtleFill))
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Text(guidance.caption)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .floatingCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gợi ý làn: \(guidance.caption)")
    }
}

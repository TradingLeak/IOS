import SwiftUI

/// Biểu đồ cột tối giản, không dùng thư viện ngoài.
struct BarChartView: View {
    let points: [ChartPoint]
    var tint: Color = PartnerTheme.accent

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(points.map(\.value).max() ?? 0, 0.000001)
            let count = max(points.count, 1)
            let spacing: CGFloat = points.count > 14 ? 4 : 8
            let barWidth = max((proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 3)
            let plotHeight = max(proxy.size.height - 34, 20)
            let showValues = points.count <= 8

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(points) { point in
                    VStack(spacing: 5) {
                        Group {
                            if showValues {
                                Text(point.value > 0 ? Fmt.compactUSD(point.value) : "")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(PartnerTheme.textTertiary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(height: 10)

                        RoundedRectangle(cornerRadius: min(4, barWidth / 2), style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint, tint.opacity(0.55)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: barWidth,
                                   height: max(4, plotHeight * CGFloat(point.value / maxValue)))

                        Text(point.label)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(PartnerTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: barWidth)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 172)
        .accessibilityLabel("Biểu đồ hoa hồng")
    }
}

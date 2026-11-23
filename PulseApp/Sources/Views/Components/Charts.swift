import SwiftUI

// MARK: - Sparkline (đường mini cho danh sách theo dõi)

struct SparklineView: View {
    let values: [Double]
    var tint: Color = PulseTheme.teal
    var lineWidth: CGFloat = 1.8

    var body: some View {
        GeometryReader { geometry in
            let points = Self.points(values: values, size: geometry.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.addLines(points)
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                        path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.32), .clear],
                                         startPoint: .top, endPoint: .bottom))

                    Path { path in
                        path.addLines(points)
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    static func points(values: [Double], size: CGSize) -> [CGPoint] {
        guard values.count > 1, let minValue = values.min(), let maxValue = values.max() else { return [] }
        let range = max(maxValue - minValue, .leastNonzeroMagnitude)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let ratio = (value - minValue) / range
            return CGPoint(x: CGFloat(index) * stepX, y: 2 + (1 - ratio) * max(size.height - 4, 1))
        }
    }
}

// MARK: - Điểm nến có sẵn ngày (đã parse từ chuỗi ISO của API)

struct CandlePoint: Identifiable, Equatable {
    let id: Int
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double

    init(id: Int, candle: Candle) {
        self.id = id
        self.date = Fmt.parseDate(candle.time) ?? Date(timeIntervalSince1970: 0)
        self.open = candle.open
        self.high = candle.high
        self.low = candle.low
        self.close = candle.close
    }

    var isUp: Bool { close >= open }
    var change: Double { close - open }
    var changePercent: Double { self.open > 0 ? (close - open) / open * 100 : 0 }
}

/// Toạ độ nến trong khung biểu đồ.
struct CandleLayout {
    let count: Int
    let step: CGFloat
    let bodyWidth: CGFloat
    let low: Double
    let high: Double
    let size: CGSize
    let topInset: CGFloat = 10
    let bottomInset: CGFloat = 26

    static func make(count: Int, candles: [CandlePoint], size: CGSize) -> CandleLayout {
        let lows = candles.map(\.low).min() ?? 0
        let highs = candles.map(\.high).max() ?? 1
        let padding = max((highs - lows) * 0.06, (highs != lows ? 0 : 1) * 0.01)
        let step = count > 0 ? size.width / CGFloat(count) : 0
        return CandleLayout(count: count,
                            step: step,
                            bodyWidth: max(step * 0.62, 1),
                            low: lows - padding,
                            high: highs + padding,
                            size: size)
    }

    func x(_ index: Int) -> CGFloat {
        step * (CGFloat(index) + 0.5)
    }

    func y(_ price: Double) -> CGFloat {
        let range = max(high - low, .leastNonzeroMagnitude)
        let ratio = (price - low) / range
        return topInset + (1 - ratio) * max(size.height - topInset - bottomInset, 1)
    }

    func index(at x: CGFloat) -> Int? {
        guard step > 0, count > 0 else { return nil }
        let computed = Int(x / step)
        return (0..<count).contains(computed) ? computed : nil
    }
}

// MARK: - Biểu đồ nến (vẽ tay, không phụ thuộc thư viện)

struct CandleChartView: View {
    let candles: [CandlePoint]
    var upColor: Color = PulseTheme.success
    var downColor: Color = PulseTheme.danger
    var digits: Int = 2
    @Binding var focus: Int?

    private let gridLines = 4

    var body: some View {
        GeometryReader { geometry in
            let layout = CandleLayout.make(count: candles.count, candles: candles, size: geometry.size)
            ZStack(alignment: .topLeading) {
                grid(layout: layout)

                ForEach(Array(candles.enumerated()), id: \.element.id) { index, candle in
                    candleShape(candle, at: index, layout: layout)
                }

                if let last = candles.last {
                    lastPriceLine(last, layout: layout)
                }

                if let focus, candles.indices.contains(focus) {
                    focusLine(candles[focus], at: focus, layout: layout)
                }

                timeAxis(layout: layout)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        focus = layout.index(at: value.location.x)
                    }
                    .onEnded { _ in }
            )
        }
        .aspectRatio(1.45, contentMode: .fit)
    }

    // MARK: Grid + trục giá

    private func grid(layout: CandleLayout) -> some View {
        ForEach(0...gridLines, id: \.self) { line in
            let fraction = CGFloat(line) / CGFloat(gridLines)
            let y = layout.topInset + fraction * max(layout.size.height - layout.topInset - layout.bottomInset, 0)
            let price = layout.high - Double(fraction) * (layout.high - layout.low)
            ZStack(alignment: .trailing) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: layout.size.width, y: y))
                }
                .stroke(Color.white.opacity(0.06), lineWidth: 1)

                Text(PulseFormat.price(price, digits: digits))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(PulseTheme.textTertiary)
                    .padding(.leading, 4)
                    .background(Color(red: 0.035, green: 0.040, blue: 0.070).opacity(0.85))
                    .offset(x: -2)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func timeAxis(layout: CandleLayout) -> some View {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = candles.last.map { Date().timeIntervalSince($0.date) > 172_800 ? "dd/MM" : "HH:mm" } ?? "HH:mm"
        let labels = 4
        return ForEach(0..<labels, id: \.self) { label in
            let index = Int(CGFloat(candles.count - 1) * CGFloat(label) / CGFloat(max(labels - 1, 1)))
            if candles.indices.contains(index) {
                Text(formatter.string(from: candles[index].date))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(PulseTheme.textTertiary)
                    .position(x: layout.x(index), y: layout.size.height - 10)
            }
        }
    }

    // MARK: Nến

    @ViewBuilder
    private func candleShape(_ candle: CandlePoint, at index: Int, layout: CandleLayout) -> some View {
        let x = layout.x(index)
        let color = candle.isUp ? upColor : downColor
        let topY = layout.y(max(candle.open, candle.close))
        let bottomY = layout.y(min(candle.open, candle.close))
        let bodyHeight = max(bottomY - topY, 1.5)
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: x, y: layout.y(candle.high)))
                path.addLine(to: CGPoint(x: x, y: layout.y(candle.low)))
            }
            .stroke(color.opacity(0.9), lineWidth: 1)

            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: layout.bodyWidth, height: bodyHeight)
                .position(x: x, y: (topY + bottomY) / 2)
        }
    }

    private func lastPriceLine(_ candle: CandlePoint, layout: CandleLayout) -> some View {
        let y = layout.y(candle.close)
        let color = candle.isUp ? upColor : downColor
        return ZStack(alignment: .trailing) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: layout.size.width, y: y))
            }
            .stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            Text(PulseFormat.price(candle.close, digits: digits))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(color))
                .offset(x: -2)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func focusLine(_ candle: CandlePoint, at index: Int, layout: CandleLayout) -> some View {
        let x = layout.x(index)
        Path { path in
            path.move(to: CGPoint(x: x, y: layout.topInset))
            path.addLine(to: CGPoint(x: x, y: layout.size.height - layout.bottomInset))
        }
        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }
}

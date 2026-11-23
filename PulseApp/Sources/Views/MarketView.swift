import SwiftUI

struct MarketView: View {
    @EnvironmentObject var store: PulseStore
    @State private var focus: Int?
    @State private var showPicker = false
    @State private var showAlertEditor = false
    @State private var showSettings = false

    private var digits: Int { PulseSymbol.digits(for: store.selectedSymbol) }
    private var category: SymbolCategory { PulseSymbol.category(for: store.selectedSymbol) }
    private var points: [CandlePoint] {
        store.candles.enumerated().map { CandlePoint(id: $0.offset, candle: $0.element) }
    }
    private var currentQuote: Quote? { store.quotes[store.selectedSymbol] }
    private var lastClose: Double? { points.last?.close }
    private var displayPrice: Double? { currentQuote?.mid ?? lastClose }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !store.isTradingConfigured {
                        notConfiguredCard
                    } else {
                        symbolHeader
                        chartCard
                        timeframePicker
                        watchlistCard
                        alertsForSymbol
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(PulseTheme.background)
            .navigationTitle("Giá")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet")
                            Text("Mã")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PulseTheme.teal)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showAlertEditor = true
                    } label: {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(PulseTheme.warning)
                    }
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(PulseTheme.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                SymbolPickerView(instruments: store.instruments,
                                 watchlist: $store.watchlist) { symbol in
                    store.selectedSymbol = symbol
                    store.addToWatchlist(symbol)
                    showPicker = false
                }
                .environmentObject(store)
                .onChange(of: store.watchlist) { _ in store.watchlistChanged() }
            }
            .sheet(isPresented: $showAlertEditor) {
                AlertEditorView(symbol: store.selectedSymbol, currentPrice: displayPrice)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .task(id: "\(store.selectedSymbol)|\(store.timeframe.rawValue)") {
                if store.isTradingConfigured {
                    await store.loadCandles()
                }
            }
            .refreshable {
                await store.loadCandles()
            }
        }
    }

    // MARK: - Header mã

    private var symbolHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            PulseIconBadge(symbol: category.symbol, tint: PulseTheme.categoryTint(category), size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(PulseSymbol.displayName(store.selectedSymbol))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(PulseTheme.textPrimary)
                    PulseStatusPill(text: category.title, color: PulseTheme.categoryTint(category))
                }
                HStack(spacing: 10) {
                    Text("Bid " + (currentQuote.map { PulseFormat.price($0.bid, digits: digits) } ?? "—"))
                    Text("Ask " + (currentQuote.map { PulseFormat.price($0.ask, digits: digits) } ?? "—"))
                    if let quote = currentQuote {
                        Text("Spread " + PulseFormat.price(quote.spread, digits: digits))
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(PulseTheme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(displayPrice.map { PulseFormat.price($0, digits: digits) } ?? "—")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(PulseTheme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: displayPrice)
                if let change = sessionChange {
                    Text(PulseFormat.signedPrice(change, digits: 2) + "%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PulseTheme.changeColor(change))
                }
            }
        }
        .padding(16)
        .pulseGlass()
    }

    private var sessionChange: Double? {
        guard let first = points.first?.open, let last = displayPrice, first > 0 else { return nil }
        return (last - first) / first * 100
    }

    // MARK: - Biểu đồ

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(store.timeframe.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PulseTheme.textSecondary)
                Text("· Nến Exness" + (focus != nil ? " · chạm để tra" : " · vuốt để tra OHLC"))
                    .font(.system(size: 11))
                    .foregroundStyle(PulseTheme.textTertiary)
                Spacer()
                PulseStatusPill(text: store.streamStatus.title,
                                color: store.streamStatus.isActive ? PulseTheme.success : PulseTheme.warning)
            }

            if store.isLoadingCandles && points.isEmpty {
                PulseLoading(title: "Đang tải nến giá")
                    .frame(height: 240)
            } else if let error = store.candleError, points.isEmpty {
                PulseErrorState(message: error) {
                    Task { await store.loadCandles() }
                }
                .frame(height: 240)
            } else if points.isEmpty {
                PulseEmptyState(symbol: "chart.bar",
                                title: "Chưa có dữ liệu nến",
                                message: "Thị trường có thể đang đóng cửa hoặc mã không có trên tài khoản.")
                    .frame(height: 240)
            } else {
                let focused = focus.flatMap { points.indices.contains($0) ? points[$0] : nil } ?? points[points.count - 1]
                ohlcRow(focused)
                CandleChartView(candles: points,
                                digits: min(digits, 5),
                                focus: $focus)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .pulseCard()
    }

    private func ohlcRow(_ candle: CandlePoint) -> some View {
        HStack(spacing: 12) {
            ohlcItem("O", candle.open)
            ohlcItem("H", candle.high)
            ohlcItem("L", candle.low)
            ohlcItem("C", candle.close)
            Spacer()
            Text(PulseFormat.signedPrice(candle.changePercent, digits: 2) + "%")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(PulseTheme.changeColor(candle.change))
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func ohlcItem(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(PulseTheme.textTertiary)
            Text(PulseFormat.price(value, digits: digits)).foregroundStyle(PulseTheme.textSecondary)
        }
    }

    // MARK: - Khung thời gian

    private var timeframePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Timeframe.allCases) { timeframe in
                    PulseFilterChip(title: timeframe.title,
                                    isSelected: store.timeframe == timeframe,
                                    tint: PulseTheme.teal) {
                        store.timeframe = timeframe
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Danh sách theo dõi

    private var watchlistCard: some View {
        PulsePanelCard(title: "Danh sách theo dõi",
                       subtitle: "Chạm để mở biểu đồ",
                       symbol: "star.fill",
                       tint: PulseTheme.teal) {
            VStack(spacing: 6) {
                ForEach(store.streamSymbols, id: \.self) { symbol in
                    QuoteRowView(symbol: symbol,
                                 quote: store.quotes[symbol],
                                 change: store.sessionChanges[symbol],
                                 sparkline: store.sparklines[symbol] ?? []) {
                        store.selectedSymbol = symbol
                    }
                }
                if store.streamSymbols.isEmpty {
                    PulseEmptyState(symbol: "star",
                                    title: "Danh sách trống",
                                    message: "Nhấn “Mã” để thêm mã cần theo dõi.")
                }
            }
        }
    }

    // MARK: - Cảnh báo của mã

    private var alertsForSymbol: some View {
        let list = store.alerts.filter { $0.symbol == store.selectedSymbol }
        return PulsePanelCard(title: "Cảnh báo cho " + PulseSymbol.displayName(store.selectedSymbol),
                              subtitle: list.isEmpty ? "Chưa có" : "\(list.filter { $0.enabled }.count) đang bật",
                              symbol: "bell.badge.fill",
                              tint: PulseTheme.warning,
                              trailing: AnyView(
                                  Button {
                                      showAlertEditor = true
                                  } label: {
                                      Image(systemName: "plus.circle.fill").foregroundStyle(PulseTheme.warning)
                                  }
                                  .buttonStyle(.plain)
                              )) {
            if list.isEmpty {
                Text("Tạo cảnh báo khi giá vượt lên, rơi xuống hoặc chạm một mức.")
                    .font(.system(size: 12))
                    .foregroundStyle(PulseTheme.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(list) { alert in
                        AlertRowView(alert: alert,
                                     currentPrice: displayPrice,
                                     onToggle: { store.toggleAlert(alert) },
                                     onDelete: { store.deleteAlert(alert) })
                    }
                }
            }
        }
    }

    // MARK: - Chưa cấu hình

    private var notConfiguredCard: some View {
        VStack(spacing: 14) {
            PulseIconBadge(symbol: "lock.fill", tint: PulseTheme.violet, size: 52)
            Text("Cần Trader API để xem giá")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(PulseTheme.textPrimary)
            Text("Nhập API key (scope Trading), host gateway và account ID trong Cài đặt. App sẽ phát hiện access point và mở WebSocket ticks.")
                .font(.system(size: 13))
                .foregroundStyle(PulseTheme.textSecondary)
                .multilineTextAlignment(.center)
            PulsePrimaryButton(title: "Mở Cài đặt", symbol: "key.fill", tint: PulseTheme.violet) {
                showSettings = true
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .pulseGlass()
    }
}

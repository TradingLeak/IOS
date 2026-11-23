import SwiftUI

/// Tạo cảnh báo giá mới cho một mã.
struct AlertEditorView: View {
    @EnvironmentObject var store: PulseStore
    @Environment(\.dismiss) private var dismiss

    let currentPrice: Double?
    @State private var selectedSymbol: String
    @State private var condition: PriceAlert.Condition = .price
    @State private var direction: PriceAlert.Direction = .cross
    @State private var targetText = ""
    @State private var note = ""
    @State private var showPicker = false
    @State private var errorMessage: String?

    init(symbol: String, currentPrice: Double?) {
        self.currentPrice = currentPrice
        _selectedSymbol = State(initialValue: symbol)
    }

    private var digits: Int { PulseSymbol.digits(for: selectedSymbol) }

    private var parsedTarget: Double? {
        Double(targetText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private var isValid: Bool {
        guard let value = parsedTarget else { return false }
        switch condition {
        case .price: return value > 0
        case .percentChange: return value > 0 && value <= 1_000
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mã") {
                    HStack {
                        PulseIconBadge(symbol: PulseSymbol.category(for: selectedSymbol).symbol,
                                       tint: PulseTheme.categoryTint(PulseSymbol.category(for: selectedSymbol)), size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PulseSymbol.displayName(selectedSymbol))
                                .font(.system(size: 15, weight: .bold))
                            if let currentPrice {
                                Text("Hiện " + PulseFormat.price(currentPrice, digits: digits))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(PulseTheme.textSecondary)
                            }
                        }
                        Spacer()
                        Button("Đổi") { showPicker = true }
                            .foregroundStyle(PulseTheme.teal)
                    }
                    .sheet(isPresented: $showPicker) {
                        SymbolPickerView(instruments: store.instruments.isEmpty ? [selectedSymbol] : store.instruments,
                                         watchlist: $store.watchlist) { symbol in
                            selectedSymbol = symbol
                            store.addToWatchlist(symbol)
                            showPicker = false
                        }
                        .onChange(of: store.watchlist) { _ in store.watchlistChanged() }
                    }
                }

                Section("Điều kiện") {
                    Picker("Loại", selection: $condition) {
                        ForEach(PriceAlert.Condition.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(condition.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(PulseTheme.textSecondary)

                    if condition == .price {
                        Picker("Hướng", selection: $direction) {
                            ForEach(PriceAlert.Direction.allCases) { item in
                                Label(item.title, systemImage: item.symbol).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack {
                        Text(condition == .price ? "Mức giá" : "Biên độ (%)")
                            .foregroundStyle(PulseTheme.textSecondary)
                        Spacer()
                        TextField(condition == .price ? "0.00" : "1.5", text: $targetText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PulseTheme.teal)
                            .frame(width: 140)
                    }
                    if condition == .price, let currentPrice {
                        Button("Dùng giá hiện tại") {
                            targetText = String(format: "%.\(digits)f", currentPrice)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(PulseTheme.teal)
                    }
                }

                Section("Ghi chú (tuỳ chọn)") {
                    TextField("vd: Vàng chạm đỉnh, chốt lời", text: $note)
                        .foregroundStyle(PulseTheme.textPrimary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(PulseTheme.danger)
                            .font(.system(size: 12))
                    }
                }

                Section {
                    PulsePrimaryButton(title: "Tạo cảnh báo", symbol: "bell.badge.fill", isEnabled: isValid) {
                        Task { await submit() }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Cảnh báo theo mức giá tự tắt sau khi kích hoạt. Cảnh báo theo % giữ bật, cách nhau tối thiểu 60 phút. Khi app không mở, iOS định kỳ đánh thức để kiểm tra (Background App Refresh).")
                        .font(.system(size: 11))
                        .foregroundStyle(PulseTheme.textTertiary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PulseTheme.background)
            .navigationTitle("Cảnh báo giá")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                        .foregroundStyle(PulseTheme.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() async {
        guard let value = parsedTarget else { return }
        if await AlertNotifier.shared.authorizationStatus() == .notDetermined {
            _ = await AlertNotifier.shared.requestAuthorization()
        }
        let alert = PriceAlert(symbol: selectedSymbol,
                               condition: condition,
                               direction: direction,
                               targetValue: value,
                               basePrice: currentPrice,
                               note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        store.addAlert(alert)
        dismiss()
    }
}

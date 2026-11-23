import SwiftUI
import SafariServices

// MARK: - Dòng báo giá (danh sách theo dõi)

struct QuoteRowView: View {
    let symbol: String
    let quote: Quote?
    let change: Double?
    let sparkline: [Double]
    var onSelect: () -> Void = {}

    private var category: SymbolCategory { PulseSymbol.category(for: symbol) }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                PulseIconBadge(symbol: category.symbol, tint: PulseTheme.categoryTint(category), size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PulseSymbol.displayName(symbol))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PulseTheme.textPrimary)
                    Text(category.title)
                        .font(.system(size: 10))
                        .foregroundStyle(PulseTheme.textTertiary)
                }
                Spacer(minLength: 6)
                if sparkline.count > 1 {
                    SparklineView(values: sparkline, tint: PulseTheme.changeColor(change ?? 0))
                        .frame(width: 56, height: 26)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text(quote.map { PulseFormat.price($0.mid, symbol: symbol) } ?? "—")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PulseTheme.textPrimary)
                    if let change {
                        Text(PulseFormat.signedPrice(change, digits: 2) + "%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PulseTheme.changeColor(change))
                    } else if let quote {
                        Text("spread " + PulseFormat.price(quote.spread, digits: PulseSymbol.digits(for: symbol)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(PulseTheme.textTertiary)
                    } else {
                        Text("chưa có giá")
                            .font(.system(size: 10))
                            .foregroundStyle(PulseTheme.textTertiary)
                    }
                }
                .frame(width: 96, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dòng sự kiện kinh tế

struct EventRowView: View {
    let event: EconomicEvent
    var isReminded: Bool = false
    var onToggleReminder: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PulseFormat.clock(event.date))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(event.isPast ? PulseTheme.textTertiary : PulseTheme.textPrimary)
                Text(event.date, formatter: EventRowView.dayFormatter)
                    .font(.system(size: 9))
                    .foregroundStyle(PulseTheme.textTertiary)
            }
            .frame(width: 44, alignment: .leading)

            Text(event.flag)
                .font(.system(size: 20))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(event.isPast ? PulseTheme.textSecondary : PulseTheme.textPrimary)
                    .lineLimit(2)
                if !event.forecast.isEmpty || !event.previous.isEmpty {
                    HStack(spacing: 10) {
                        if !event.forecast.isEmpty {
                            Text("Dự báo " + event.forecast)
                        }
                        if !event.previous.isEmpty {
                            Text("Trước " + event.previous)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(PulseTheme.textTertiary)
                }
            }
            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                PulseStatusPill(text: event.impact.title, color: PulseTheme.impactColor(event.impact))
                Button(action: onToggleReminder) {
                    Image(systemName: isReminded ? "bell.fill" : "bell")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isReminded ? PulseTheme.warning : PulseTheme.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(event.impact == .high && !event.isPast
                      ? PulseTheme.danger.opacity(0.06)
                      : Color.white.opacity(0.03))
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM"
        return formatter
    }()
}

// MARK: - Dòng tin tức

struct NewsRowView: View {
    let item: NewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(item.source)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(item.category.tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(item.category.tint.opacity(0.14)))
                Text(item.category.title)
                    .font(.system(size: 10))
                    .foregroundStyle(PulseTheme.textTertiary)
                Spacer()
                if let date = item.date {
                    Text(PulseFormat.relativeTime(date))
                        .font(.system(size: 10))
                        .foregroundStyle(PulseTheme.textTertiary)
                }
            }
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PulseTheme.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(PulseTheme.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }
}

// MARK: - Dòng cảnh báo giá

struct AlertRowView: View {
    let alert: PriceAlert
    var currentPrice: Double?
    var onToggle: () -> Void
    var onDelete: () -> Void

    private var digits: Int { PulseSymbol.digits(for: alert.symbol) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: alert.condition.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(alert.enabled ? PulseTheme.teal : PulseTheme.textTertiary)
                    Text(PulseSymbol.displayName(alert.symbol))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PulseTheme.textPrimary)
                    if alert.condition == .price {
                        Image(systemName: alert.direction.symbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(PulseTheme.textSecondary)
                    }
                }
                Text(alert.conditionText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(PulseTheme.teal)
                if let price = currentPrice {
                    Text("Hiện " + PulseFormat.price(price, digits: digits))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(PulseTheme.textSecondary)
                }
                if !alert.note.isEmpty {
                    Text(alert.note)
                        .font(.system(size: 11))
                        .foregroundStyle(PulseTheme.textTertiary)
                        .lineLimit(1)
                }
                if let last = alert.lastTriggeredAt {
                    Text("Kích hoạt " + PulseFormat.relativeTime(last) + (alert.triggerCount > 1 ? " · \(alert.triggerCount) lần" : ""))
                        .font(.system(size: 10))
                        .foregroundStyle(PulseTheme.warning)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { alert.enabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(PulseTheme.teal)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Xoá", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Xoá cảnh báo", systemImage: "trash")
            }
        }
    }
}

// MARK: - Mở link trong app (SFSafariViewController)

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Chọn mã (tìm kiếm + thêm/bỏ khỏi danh sách theo dõi)

private struct SymbolGroup: Identifiable {
    let category: SymbolCategory
    let symbols: [String]
    var id: String { category.rawValue }
}

struct SymbolPickerView: View {
    let instruments: [String]
    @Binding var watchlist: [String]
    var onPick: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? instruments : instruments.filter { $0.localizedCaseInsensitiveContains(trimmed) }
        return Array(base.prefix(300))
    }

    private var grouped: [SymbolGroup] {
        Dictionary(grouping: filtered) { PulseSymbol.category(for: $0) }
            .map { SymbolGroup(category: $0.key, symbols: $0.value) }
            .sorted { $0.category.rawValue < $1.category.rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                if watchlist.isEmpty && instruments.isEmpty {
                    Text("Chưa có danh sách mã. Kết nối Trader API để tải danh sách mã của tài khoản.")
                        .font(.system(size: 13))
                        .foregroundStyle(PulseTheme.textSecondary)
                }
                ForEach(grouped) { group in
                    Section(group.category.title) {
                        ForEach(group.symbols, id: \.self) { symbol in
                            Button {
                                if let onPick {
                                    onPick(symbol)
                                } else if watchlist.contains(symbol) {
                                    watchlist.removeAll { $0 == symbol }
                                } else {
                                    watchlist.append(symbol)
                                }
                            } label: {
                                HStack {
                                    Text(PulseSymbol.displayName(symbol))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(PulseTheme.textPrimary)
                                    Spacer()
                                    if watchlist.contains(symbol) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(PulseTheme.teal)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .searchable(text: $query, prompt: "Tìm mã (vd XAUUSD, BTCUSD)")
            .navigationTitle(onPick == nil ? "Danh sách theo dõi" : "Chọn mã")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                        .foregroundStyle(PulseTheme.teal)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

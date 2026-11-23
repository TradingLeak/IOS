import SwiftUI
import UIKit
import UserNotifications

struct AlertsView: View {
    @EnvironmentObject var store: PulseStore
    @State private var showEditor = false
    @State private var showSettings = false
    @State private var filterSymbol: String?
    @State private var permission: UNAuthorizationStatus = .notDetermined

    private var symbolsWithAlerts: [String] {
        Array(Set(store.alerts.map(\.symbol))).sorted()
    }

    private var visibleAlerts: [PriceAlert] {
        guard let filterSymbol else { return store.alerts }
        return store.alerts.filter { $0.symbol == filterSymbol }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    permissionBanner

                    if store.alerts.isEmpty {
                        emptyState
                    } else {
                        if symbolsWithAlerts.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    PulseFilterChip(title: "Tất cả", isSelected: filterSymbol == nil, tint: PulseTheme.warning) {
                                        filterSymbol = nil
                                    }
                                    ForEach(symbolsWithAlerts, id: \.self) { symbol in
                                        PulseFilterChip(title: PulseSymbol.displayName(symbol),
                                                        isSelected: filterSymbol == symbol,
                                                        tint: PulseTheme.warning) {
                                            filterSymbol = symbol
                                        }
                                    }
                                }
                            }
                        }

                        VStack(spacing: 8) {
                            ForEach(visibleAlerts) { alert in
                                AlertRowView(alert: alert,
                                             currentPrice: store.quotes[alert.symbol]?.mid,
                                             onToggle: { store.toggleAlert(alert) },
                                             onDelete: { store.deleteAlert(alert) })
                            }
                        }
                    }

                    historySection
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(PulseTheme.background)
            .navigationTitle("Cảnh báo giá")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(PulseTheme.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                AlertEditorView(symbol: store.selectedSymbol,
                                currentPrice: store.quotes[store.selectedSymbol]?.mid)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .task {
                permission = await AlertNotifier.shared.authorizationStatus()
            }
            .refreshable {
                permission = await AlertNotifier.shared.authorizationStatus()
                if store.isTradingConfigured {
                    await store.loadSparklines()
                }
            }
        }
    }

    // MARK: - Quyền thông báo

    @ViewBuilder
    private var permissionBanner: some View {
        if permission == .denied {
            HStack(spacing: 12) {
                PulseIconBadge(symbol: "bell.slash.fill", tint: PulseTheme.danger, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thông báo đang bị tắt")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PulseTheme.textPrimary)
                    Text("Bật thông báo trong Cài đặt iOS để nhận cảnh báo khi app không mở.")
                        .font(.system(size: 11))
                        .foregroundStyle(PulseTheme.textSecondary)
                }
                Spacer(minLength: 0)
                Button("Mở Cài đặt") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Capsule().fill(PulseTheme.danger))
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PulseTheme.danger.opacity(0.12)))
        }
    }

    // MARK: - Rỗng

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(PulseTheme.warning.opacity(0.12)).frame(width: 84, height: 84)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(PulseTheme.warning)
            }
            Text("Chưa có cảnh báo nào")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(PulseTheme.textPrimary)
            Text("Ví dụ: XAUUSD vượt 4_050, BTCUSD rơi dưới 60_000, hoặc EURUSD biến động hơn 0.5%.")
                .font(.system(size: 13))
                .foregroundStyle(PulseTheme.textSecondary)
                .multilineTextAlignment(.center)
            PulsePrimaryButton(title: "Tạo cảnh báo đầu tiên", symbol: "plus", tint: PulseTheme.warning) {
                showEditor = true
            }
            if !store.isTradingConfigured {
                Text("Cảnh báo giá cần Trader API để lấy báo giá. Vẫn tạo được trước, kích hoạt khi có giá.")
                    .font(.system(size: 11))
                    .foregroundStyle(PulseTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .pulseGlass()
    }

    // MARK: - Lịch sử

    @ViewBuilder
    private var historySection: some View {
        if !store.alertHistory.isEmpty {
            PulsePanelCard(title: "Lịch sử kích hoạt",
                           subtitle: "\(store.alertHistory.count) lần gần nhất",
                           symbol: "clock.arrow.circlepath",
                           tint: PulseTheme.textSecondary) {
                VStack(spacing: 0) {
                    ForEach(Array(store.alertHistory.prefix(15).enumerated()), id: \.element.id) { index, event in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(PulseTheme.warning)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(PulseTheme.textPrimary)
                                Text(event.message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(PulseTheme.textSecondary)
                                    .lineLimit(2)
                                Text(PulseFormat.relativeTime(event.date) + " · " + PulseFormat.clock(event.date) + " " + PulseFormat.shortDate(event.date))
                                    .font(.system(size: 10))
                                    .foregroundStyle(PulseTheme.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        if index < min(store.alertHistory.count, 15) - 1 {
                            Divider().overlay(PulseTheme.stroke)
                        }
                    }
                }
            }
        }
    }
}

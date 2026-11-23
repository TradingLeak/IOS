import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var store: PulseStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $store.selectedTab) {
            DashboardView()
                .tabItem { Label("Tổng quan", systemImage: "square.grid.2x2.fill") }
                .tag(PulseTab.dashboard)

            MarketView()
                .tabItem { Label("Giá", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(PulseTab.market)

            CalendarView()
                .tabItem { Label("Lịch", systemImage: "calendar") }
                .tag(PulseTab.calendar)

            NewsView()
                .tabItem { Label("Tin tức", systemImage: "newspaper.fill") }
                .tag(PulseTab.news)

            AlertsView()
                .badge(store.activeAlertCount)
                .tabItem { Label("Cảnh báo", systemImage: "bell.badge.fill") }
                .tag(PulseTab.alerts)
        }
        .task {
            // Bấm vào thông báo hệ thống → mở tab Cảnh báo.
            AlertNotifier.shared.onOpenAlerts = { store.openAlerts() }
            if AlertNotifier.shared.consumePendingRoute() == AlertNotifier.alertsRoute {
                store.selectedTab = .alerts
            }
            await store.bootstrap()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            // Quay lại app sau hơn 15 phút → nạp lại dữ liệu.
            if let updated = store.calendarUpdatedAt, Date().timeIntervalSince(updated) > 900 {
                Task { await store.refreshDashboard() }
            }
        }
    }
}

import SwiftUI

enum AppTab: Hashable {
    case overview
    case rewards
    case clients
    case transactions
    case settings
}

struct MainTabView: View {
    @EnvironmentObject var store: PartnerStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $store.selectedTab) {
            OverviewView()
                .tabItem { Label("Tổng quan", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.overview)

            RewardsView()
                .tabItem { Label("Hoa hồng", systemImage: "chart.bar.fill") }
                .tag(AppTab.rewards)

            ClientsView()
                .tabItem { Label("Khách hàng", systemImage: "person.2.fill") }
                .tag(AppTab.clients)

            TransactionsView()
                .tabItem { Label("Giao dịch", systemImage: "arrow.left.arrow.right") }
                .tag(AppTab.transactions)

            SettingsView()
                .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .task {
            // Bấm vào thông báo hệ thống → mở tab Hoa hồng.
            PaymentNotifier.shared.onOpenRewards = { store.openPayments() }
            if PaymentNotifier.shared.consumePendingOpenRewards() {
                store.selectedTab = .rewards
            }
            if store.tierState == nil {
                await store.refreshAll()
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            // Quay lại app sau hơn 5 phút → nạp lại để bắt khoản thanh toán mới.
            if let updated = store.lastUpdated, Date().timeIntervalSince(updated) > 300 {
                Task { await store.refreshAll() }
            }
        }
    }
}

import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: PulseStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.canBrowse {
                MainTabView()
            } else {
                NavigationStack {
                    OnboardingView()
                }
            }
        }
        .pulseScreenBackground()
        .animation(.easeInOut(duration: 0.25), value: store.canBrowse)
        .overlay(alignment: .top) {
            // Toast "cảnh báo giá đã kích hoạt" — hiện trên mọi tab.
            if let event = store.toast {
                PulseToastView(title: event.title,
                               message: event.message,
                               tint: PulseTheme.warning,
                               symbol: "bell.badge.fill",
                               onTap: { store.openAlerts() },
                               onDismiss: { store.dismissToast() })
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: event.id) {
                        // Tự ẩn sau 8 giây nếu người dùng không chạm.
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                        if store.toast?.id == event.id {
                            store.dismissToast()
                        }
                    }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: store.toast)
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                // Về nền → xếp lịch kiểm tra cảnh báo lần sau (Background App Refresh).
                AlertBackgroundRefresh.schedule()
            case .active:
                store.refreshStream()
            default:
                break
            }
        }
    }
}

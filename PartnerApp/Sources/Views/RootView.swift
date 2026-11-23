import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: PartnerStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.isConfigured {
                MainTabView()
            } else {
                NavigationStack {
                    OnboardingView()
                }
            }
        }
        .partnerScreenBackground()
        .animation(.easeInOut(duration: 0.25), value: store.isConfigured)
        .overlay(alignment: .top) {
            // Pop-up "có khoản thanh toán mới" — hiện trên mọi tab.
            if store.isConfigured, let event = store.paymentEvents.last {
                PaymentToastView(event: event,
                                 extraCount: store.paymentEvents.count - 1) {
                    store.openPayments()
                } onDismiss: {
                    store.paymentEvents = []
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: store.paymentEvents.count)
        .onChange(of: scenePhase) { phase in
            // Về nền → xếp lịch kiểm tra thanh toán lần sau (Background App Refresh).
            if phase == .background {
                BackgroundRefreshScheduler.schedule()
            }
        }
    }
}

import SwiftUI
import UIKit

@main
struct PartnerHubApp: App {
    @UIApplicationDelegateAdaptor(PartnerHubAppDelegate.self) private var appDelegate
    @StateObject private var store = PartnerStore()

    init() {
        AppAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(PartnerTheme.accent)
        }
    }
}

/// Đăng ký delegate thông báo + Background App Refresh trước khi app chạy xong launch
/// (bắt buộc với BGTaskScheduler và để nhận tap vào thông báo khi app đang tắt).
final class PartnerHubAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PaymentNotifier.shared.activate()
        BackgroundRefreshScheduler.register()
        BackgroundRefreshScheduler.schedule()
        return true
    }
}

/// Tinh chỉnh navigation bar + tab bar cho giao diện tối.
enum AppAppearance {
    static func configure() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(red: 0.027, green: 0.031, blue: 0.043, alpha: 1)
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        nav.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(red: 0.027, green: 0.031, blue: 0.043, alpha: 1)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

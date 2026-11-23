import SwiftUI
import UIKit

@main
struct PulseHubApp: App {
    @UIApplicationDelegateAdaptor(PulseHubAppDelegate.self) private var appDelegate
    @StateObject private var store = PulseStore()

    init() {
        PulseAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(PulseTheme.teal)
        }
    }
}

/// Đăng ký delegate thông báo + Background App Refresh trước khi app chạy xong launch
/// (bắt buộc với BGTaskScheduler và để nhận tap vào thông báo khi app đang tắt).
final class PulseHubAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AlertNotifier.shared.activate()
        AlertBackgroundRefresh.register()
        AlertBackgroundRefresh.schedule()
        return true
    }
}

/// Tinh chỉnh navigation bar + tab bar cho giao diện tối.
enum PulseAppearance {
    static func configure() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(red: 0.035, green: 0.040, blue: 0.070, alpha: 1)
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        nav.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(red: 0.035, green: 0.040, blue: 0.070, alpha: 1)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

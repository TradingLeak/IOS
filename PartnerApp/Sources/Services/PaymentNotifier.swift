import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

/// Gửi **local notification** (thông báo hệ thống, không cần server/APNs) khi có
/// khoản thanh toán mới trong lúc app không ở foreground. Với IPA unsigned không
/// có push từ server, đây là cách duy nhất để báo khi app đang đóng/không mở.
final class PaymentNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PaymentNotifier()

    /// Khoá UserDefaults bật/tắt thông báo (mặc định bật). Không dùng @AppStorage ở đây
    /// để tầng service không phụ thuộc SwiftUI.
    static let enabledKey = "paymentNotificationsEnabled"
    static let routeKey = "route"
    static let rewardsRoute = "rewards"

    /// Được gọi trên main queue khi người dùng bấm vào thông báo.
    var onOpenRewards: (() -> Void)?
    /// App được mở từ thông báo trước khi có view đăng ký `onOpenRewards`.
    private(set) var pendingOpenRewards = false

    private override init() {
        super.init()
    }

    /// Gọi trong `application(_:didFinishLaunchingWithOptions:)` — cần gán delegate
    /// trước khi app chạy xong launch để nhận tap vào thông báo khi app đang tắt.
    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func notify(events: [PaymentEvent]) {
        guard isEnabled, !events.isEmpty else { return }
        let summary = PaymentWatcher.summary(of: events)

        let content = UNMutableNotificationContent()
        content.title = summary.title
        content.body = summary.body
        content.sound = .default
        content.threadIdentifier = "partnerhub.payments"
        content.userInfo = [Self.routeKey: Self.rewardsRoute]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "payment-" + UUID().uuidString,
                                            content: content,
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Đọc và xoá cờ "mở từ thông báo" (view gọi một lần khi xuất hiện).
    func consumePendingOpenRewards() -> Bool {
        defer { pendingOpenRewards = false }
        return pendingOpenRewards
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let route = response.notification.request.content.userInfo[Self.routeKey] as? String
        if route == Self.rewardsRoute {
            DispatchQueue.main.async {
                self.pendingOpenRewards = true
                self.onOpenRewards?()
            }
        }
        completionHandler()
    }
}

/// Đăng ký Background App Refresh để iOS định kỳ đánh thức app kiểm tra thanh toán.
/// iOS **tự quyết định** thời điểm (thường 15–60 phút/lần khi app được dùng thường xuyên,
/// máy đang sạc/Wi-Fi); không đảm bảo chính xác.
enum BackgroundRefreshScheduler {
    /// Id = `<bundle id>.payment-refresh`, phải khai báo cùng giá trị trong Info.plist
    /// `BGTaskSchedulerPermittedIdentifiers` — mỗi app trong repo dùng id của chính mình.
    static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "com.tradingleak.partnerhub") + ".payment-refresh"
    static let minimumInterval: TimeInterval = 30 * 60

    /// Gọi một lần trong `application(_:didFinishLaunchingWithOptions:)`.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handle(task)
        }
    }

    static func schedule() {
        guard PaymentNotifier.shared.isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Người dùng tắt Background App Refresh hoặc chạy trên Simulator → bỏ qua.
        }
    }

    private static func handle(_ task: BGTask) {
        // Xếp lịch cho lần sau ngay để chuỗi không bị đứt.
        schedule()

        guard let refreshTask = task as? BGAppRefreshTask else {
            task.setTaskCompleted(success: false)
            return
        }
        let work = Task {
            let success = await BackgroundRefreshScheduler.run()
            refreshTask.setTaskCompleted(success: success)
        }
        refreshTask.expirationHandler = {
            work.cancel()
        }
    }

    /// Kiểm tra bằng key trong Keychain (không cần UI). `true` nếu gọi API thành công.
    static func run() async -> Bool {
        guard let credentials = CredentialKeychain().load() else { return false }
        let client = ExnessClient(credentials: credentials)
        do {
            let events = try await PaymentWatcher.check(using: client)
            PaymentNotifier.shared.notify(events: events)
            return true
        } catch {
            return false
        }
    }
}

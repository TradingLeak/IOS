import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

/// Gửi **local notification** (không cần server/APNs) khi cảnh báo giá kích hoạt
/// hoặc đến giờ nhắc sự kiện kinh tế.
final class AlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertNotifier()

    static let enabledKey = "pulse.alerts.notificationsEnabled"
    static let routeKey = "route"
    static let alertsRoute = "alerts"
    static let calendarRoute = "calendar"
    static let alertThread = "pulsehub.alerts"
    static let eventThread = "pulsehub.events"

    /// Được gọi trên main queue khi người dùng bấm vào thông báo.
    var onOpenAlerts: (() -> Void)?
    /// App được mở từ thông báo trước khi có view đăng ký `onOpenAlerts`.
    private(set) var pendingRoute: String?

    private override init() {
        super.init()
    }

    /// Gán delegate ngay trong `application(_:didFinishLaunchingWithOptions:)`.
    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
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

    // MARK: - Cảnh báo giá

    func notify(alert: PriceAlert, price: Double) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Cảnh báo giá · " + PulseSymbol.displayName(alert.symbol)
        content.body = alert.notificationBody(price: price)
        content.sound = .default
        content.threadIdentifier = Self.alertThread
        content.userInfo = [Self.routeKey: Self.alertsRoute, "symbol": alert.symbol]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "alert-" + alert.id.uuidString + "-" + String(Int(Date().timeIntervalSince1970)),
                                            content: content,
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Nhắc sự kiện kinh tế

    /// Xếp lịch thông báo trước sự kiện `minutesBefore` phút. `false` nếu mốc đã qua.
    @discardableResult
    func scheduleEventReminder(event: EconomicEvent, minutesBefore: Int) -> Bool {
        let fireDate = event.alertDate(minutesBefore: minutesBefore)
        guard fireDate > Date() else { return false }

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = "\(event.flag) \(event.currencyName) · \(event.title)"
        var parts = [event.impact.title + " ảnh hưởng"]
        parts.append(minutesBefore == 0 ? "phát hành ngay bây giờ" : "phát hành sau \(minutesBefore) phút")
        if !event.forecast.isEmpty { parts.append("Dự báo " + event.forecast) }
        if !event.previous.isEmpty { parts.append("Trước " + event.previous) }
        content.body = parts.joined(separator: " · ")
        content.sound = .default
        content.threadIdentifier = Self.eventThread
        content.userInfo = [Self.routeKey: Self.calendarRoute, "eventId": event.id]

        let request = UNNotificationRequest(identifier: CalendarReminderStore.notificationId(for: event.id),
                                            content: content,
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request)
        return true
    }

    func cancelEventReminder(eventId: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [CalendarReminderStore.notificationId(for: eventId)])
    }

    /// Đọc và xoá route đang chờ từ thông báo (view gọi một lần khi xuất hiện).
    func consumePendingRoute() -> String? {
        defer { pendingRoute = nil }
        return pendingRoute
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
        if let route {
            DispatchQueue.main.async {
                self.pendingRoute = route
                if route == Self.alertsRoute {
                    self.onOpenAlerts?()
                }
            }
        }
        completionHandler()
    }
}

/// Background App Refresh: iOS định kỳ đánh thức app để kiểm tra cảnh báo giá bằng
/// REST (nến 1 phút) khi app không mở. iOS **tự quyết định** thời điểm.
enum AlertBackgroundRefresh {
    /// Id = `<bundle id>.alert-refresh`, khai báo cùng giá trị trong Info.plist
    /// `BGTaskSchedulerPermittedIdentifiers`.
    static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "com.tradingleak.pulsehub") + ".alert-refresh"
    static let minimumInterval: TimeInterval = 15 * 60

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handle(task)
        }
    }

    static func schedule() {
        guard AlertNotifier.shared.isEnabled, !PriceAlertStore.load().isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Người dùng tắt Background App Refresh hoặc chạy trên Simulator → bỏ qua.
        }
    }

    private static func handle(_ task: BGTask) {
        schedule()
        guard let refreshTask = task as? BGAppRefreshTask else {
            task.setTaskCompleted(success: false)
            return
        }
        let work = Task {
            let success = await run()
            refreshTask.setTaskCompleted(success: success)
        }
        refreshTask.expirationHandler = {
            work.cancel()
        }
    }

    /// Kiểm tra cảnh báo bằng key trong Keychain (không cần UI). `true` nếu gọi API thành công.
    static func run() async -> Bool {
        guard AlertNotifier.shared.isEnabled else { return true }
        guard var credentials = PulseKeychain().load(),
              let trading = credentials.tradingCredentials else {
            return false
        }
        let alerts = PriceAlertStore.load().filter { $0.enabled }
        guard !alerts.isEmpty else { return true }

        // REST phải đi qua access point; chưa có thì phát hiện qua gateway rồi lưu lại Keychain.
        func makeClient() -> TradingClient {
            let account = credentials.tradingCredentials ?? trading
            let gateway = credentials.tradingGatewayCredentials ?? account
            return TradingClient(discovery: ExnessClient(credentials: gateway),
                                 account: ExnessClient(credentials: account),
                                 accountId: credentials.accountId)
        }
        var client = makeClient()
        if credentials.accessPoint?.isEmpty != false, let point = try? await client.accessPoint() {
            credentials.accessPoint = point
            try? PulseKeychain().save(credentials)
            client = makeClient()
        }
        let knownInstruments = UserDefaults.standard.stringArray(forKey: PulseSymbol.instrumentsDefaultsKey) ?? []
        var success = true
        var history = AlertHistoryStore.load()

        for alert in alerts {
            do {
                let api = PulseSymbol.apiInstrument(alert.symbol, in: knownInstruments)
                guard let price = try await client.latestPrice(symbol: api) else { continue }
                if let fired = AlertEvaluator.fire(alert, price: price) {
                    var all = PriceAlertStore.load()
                    if let index = all.firstIndex(where: { $0.id == fired.id }) {
                        all[index] = fired
                    }
                    PriceAlertStore.save(all)
                    AlertNotifier.shared.notify(alert: fired, price: price)
                    history.insert(AlertEvent(alertId: fired.id,
                                              symbol: fired.symbol,
                                              title: "Cảnh báo giá · " + PulseSymbol.displayName(fired.symbol),
                                              message: fired.notificationBody(price: price),
                                              price: price,
                                              date: Date()), at: 0)
                }
            } catch {
                success = false
            }
        }
        AlertHistoryStore.save(history)
        return success
    }
}

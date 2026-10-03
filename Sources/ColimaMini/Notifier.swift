import AppKit
import ColimaAppState
import ColimaCore
import UserNotifications

// Delivers container alerts as macOS notifications. Clicking one opens the
// container's logs. Only a packaged app has the identity notifications require.
@MainActor final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var openLogs: ((String) -> Void)?
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
            ? UNUserNotificationCenter.current() : nil
    }
    func attach(to model: Dashboard, openLogs: @escaping (String) -> Void) {
        self.openLogs = openLogs
        guard let center, !model.sample else { return }
        center.delegate = self
        if model.notificationsEnabled { requestAuthorization() }
        model.onAlerts = { [weak self] alerts in self?.deliver(alerts) }
    }
    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    private func deliver(_ alerts: [ContainerAlert]) {
        guard let center else { return }
        // A burst, such as a whole project failing, becomes one notification.
        let content = UNMutableNotificationContent()
        if alerts.count == 1, let alert = alerts.first {
            content.title = alert.title
            content.body = alert.message
            content.userInfo = ["container": alert.containerID]
        } else {
            content.title = "\(alerts.count) containers need attention"
            content.body = alerts.map(\.title).joined(separator: "\n")
            if let first = alerts.first { content.userInfo = ["container": first.containerID] }
        }
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.content.userInfo["container"] as? String
        Task { @MainActor in
            if let id { self.openLogs?(id) }
            completionHandler()
        }
    }
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

import AppKit
import ColimaAppState
import ColimaCore
import UserNotifications

// Delivers container alerts as macOS notifications. Clicking one opens the
// container's logs; clicking a cleanup alert opens the unused-container review.
// Only a packaged app has the identity notifications require.
@MainActor final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var openLogs: ((String) -> Void)?
    private var openReview: (() -> Void)?
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
            ? UNUserNotificationCenter.current() : nil
    }
    func attach(
        to model: Dashboard, openLogs: @escaping (String) -> Void, openReview: @escaping () -> Void
    ) {
        self.openLogs = openLogs
        self.openReview = openReview
        guard let center, !model.sample else { return }
        center.delegate = self
        if model.notificationsEnabled { requestAuthorization() }
        model.onAlerts = { [weak self] alerts in self?.deliver(alerts) }
        model.onCleanupAlert = { [weak self] alert in self?.deliver(alert) }
    }
    private func deliver(_ alert: CleanupAlert) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message
        content.userInfo = ["review": true]
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
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
        let info = response.notification.request.content.userInfo
        let id = info["container"] as? String
        let review = info["review"] as? Bool == true
        Task { @MainActor in
            if review {
                self.openReview?()
            } else if let id {
                self.openLogs?(id)
            }
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

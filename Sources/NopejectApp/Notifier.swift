import Foundation
import UserNotifications

/// 系统通知封装。通知权限在首次打开 App 时申请。
enum Notifier {
    /// 是否运行在 .app bundle 中（swift run 裸进程下 UNUserNotificationCenter 会崩溃）。
    private static var isBundled: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    static func requestPermissionIfNeeded() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func notifyBlocked(volumeName: String) {
        notify(title: L10n.t("notify.blocked.title"), body: L10n.tf("notify.blocked.body", volumeName))
    }
}

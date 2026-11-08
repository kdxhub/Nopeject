import AppKit
import UserNotifications
import NopejectCore

/// 应用代理：注册访达服务、申请通知权限、启动后端连接。
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 访达快捷操作（服务菜单）：接收目录并定位其所在挂载点。
        NSApp.servicesProvider = self

        // 通知权限：首次打开 App 即申请。
        UNUserNotificationCenter.current().delegate = self
        Notifier.requestPermissionIfNeeded()

        // 启动 / 连接后端守护进程，并注册开机自启动。
        AppState.shared.bootstrap()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - 通知展示（App 前台时也显示横幅）

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - 访达服务入口

    /// NSServices 处理器：接收访达选中的文件/目录，判断其所在挂载点并高亮提示。
    @objc func locateMountPoint(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSError>
    ) {
        guard let paths = pboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ) as? [String], let first = paths.first else { return }
        Task { @MainActor in
            AppState.shared.locateMountPoint(forPath: first)
        }
    }
}

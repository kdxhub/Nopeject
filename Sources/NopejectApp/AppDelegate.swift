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

        // 首次启动引导：本应用常驻菜单栏且无 Dock 图标，提示用户去菜单栏找入口。
        showOnboardingOnceIfNeeded()
    }

    // MARK: - 首次启动引导

    private static let onboardingFlag = "nopeject.onboarding.v1.shown"

    private func showOnboardingOnceIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.onboardingFlag) else { return }
        defaults.set(true, forKey: Self.onboardingFlag)

        // 稍作延迟：让系统通知权限弹窗先出现，避免两个弹窗叠在一起。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.showOnboarding()
        }
    }

    private func showOnboarding() {
        let alert = NSAlert()
        alert.messageText = L10n.t("onboarding.title")
        alert.informativeText = L10n.t("onboarding.text")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.t("onboarding.ok"))
        if let symbol = NSImage(
            systemSymbolName: "externaldrive.badge.checkmark",
            accessibilityDescription: nil
        ) {
            alert.icon = symbol
        }
        alert.runModal()
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

    // MARK: - 通知点击

    /// 点击已阻止推出的通知 → 弹窗询问是否临时推出对应磁盘。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        guard request.identifier.hasPrefix(Notifier.blockedIdentifierPrefix) else {
            completionHandler()
            return
        }
        let info = request.content.userInfo
        let event = BlockedEvent(
            volumeName: info["volumeName"] as? String ?? "",
            uuid: info["uuid"] as? String,
            path: info["path"] as? String
        )
        Task { @MainActor in
            AppState.shared.confirmTemporaryEject(for: event)
        }
        completionHandler()
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

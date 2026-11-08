import AppKit
import Foundation
import UserNotifications
import NopejectCore

/// 系统通知封装。通知权限在首次打开 App 时申请。
enum Notifier {
    /// 是否运行在 .app bundle 中（swift run 裸进程下 UNUserNotificationCenter 会崩溃）。
    private static var isBundled: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// 点击已阻止通知的 identifier 前缀（NotificationDelegate 依此路由点击行为）。
    static let blockedIdentifierPrefix = "nopeject.blocked."

    /// 同一挂载点的防抖窗口：macOS 推出失败后会高频重试，窗口期内不重复弹通知。
    private static let debounceInterval: TimeInterval = 10
    private static var lastNotifiedAt: [String: Date] = [:]

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

    /// 拦截通知：同一挂载点在防抖窗口内只弹一次；带挂载点图标 + 右下角 App logo 附件，
    /// 点击后由 NotificationDelegate 弹出「临时推出」询问。
    static func notifyBlocked(event: BlockedEvent) {
        guard isBundled else { return }

        let now = Date()
        let key = event.uuid ?? event.path ?? event.volumeName
        if let last = lastNotifiedAt[key], now.timeIntervalSince(last) < debounceInterval {
            return
        }
        lastNotifiedAt[key] = now

        let content = UNMutableNotificationContent()
        content.title = L10n.t("notify.blocked.title")
        content.body = L10n.tf("notify.blocked.body", event.volumeName)
        content.sound = .default
        content.userInfo = [
            "volumeName": event.volumeName,
            "uuid": event.uuid ?? "",
            "path": event.path ?? ""
        ]
        if let attachment = volumeIconAttachment(volumePath: event.path) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: blockedIdentifierPrefix + UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// 合成通知附件：挂载点同款图标为主体，右下角叠加 App 图标。
    private static func volumeIconAttachment(volumePath: String?) -> UNNotificationAttachment? {
        let size: CGFloat = 144
        let base: NSImage
        if let volumePath, FileManager.default.fileExists(atPath: volumePath) {
            base = NSWorkspace.shared.icon(forFile: volumePath)
        } else if let app = NSApp.applicationIconImage {
            base = app
        } else {
            return nil
        }

        let composite = NSImage(size: NSSize(width: size, height: size))
        composite.lockFocus()
        base.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        if let appIcon = NSApp.applicationIconImage {
            let overlay = size * 0.42
            appIcon.draw(in: NSRect(x: size - overlay, y: 0, width: overlay, height: overlay))
        }
        composite.unlockFocus()

        guard let tiff = composite.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nopeject-notify", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("volume-icon-\(UUID().uuidString).png")
        do {
            try png.write(to: fileURL)
            return try UNNotificationAttachment(identifier: "volumeIcon", url: fileURL, options: nil)
        } catch {
            return nil
        }
    }
}

import Foundation
import AppKit
import SwiftUI
import ServiceManagement
import NopejectCore

/// 前端应用状态。
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum SaveState: Equatable {
        case idle, saving, saved
    }

    enum Screen: Equatable {
        case main, preferences, about
    }

    // MARK: - 发布状态

    @Published var mountPoints: [MountPoint] = []
    @Published var savedConfig: NopejectConfig = NopejectConfig()
    @Published var pendingProtected: Set<String> = []
    @Published var backendRunning = false
    @Published var saveState: SaveState = .idle
    @Published var highlightUUID: String?
    /// 当前右键菜单打开的挂载点 ID（用于高亮该行）。
    @Published var contextMenuUUID: String?
    @Published var screen: Screen = .main
    @Published var statusMessage: String?

    /// 赞助链接。
    static let sponsorURL = URL(string: "http://kdx233.github.io/s/donate")!

    /// 项目主页。
    static let githubURL = URL(string: "https://github.com/kdxhub/Nopeject")!

    private var client = BackendClient()
    /// 打开界面是否已完成密码验证（界面关闭后重置）。
    @Published var uiAuthorized = false
    /// 正在进行系统身份验证（期间禁止再次发起，避免重复弹出认证框）。
    @Published var isAuthenticating = false
    /// 等待守护进程确认的配置（configSaved 到达后整体回写）。
    private var pendingConfig: NopejectConfig?
    private var pendingSaveContinuation: CheckedContinuation<Void, Never>?
    private var savedResetTask: Task<Void, Never>?

    var hasPendingEdits: Bool {
        pendingProtected != Set(savedConfig.protectedUUIDs)
    }

    /// 界面是否处于锁定状态（开启「打开界面需要密码」且本次打开未验证）。
    var isUILocked: Bool {
        savedConfig.requireAuthOpenUI && !uiAuthorized
    }

    // MARK: - 生命周期

    func bootstrap() {
        Notifier.requestPermissionIfNeeded()
        registerLoginItem()
        startClient()
        startPeriodicRefresh()
    }

    private func registerLoginItem() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        if #available(macOS 13.0, *) {
            do {
                _ = try SMAppService.mainApp.register()
            } catch {
                FileHandle.standardError.write(Data("Nopeject: 注册开机自启动失败: \(error)\n".utf8))
            }
        }
    }

    private func startClient() {
        client.onMessage = { [weak self] message in
            Task { @MainActor in self?.handle(message: message) }
        }
        client.onConnected = { [weak self] in
            Task { @MainActor in
                self?.backendRunning = true
                self?.client.send(IPCMessage(action: IPCMessage.getMountPoints))
                self?.client.send(IPCMessage(action: IPCMessage.getConfig))
            }
        }
        client.onDisconnected = { [weak self] in
            Task { @MainActor in
                self?.backendRunning = false
                self?.pendingSaveContinuation?.resume()
                self?.pendingSaveContinuation = nil
            }
        }
        client.start()
    }

    // MARK: - 数据刷新

    /// 菜单打开或周期触发时向守护进程请求最新数据，
    /// 确保重启前端、前端与后端状态漂移等场景下列表始终正确。
    func refresh() {
        client.send(IPCMessage(action: IPCMessage.getMountPoints))
        client.send(IPCMessage(action: IPCMessage.getConfig))
    }

    private func startPeriodicRefresh() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, self.backendRunning else { continue }
                self.client.send(IPCMessage(action: IPCMessage.getMountPoints))
            }
        }
    }

    // MARK: - 消息处理

    private func handle(message: IPCMessage) {
        switch message.action {
        case IPCMessage.mountPoints:
            if let mounts = message.decode(as: [MountPoint].self) {
                mountPoints = mounts
            }

        case "config":
            if let config = message.decode(as: NopejectConfig.self) {
                savedConfig = config
                pendingProtected = Set(config.protectedUUIDs)
            }

        case IPCMessage.configSaved:
            // 用发送时完整配置回写（含 permissionMode），保证模式切换立即生效。
            if let pending = pendingConfig {
                savedConfig = pending
                pendingConfig = nil
            } else {
                savedConfig.protectedUUIDs = Array(pendingProtected).sorted()
            }
            setSaveState(.saved)
            pendingSaveContinuation?.resume()
            pendingSaveContinuation = nil

        case IPCMessage.blocked:
            if let event = message.decode(as: BlockedEvent.self) {
                Notifier.notifyBlocked(event: event)
            }

        case IPCMessage.remountResult:
            if let result = message.decode(as: RemountResult.self) {
                Notifier.notifyRemountResult(ok: result.ok, volumeName: result.volumeName)
            }

        case IPCMessage.ejectResult:
            if let result = message.decode(as: EjectResult.self) {
                statusMessage = result.ok ? nil : result.message
            }
            client.send(IPCMessage(action: IPCMessage.getMountPoints))

        default:
            break
        }
    }

    private func setSaveState(_ newState: SaveState) {
        withAnimation(.spring(duration: 0.35)) {
            saveState = newState
        }
        savedResetTask?.cancel()
        if newState == .saved {
            savedResetTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                self?.setSaveState(.idle)
            }
        }
    }

    // MARK: - 编辑操作

    /// 切换某挂载点的保护状态（开启「编辑保护状态需要密码」时每次都要求验证）。
    func toggle(_ mount: MountPoint, to newValue: Bool) async {
        if savedConfig.requireAuthEdit {
            guard await authenticate(reason: String(format: L10n.t("auth.reason.toggleProtection"), mount.name)) else { return }
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            if newValue {
                pendingProtected.insert(mount.id)
            } else {
                pendingProtected.remove(mount.id)
            }
        }
        // 即改即存，无需手动保存。
        await save()
    }

    /// 保存配置到守护进程。
    func save() async {
        guard hasPendingEdits else { return }
        setSaveState(.saving)
        var config = savedConfig
        config.protectedUUIDs = Array(pendingProtected).sorted()
        pendingConfig = config
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pendingSaveContinuation = continuation
            client.send(IPCMessage.encode(IPCMessage.setConfig, config))
        }
    }

    /// 更新偏好设置开关，随后立即持久化。
    /// authReason 非空时先做管理员验证（安全类开关），取消验证则不生效。
    func setPreference(
        _ keyPath: WritableKeyPath<NopejectConfig, Bool>,
        to value: Bool,
        authReason: String? = nil
    ) async {
        if let authReason {
            guard await authenticate(reason: authReason) else { return }
        }
        guard savedConfig[keyPath: keyPath] != value else { return }
        var config = savedConfig
        config[keyPath: keyPath] = value
        config.protectedUUIDs = Array(pendingProtected).sorted()
        pendingConfig = config
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pendingSaveContinuation = continuation
            client.send(IPCMessage.encode(IPCMessage.setConfig, config))
        }
    }

    /// 打开界面时的密码验证（开启「打开界面需要密码」时自动触发）。
    func authorizeUIIfNeeded() async {
        guard isUILocked, !isAuthenticating else { return }
        if await authenticate(reason: L10n.t("auth.reason.openUI")) {
            uiAuthorized = true
        }
    }

    /// 发起系统身份验证；验证期间挂起状态互斥，不允许并发重复弹出认证界面。
    /// reason 会拼在系统认证框的「“Nopeject”想要」之后，让用户知道这次验证要做什么。
    private func authenticate(reason: String? = nil) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        return await AdminAuth.requireAdmin(reason: reason)
    }

    // MARK: - 右键菜单与底部菜单动作

    /// 临时推出：通知守护进程一次性放行并执行推出。
    func temporaryEject(_ mount: MountPoint) {
        Task { await temporaryEject(id: mount.id, volumeName: mount.name) }
    }

    /// 按挂载点 ID（uuid 或路径）临时推出，供通知点击等没有完整 MountPoint 的场景使用。
    /// 开启「临时推出需要密码」时先验证再放行。
    func temporaryEject(id: String, volumeName: String? = nil) async {
        guard !id.isEmpty else { return }
        if savedConfig.requireAuthTemporaryEject {
            let name = volumeName ?? id
            guard await authenticate(reason: String(format: L10n.t("auth.reason.temporaryEject"), name)) else { return }
        }
        client.send(IPCMessage(action: IPCMessage.ejectOnce, data: id))
    }

    /// 点击拦截通知后的确认弹窗：询问用户是否临时推出被拦截的磁盘。
    func confirmTemporaryEject(for event: BlockedEvent) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.tf("alert.eject.title", event.volumeName)
        alert.informativeText = L10n.t("alert.eject.text")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.t("ctx.temporaryEject"))
        alert.addButton(withTitle: L10n.t("alert.quit.cancel"))
        if let icon = NSImage(systemSymbolName: "eject.fill", accessibilityDescription: nil) {
            alert.icon = icon
        }
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task { await temporaryEject(id: event.uuid ?? event.path ?? "", volumeName: event.volumeName) }
        }
    }

    func revealInFinder(_ mount: MountPoint) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: mount.path)])
    }

    /// 强制重启服务。
    func restartBackend() {
        client.stop()
        Task.detached {
            BackendClient.sendShutdownOnce()
            try? await Task.sleep(nanoseconds: 500_000_000)
            BackendClient.spawnDaemon()
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            self?.client = BackendClient()
            self?.startClient()
        }
    }

    /// 完全退出：二次确认（红色破坏性按钮）后，先停守护进程，再退出前端。
    func quitAll() {
        let alert = NSAlert()
        alert.messageText = L10n.t("alert.quit.title")
        alert.informativeText = L10n.t("alert.quit.text")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.t("alert.quit.confirm"))
        alert.addButton(withTitle: L10n.t("alert.quit.cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        alert.buttons.last?.keyEquivalent = "\u{1b}" // Esc 取消
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        client.stop()
        Task.detached {
            BackendClient.sendShutdownOnce()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    /// 仅退出前端（守护进程继续常驻）。
    func quitFrontendOnly() {
        NSApp.terminate(nil)
    }

    // MARK: - Finder 快捷操作回调

    /// 接收来自访达（NSServices）的目录路径，定位其所在挂载点。
    func locateMountPoint(forPath path: String) {
        guard let mount = MountEnumerator.mountPoint(containing: path) else {
            Notifier.notify(title: L10n.t("notify.locate.title"), body: L10n.t("notify.locate.notFound"))
            return
        }
        highlightUUID = mount.id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            self?.highlightUUID = nil
        }
        Notifier.notify(
            title: L10n.t("notify.locate.title"),
            body: L10n.tf("notify.locate.body", mount.name)
        )
    }
}

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
        case main, security, about
    }

    // MARK: - 发布状态

    @Published var mountPoints: [MountPoint] = []
    @Published var savedConfig: NopejectConfig = NopejectConfig()
    @Published var pendingProtected: Set<String> = []
    @Published var backendRunning = false
    @Published var saveState: SaveState = .idle
    @Published var highlightUUID: String?
    @Published var screen: Screen = .main
    @Published var statusMessage: String?

    /// 赞助链接（发布时替换为实际地址）。
    static let sponsorURL = URL(string: "https://afdian.com/a/neonai")!

    private var client = BackendClient()
    private var editAuthorized = false
    private var pendingSaveContinuation: CheckedContinuation<Void, Never>?
    private var savedResetTask: Task<Void, Never>?

    var hasPendingEdits: Bool {
        pendingProtected != Set(savedConfig.protectedUUIDs)
    }

    var permissionMode: PermissionMode {
        savedConfig.permissionMode
    }

    // MARK: - 生命周期

    func bootstrap() {
        Notifier.requestPermissionIfNeeded()
        registerLoginItem()
        startClient()
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
                editAuthorized = false
            }

        case IPCMessage.configSaved:
            savedConfig.protectedUUIDs = Array(pendingProtected).sorted()
            editAuthorized = false
            setSaveState(.saved)
            pendingSaveContinuation?.resume()
            pendingSaveContinuation = nil

        case IPCMessage.blocked:
            if let event = message.decode(as: BlockedEvent.self) {
                Notifier.notifyBlocked(volumeName: event.volumeName)
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

    /// 切换某挂载点的保护状态（可能要求管理员验证）。
    func toggle(_ mount: MountPoint, to newValue: Bool) async {
        switch permissionMode {
        case .none:
            break
        case .requireForEdit:
            if !editAuthorized {
                guard await AdminAuth.requireAdmin() else { return }
                editAuthorized = true
            }
        case .always:
            guard await AdminAuth.requireAdmin() else { return }
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            if newValue {
                pendingProtected.insert(mount.id)
            } else {
                pendingProtected.remove(mount.id)
            }
        }
    }

    /// 保存配置到守护进程。
    func save() async {
        guard hasPendingEdits || savedConfig.permissionMode != permissionMode else { return }
        setSaveState(.saving)
        var config = savedConfig
        config.protectedUUIDs = Array(pendingProtected).sorted()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pendingSaveContinuation = continuation
            client.send(IPCMessage.encode(IPCMessage.setConfig, config))
        }
    }

    /// 更改权限模式（切换需验证管理员密码，随后立即持久化）。
    func changePermissionMode(to newMode: PermissionMode) async {
        guard newMode != permissionMode else { return }
        guard await AdminAuth.requireAdmin() else { return }
        var config = savedConfig
        config.permissionMode = newMode
        config.protectedUUIDs = Array(pendingProtected).sorted()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pendingSaveContinuation = continuation
            client.send(IPCMessage.encode(IPCMessage.setConfig, config))
        }
    }

    // MARK: - 右键菜单与底部菜单动作

    /// 临时弹出：通知守护进程一次性放行并执行推出。
    func temporaryEject(_ mount: MountPoint) {
        client.send(IPCMessage(action: IPCMessage.ejectOnce, data: mount.id))
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

    /// 完全退出：先停守护进程，再退出前端。
    func quitAll() {
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

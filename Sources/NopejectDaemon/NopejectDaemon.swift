import Foundation
import DiskArbitration
import NopejectCore

/// DARegisterDiskUnmountApprovalCallback 的 C 回调签名。
private typealias UnmountApprovalCallback = @convention(c) (
    DADisk, UnsafeMutableRawPointer?
) -> Unmanaged<DADissenter>?

private let unmountApprovalCallback: UnmountApprovalCallback = { disk, context in
    guard let context else { return nil }
    let daemon = Unmanaged<NopejectDaemon>.fromOpaque(context).takeUnretainedValue()
    return daemon.handleUnmountApproval(disk: disk)
}

/// DARegisterDiskDisappearedCallback 的 C 回调签名。
private typealias DiskDisappearedCallback = @convention(c) (
    DADisk, UnsafeMutableRawPointer?
) -> Void

private let diskDisappearedCallback: DiskDisappearedCallback = { disk, context in
    guard let context else { return }
    let daemon = Unmanaged<NopejectDaemon>.fromOpaque(context).takeUnretainedValue()
    daemon.handleDiskDisappeared(disk: disk)
}

/// Nopeject 后端守护进程。
///
/// - 注册 DiskArbitration 卸载审批回调（DARegisterDiskUnmountApprovalCallback），
///   对受保护宗卷构造 DADissenter 阻止推出；
/// - 监听 Unix domain socket 与前端通信（uid 校验 + HMAC 挑战-应答）；
/// - 与前端断连时不报错、不退出，继续独立承担拦截职责。
public final class NopejectDaemon {
    private let store = ConfigStore()
    private let secret: String
    private var session: DASession?
    private let lock = NSLock()
    private var temporarilyAllowed = Set<String>()
    /// 已记录的主动推出（临时推出等）：对应磁盘消失时不算意外，不做恢复。
    private var expectedEjects = Set<String>()
    private var activeConnections: [ObjectIdentifier: SocketConnection] = [:]

    public init() {
        secret = SecureChannel.loadOrCreateSecret()
    }

    // MARK: - 生命周期

    public func run() {
        // DiskArbitration 会话调度到主 RunLoop。
        if let session = DASessionCreate(kCFAllocatorDefault) as DASession? {
            self.session = session
            DARegisterDiskUnmountApprovalCallback(
                session,
                nil,
                unmountApprovalCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )
            DARegisterDiskDisappearedCallback(
                session,
                nil,
                diskDisappearedCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )
            DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }

        // IPC 服务端运行在后台队列（与前端断连不影响主职责）。
        let server = UnixSocketServer(path: SecureChannel.socketPath()) { [weak self] fd in
            self?.handleConnection(fd: fd)
        }
        do {
            try server.start()
        } catch let error as POSIXError where error.code == .EADDRINUSE {
            FileHandle.standardError.write(Data("nopejectd: 已有实例在运行（IPC socket 被占用），退出\n".utf8))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("nopejectd: 无法监听 IPC socket: \(error)\n".utf8))
            exit(1)
        }

        FileHandle.standardError.write(Data("nopejectd: started\n".utf8))
        CFRunLoopRun()
    }

    public func requestShutdown() {
        if let session {
            DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        CFRunLoopStop(CFRunLoopGetMain())
    }

    // MARK: - 推出拦截

    /// DiskArbitration 卸载审批：受保护宗卷返回 DADissenter 阻止，其余放行（nil）。
    func handleUnmountApproval(disk: DADisk) -> Unmanaged<DADissenter>? {
        guard let desc = DADiskCopyDescription(disk) as? [String: Any] else { return nil }
        let uuid = desc[kDADiskDescriptionVolumeUUIDKey as String]
            .map { unsafeDowncast($0 as AnyObject, to: CFUUID.self) }
            .map { CFUUIDCreateString(kCFAllocatorDefault, $0) as String }
        let name = desc[kDADiskDescriptionVolumeNameKey as String] as? String
            ?? desc[kDADiskDescriptionMediaNameKey as String] as? String
            ?? "Volume"
        let path = desc[kDADiskDescriptionVolumePathKey as String] as? URL

        guard let uuid, isProtected(uuid: uuid) else { return nil }

        // 临时弹出：消耗一次性豁免后放行。
        lock.lock()
        let wasTemporarilyAllowed = temporarilyAllowed.remove(uuid) != nil
        lock.unlock()
        if wasTemporarilyAllowed {
            return nil
        }

        broadcast(IPCMessage.encode(
            IPCMessage.blocked,
            BlockedEvent(volumeName: name, uuid: uuid, path: path?.path)
        ))

        let dissenter = DADissenterCreate(
            kCFAllocatorDefault,
            DAReturn(kDAReturnNotPermitted),
            "Protected by Nopeject" as CFString
        )
        return Unmanaged.passRetained(dissenter)
    }

    private func isProtected(uuid: String) -> Bool {
        store.current.protectedUUIDs.contains(uuid)
    }

    // MARK: - 意外推出恢复

    /// 磁盘消失回调：受保护磁盘意外消失时按配置尝试重新挂载并通知前端结果。
    /// 主动操作（临时推出）已记录豁免，不算意外。
    func handleDiskDisappeared(disk: DADisk) {
        guard store.current.remountAfterUnexpectedEject,
              let desc = DADiskCopyDescription(disk) as? [String: Any],
              let uuid = desc[kDADiskDescriptionVolumeUUIDKey as String]
                  .map({ unsafeDowncast($0 as AnyObject, to: CFUUID.self) })
                  .map({ CFUUIDCreateString(kCFAllocatorDefault, $0) as String }),
              isProtected(uuid: uuid) else { return }

        lock.lock()
        let expected = expectedEjects.remove(uuid) != nil
        lock.unlock()
        if expected { return }

        let name = desc[kDADiskDescriptionVolumeNameKey as String] as? String
            ?? desc[kDADiskDescriptionMediaNameKey as String] as? String
            ?? "Volume"
        let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String

        Task.detached { [weak self] in
            guard let self else { return }
            let ok = await self.tryRemount(bsdName: bsdName)
            self.broadcast(IPCMessage.encode(
                IPCMessage.remountResult,
                RemountResult(ok: ok, volumeName: name)
            ))
        }
    }

    /// 尝试重新挂载：磁盘刚消失时系统可能仍在处理，间隔做两次尝试。
    private func tryRemount(bsdName: String?) async -> Bool {
        guard let bsdName else { return false }
        for delay in [0.6, 2.0] {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if runDiskUtil(["mount", "/dev/\(bsdName)"]).ok { return true }
        }
        return false
    }

    /// 执行 diskutil 子命令，返回退出状态与合并输出。
    private func runDiskUtil(_ arguments: [String]) -> (ok: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else {
            return (false, "无法启动 diskutil")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus == 0, output)
    }

    // MARK: - IPC 连接处理

    private func handleConnection(fd: Int32) {
        defer { close(fd) }

        // 1. 对端必须与本进程同 uid。
        guard UnixSocketConnector.checkPeerIsSameUser(fd) else { return }

        let conn = SocketConnection(fd: fd)
        conn.setReadTimeout(5)

        // 2. 挑战-应答握手（HMAC-SHA256，一次性 nonce）。
        let nonce = UUID().uuidString
        guard conn.send(IPCMessage(action: IPCMessage.challenge, data: nonce)),
              let proofMsg = conn.receive(),
              proofMsg.action == IPCMessage.proof,
              let proof = proofMsg.data,
              SecureChannel.verify(secret: secret, nonce: nonce, proof: proof) else {
            conn.send(IPCMessage(action: IPCMessage.authFail))
            return
        }
        guard conn.send(IPCMessage(action: IPCMessage.authOk)) else { return }

        // 3. 消息循环：前端断开即结束本连接处理，守护进程继续常驻。
        conn.setReadTimeout(0)
        lock.lock()
        activeConnections[ObjectIdentifier(conn)] = conn
        lock.unlock()
        defer {
            lock.lock()
            activeConnections.removeValue(forKey: ObjectIdentifier(conn))
            lock.unlock()
        }

        while let message = conn.receive() {
            guard handle(message: message, conn: conn) else { break }
        }
    }

    /// 处理一条前端消息；返回 false 表示结束连接（如 shutdown）。
    private func handle(message: IPCMessage, conn: SocketConnection) -> Bool {
        switch message.action {
        case IPCMessage.ping:
            conn.send(IPCMessage(action: IPCMessage.pong))

        case IPCMessage.getMountPoints:
            conn.send(IPCMessage.encode(IPCMessage.mountPoints, MountEnumerator.enumerate()))

        case IPCMessage.getConfig:
            conn.send(IPCMessage.encode("config", store.current))

        case IPCMessage.setConfig:
            if let config = message.decode(as: NopejectConfig.self) {
                store.update(config)
                conn.send(IPCMessage(action: IPCMessage.configSaved))
            } else {
                conn.send(IPCMessage(action: "configError"))
            }

        case IPCMessage.ejectOnce:
            handleEjectOnce(message: message, conn: conn)

        case IPCMessage.shutdown:
            broadcast(IPCMessage(action: "shutdownNotice"))
            requestShutdown()
            return false

        default:
            break
        }
        return true
    }

    /// 临时弹出：本次放行并立即执行推出。
    private func handleEjectOnce(message: IPCMessage, conn: SocketConnection) {
        // 兼容两种负载形式：JSON 编码的字符串（带引号）或裸 UUID。
        guard let uuid = message.decode(as: String.self) ?? message.data, !uuid.isEmpty else {
            conn.send(IPCMessage.encode(IPCMessage.ejectResult, EjectResult(ok: false, message: "missing uuid")))
            return
        }
        lock.lock()
        temporarilyAllowed.insert(uuid)
        // 主动推出：记入豁免，磁盘消失时不会触发意外恢复。
        expectedEjects.insert(uuid)
        lock.unlock()

        // 找到对应挂载点并调用 diskutil eject；审批回调将因一次性豁免而放行。
        // 负载可能是宗卷 UUID 或挂载路径（无 UUID 的宗卷回退为路径）。
        let mount = MountEnumerator.enumerate().first { $0.id == uuid || $0.path == uuid }
        var ok = false
        var output = ""
        if let target = mount?.path ?? mount?.bsdName.map({ "/dev/\($0)" }) {
            (ok, output) = runDiskUtil(["eject", target])
        } else {
            output = "未找到挂载点"
        }

        if !ok {
            // 弹出失败则回收豁免，避免留下意外放行窗口。
            lock.lock()
            temporarilyAllowed.remove(uuid)
            expectedEjects.remove(uuid)
            lock.unlock()
        }
        conn.send(IPCMessage.encode(IPCMessage.ejectResult, EjectResult(ok: ok, message: output)))
    }

    /// 向所有已认证的前端连接广播。
    private func broadcast(_ message: IPCMessage) {
        lock.lock()
        let conns = Array(activeConnections.values)
        lock.unlock()
        for conn in conns {
            conn.send(message)
        }
    }
}

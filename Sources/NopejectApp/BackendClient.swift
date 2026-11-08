import Foundation
import NopejectCore

/// 与守护进程之间的客户端连接：后台线程上做连接、握手、消息循环与自动重连。
final class BackendClient {
    var onMessage: ((IPCMessage) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?

    private var connection: SocketConnection?
    private let lock = NSLock()
    private var stopped = false
    private var spawnCounter = 0

    /// 守护进程可执行文件路径：与前端同目录（SwiftPM .build 目录或 .app/Contents/MacOS）。
    static var daemonURL: URL? {
        Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("nopejectd")
    }

    /// 拉起守护进程（独立进程，前端退出后继续常驻）。
    static func spawnDaemon() {
        guard let url = daemonURL, FileManager.default.isExecutableFile(atPath: url.path) else { return }
        let process = Process()
        process.executableURL = url
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    func start() {
        lock.lock()
        stopped = false
        lock.unlock()
        Thread.detachNewThread { [weak self] in
            self?.runLoop()
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        let conn = connection
        lock.unlock()
        conn?.closeConnection()
    }

    var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    @discardableResult
    func send(_ message: IPCMessage) -> Bool {
        lock.lock(); let conn = connection; lock.unlock()
        return conn?.send(message) ?? false
    }

    /// 用一次性连接向守护进程发送 shutdown（用于强制重启/完全退出）。
    static func sendShutdownOnce() {
        let secret = SecureChannel.loadOrCreateSecret()
        let fd = UnixSocketConnector.connect(path: SecureChannel.socketPath(), timeout: 2)
        guard fd >= 0 else { return }
        let conn = SocketConnection(fd: fd)
        conn.setReadTimeout(3)
        guard let challenge = conn.receive(), challenge.action == IPCMessage.challenge,
              let nonce = challenge.data,
              conn.send(IPCMessage(action: IPCMessage.proof, data: SecureChannel.proof(secret: secret, nonce: nonce))),
              let reply = conn.receive(), reply.action == IPCMessage.authOk else { return }
        conn.send(IPCMessage(action: IPCMessage.shutdown))
        _ = conn.receive() // shutdownNotice 或对端关闭
    }

    // MARK: - 私有

    private func runLoop() {
        let secret = SecureChannel.loadOrCreateSecret()
        while !isStopped {
            let fd = UnixSocketConnector.connect(path: SecureChannel.socketPath(), timeout: 2)
            guard fd >= 0 else {
                // 连不上：前两次静默重试，第三次尝试拉起守护进程
                // （幂等：已有实例时新实例会探测到存活 socket 而自行退出）。
                spawnCounter += 1
                if spawnCounter >= 3 {
                    spawnCounter = 0
                    Self.spawnDaemon()
                }
                sleep(2)
                continue
            }
            spawnCounter = 0

            let conn = SocketConnection(fd: fd)
            conn.setReadTimeout(5)

            // 挑战-应答握手。
            guard let challenge = conn.receive(), challenge.action == IPCMessage.challenge,
                  let nonce = challenge.data,
                  conn.send(IPCMessage(
                      action: IPCMessage.proof,
                      data: SecureChannel.proof(secret: secret, nonce: nonce)
                  )),
                  let authReply = conn.receive(), authReply.action == IPCMessage.authOk else {
                sleep(2)
                continue
            }

            conn.setReadTimeout(0)
            lock.lock()
            connection = conn
            lock.unlock()
            onConnected?()

            // 消息循环：断开（包括前端单独休眠时的 socket 错误）都只触发重连逻辑，
            // 守护进程侧独立运行不受影响。
            while !isStopped, let message = conn.receive() {
                onMessage?(message)
            }

            lock.lock()
            connection = nil
            lock.unlock()
            if isStopped { break }
            onDisconnected?()
            sleep(2)
        }
    }
}

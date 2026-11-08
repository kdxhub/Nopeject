import Foundation

/// Unix domain socket 服务端：串行 accept 循环，每条连接由 handler 同步处理。
public final class UnixSocketServer {
    public typealias Handler = (Int32) -> Void

    private let path: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "nopeject.ipc.server")
    private var listenFD: Int32 = -1

    public init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .ENOSYS)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw POSIXError(POSIXErrorCode.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            dest.baseAddress!.copyMemory(from: pathBytes, byteCount: pathBytes.count)
        }

        // 先探测是否已有存活实例：socket 能连上说明已有守护进程在监听。
        // 此时绝不能 unlink 抢占——否则第二个实例会顶掉旧实例的 socket 路径，
        // 导致两个进程同时注册卸载审批回调、旧实例与前端失联。直接报错退出。
        let probe = UnixSocketConnector.connect(path: path, timeout: 1)
        if probe >= 0 {
            close(probe)
            throw POSIXError(.EADDRINUSE)
        }
        // 探测失败：socket 文件要么不存在，要么是残留的死文件（旧实例已退出），
        // 此时 unlink 是安全的。
        unlink(path)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .ENOSYS)
        }
        // 仅属主可连接。
        chmod(path, 0o600)
        guard listen(fd, 4) == 0 else {
            let code = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .ENOSYS)
        }
        listenFD = fd
        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    public func stop() {
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(path)
    }

    // MARK: - 私有

    private func acceptLoop() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            guard clientFD >= 0 else {
                if errno == EINTR { continue }
                return
            }
            // 对端已关闭时写 socket 会触发 SIGPIPE 杀死进程；socket 层面禁掉。
            var nosigpipe: Int32 = 1
            setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
            // 每条连接在独立队列上处理完整生命周期（含握手与消息循环），
            // 避免一个长连接阻塞后续连接（前端重连、多客户端等场景）。
            DispatchQueue.global(qos: .userInitiated).async { [handler] in
                handler(clientFD)
            }
        }
    }
}

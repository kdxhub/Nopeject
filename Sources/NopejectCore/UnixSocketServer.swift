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
            // 每条连接在独立队列上处理完整生命周期（含握手与消息循环），
            // 避免一个长连接阻塞后续连接（前端重连、多客户端等场景）。
            DispatchQueue.global(qos: .userInitiated).async { [handler] in
                handler(clientFD)
            }
        }
    }
}

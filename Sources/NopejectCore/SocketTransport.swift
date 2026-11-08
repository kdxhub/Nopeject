import Foundation

/// 基于 POSIX Unix domain socket 的连接封装：JSON 行协议（一行一条 IPCMessage）。
public final class SocketConnection {
    public let fd: Int32
    private var buffer = Data()

    public init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        if fd >= 0 { close(fd) }
    }

    /// 设置读超时（秒）；传 0 表示恢复阻塞模式。
    public func setReadTimeout(_ seconds: TimeInterval) {
        var tv = timeval()
        if seconds > 0 {
            tv.tv_sec = Int(seconds)
            tv.tv_usec = Int32((seconds - Double(Int(seconds))) * 1_000_000)
        }
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// 发送一条消息（序列化失败返回 false）。
    @discardableResult
    public func send(_ message: IPCMessage) -> Bool {
        guard let data = message.serialized() else { return false }
        return data.withUnsafeBytes { raw in
            var offset = 0
            while offset < data.count {
                let n = write(fd, raw.baseAddress!.advanced(by: offset), data.count - offset)
                if n <= 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += n
            }
            return true
        }
    }

    /// 阻塞读取一条消息；对端关闭或出错返回 nil。
    public func receive() -> IPCMessage? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                if line.isEmpty { continue }
                return IPCMessage.deserialize(from: line)
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 {
                if n < 0 && errno == EINTR { continue }
                return nil
            }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }

    /// 主动关闭连接。
    public func closeConnection() {
        if fd >= 0 { close(fd) }
    }
}

/// 与守护进程建立连接的客户端连接器（阻塞式，供调用方在自己的线程上使用）。
public enum UnixSocketConnector {
    /// 连接到指定 socket 路径，失败返回 -1。
    public static func connect(path: String, timeout: TimeInterval = 3) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }

        // 读超时，防止连接后悬挂。
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            return -1
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            dest.baseAddress!.copyMemory(from: pathBytes, byteCount: pathBytes.count)
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            return -1
        }
        return fd
    }

    /// 校验 fd 对端 uid 是否与本进程一致。
    public static func checkPeerIsSameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }
}

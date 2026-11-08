import Foundation

/// IPC 安全通道：
///
/// 安全模型（经得起代码审计的本地 IPC）：
/// 1. Unix domain socket 固定路径，socket 文件与所在目录均为 0600/0700，其他用户无法触达；
/// 2. 连接建立后通过 `getpeereid` 校验对端 uid 必须与本进程一致（防同机其他用户）；
/// 3. 共享密钥（首次运行生成的 256-bit 随机值，文件 0600）+ HMAC-SHA256 挑战-应答握手，
///    防止同用户下被劫持/重放（每次 nonce 均为一次性随机值）；
/// 4. 应答比较采用常数时间比较，抗时序侧信道。
///
/// 宿主 App 进程为守护进程拉起时天然继承同一用户；同用户下的其他 App 即使知道 socket
/// 路径，也无法读取 0600 的密钥文件（macOS 沙盒/TCC 进一步限制读取他人数据目录）。
public enum SecureChannel {
    /// 密钥文件路径。
    public static func secretFileURL() -> URL {
        appSupportURL().appendingPathComponent("ipc.secret")
    }

    /// socket 文件路径。
    public static func socketPath() -> String {
        appSupportURL().appendingPathComponent("ipc.sock").path
    }

    /// 共享数据目录（0700）。
    @discardableResult
    public static func appSupportURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nopeject", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return base
    }

    /// 读取共享密钥，不存在则生成 32 字节随机十六进制并落盘（0600）。
    public static func loadOrCreateSecret() -> String {
        let url = secretFileURL()
        if let data = try? Data(contentsOf: url),
           let existing = String(data: data, encoding: .utf8),
           existing.count >= 64 {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        if result != errSecSuccess {
            for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        try? Data(hex.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return hex
    }

    /// 计算 HMAC-SHA256(secret, nonce) 的十六进制应答。
    public static func proof(secret: String, nonce: String) -> String {
        let mac = HMACSHA256.authenticationCode(
            message: Array(nonce.utf8),
            key: Array(secret.utf8)
        )
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// 常数时间比较应答。
    public static func verify(secret: String, nonce: String, proof candidate: String) -> Bool {
        let expected = proof(secret: secret, nonce: nonce)
        let a = Array(expected.utf8)
        let b = Array(candidate.utf8)
        guard a.count == b.count, !a.isEmpty else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}

import Foundation

/// 管理员密码验证：通过系统授权对话框（osascript with administrator privileges）。
/// 「编辑需要权限」「始终需要权限」两种模式的切换与生效均依赖它。
enum AdminAuth {
    /// 弹出系统管理员授权对话框，返回用户是否通过验证。
    static func requireAdmin(reason: String? = nil) async -> Bool {
        let prompt = reason ?? L10n.t("auth.prompt")
        let escaped = prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"true\" with administrator privileges with prompt \"\(escaped)\""

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

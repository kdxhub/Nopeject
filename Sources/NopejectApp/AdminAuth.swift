import Foundation
import LocalAuthentication

/// 管理员身份验证：使用 LocalAuthentication（触控 ID / 登录密码）。
/// 系统认证界面异步弹出，验证期间应用 UI 保持响应；
/// 「编辑需要权限」「始终需要权限」两种模式的切换与生效均依赖它。
enum AdminAuth {
    /// 发起系统身份验证，返回用户是否通过验证。
    static func requireAdmin(reason: String? = nil) async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            FileHandle.standardError.write(
                Data("Nopeject: 无法评估身份验证策略: \(error?.localizedDescription ?? "unknown")\n".utf8)
            )
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason ?? L10n.t("auth.prompt")
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

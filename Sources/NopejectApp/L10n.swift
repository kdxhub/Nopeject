import Foundation

/// 本地化辅助。语言资源位于 Bundle.module 的 .lproj 中。
enum L10n {
    static func t(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }

    static func tf(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}

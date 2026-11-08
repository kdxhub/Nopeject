import Foundation

/// 本地化辅助。
///
/// 不依赖 Bundle 的自动语言匹配：SwiftPM 会把 `zh-Hans.lproj` 规范化为小写
/// `zh-hans.lproj`，导致 Bundle 的本地化匹配失败（preferredLocalizations 只剩 en，
/// 中文系统显示英文）。这里显式按系统首选语言加载对应 .strings 并解析为字典。
enum L10n {
    /// 已解析的键值表；按系统语言一次性加载。
    private static let table: [String: String] = loadTable()

    static func t(_ key: String) -> String {
        table[key] ?? fallbackValue(forKey: key)
    }

    static func tf(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    // MARK: - 私有

    /// 系统首选语言 → 资源包语言标识。
    private static var preferredLocalization: String {
        if Locale.preferredLanguages.contains(where: { $0.lowercased().hasPrefix("zh") }) {
            return "zh-Hans"
        }
        return "en"
    }

    private static func loadTable() -> [String: String] {
        let order = [preferredLocalization, "zh-Hans", "en"]
        for lang in order {
            if let dict = stringsDict(forLocalization: lang) {
                return dict
            }
        }
        return [:]
    }

    /// 从资源包读取指定语言的 Localizable.strings 并解析为字典。
    private static func stringsDict(forLocalization lang: String) -> [String: String]? {
        guard let path = Bundle.module.path(
            forResource: "Localizable",
            ofType: "strings",
            inDirectory: nil,
            forLocalization: lang
        ), let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        // .strings 在资源包内为二进制/ASCII plist 格式。
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: String] else {
            return nil
        }
        return plist
    }

    /// 兜底：走系统匹配（表加载失败时），再兜底显示键名。
    private static func fallbackValue(forKey key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }
}

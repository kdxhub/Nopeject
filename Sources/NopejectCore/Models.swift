import Foundation

/// 一个挂载点的完整描述。
public struct MountPoint: Codable, Equatable, Hashable, Identifiable {
    /// 宗卷 UUID（由 DiskArbitration 提供），不可用时回退为路径。
    public var id: String { uuid ?? path }
    public var uuid: String?
    public var name: String
    public var path: String
    /// 挂载点类型原始值：internal / external / network
    public var kindRaw: String
    public var totalBytes: Int64
    public var freeBytes: Int64
    /// 对应的 BSD 设备名（如 disk4s1），用于临时弹出。
    public var bsdName: String?
    public var isEjectable: Bool

    public init(
        uuid: String?, name: String, path: String, kindRaw: String,
        totalBytes: Int64, freeBytes: Int64, bsdName: String?, isEjectable: Bool
    ) {
        self.uuid = uuid
        self.name = name
        self.path = path
        self.kindRaw = kindRaw
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.bsdName = bsdName
        self.isEjectable = isEjectable
    }
}

/// 守护进程持久化的配置（保护列表以 UUID 记录，重启后依然生效）。
/// 权限控制从旧版单一 permissionMode 细分为按操作独立的开关。
public struct NopejectConfig: Codable, Equatable {
    public var protectedUUIDs: [String]
    public var protectedNames: [String: String]
    /// 打开前端界面需要密码验证。
    public var requireAuthOpenUI: Bool
    /// 编辑保护状态（切换开关）需要密码验证。
    public var requireAuthEdit: Bool
    /// 使用临时推出功能需要密码验证。
    public var requireAuthTemporaryEject: Bool
    /// 完全退出（停止后台保护）需要密码验证。
    public var requireAuthQuit: Bool
    /// 受保护磁盘被意外推出后尝试重新挂载并通知结果。
    public var remountAfterUnexpectedEject: Bool

    enum CodingKeys: String, CodingKey {
        case protectedUUIDs, protectedNames
        case requireAuthOpenUI, requireAuthEdit, requireAuthTemporaryEject, requireAuthQuit
        case remountAfterUnexpectedEject
        /// 旧版配置的权限模式键（仅用于迁移）。
        case permissionMode
    }

    public init(
        protectedUUIDs: [String] = [],
        protectedNames: [String: String] = [:],
        requireAuthOpenUI: Bool = false,
        requireAuthEdit: Bool = false,
        requireAuthTemporaryEject: Bool = false,
        requireAuthQuit: Bool = false,
        remountAfterUnexpectedEject: Bool = false
    ) {
        self.protectedUUIDs = protectedUUIDs
        self.protectedNames = protectedNames
        self.requireAuthOpenUI = requireAuthOpenUI
        self.requireAuthEdit = requireAuthEdit
        self.requireAuthTemporaryEject = requireAuthTemporaryEject
        self.requireAuthQuit = requireAuthQuit
        self.remountAfterUnexpectedEject = remountAfterUnexpectedEject
    }

    /// 兼容旧版配置：无新开关字段时按 permissionMode 映射
    /// （none → 全关；requireForEdit → 编辑开；always → 全开）。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protectedUUIDs = try container.decodeIfPresent([String].self, forKey: .protectedUUIDs) ?? []
        protectedNames = try container.decodeIfPresent([String: String].self, forKey: .protectedNames) ?? [:]

        if let openUI = try container.decodeIfPresent(Bool.self, forKey: .requireAuthOpenUI) {
            requireAuthOpenUI = openUI
            requireAuthEdit = try container.decodeIfPresent(Bool.self, forKey: .requireAuthEdit) ?? false
            requireAuthTemporaryEject = try container.decodeIfPresent(Bool.self, forKey: .requireAuthTemporaryEject) ?? false
            requireAuthQuit = try container.decodeIfPresent(Bool.self, forKey: .requireAuthQuit) ?? false
        } else {
            switch try? container.decodeIfPresent(String.self, forKey: .permissionMode) {
            case "always":
                requireAuthOpenUI = true
                requireAuthEdit = true
                requireAuthTemporaryEject = true
                requireAuthQuit = true
            case "requireForEdit":
                requireAuthOpenUI = false
                requireAuthEdit = true
                requireAuthTemporaryEject = false
                requireAuthQuit = false
            default:
                requireAuthOpenUI = false
                requireAuthEdit = false
                requireAuthTemporaryEject = false
                requireAuthQuit = false
            }
        }

        remountAfterUnexpectedEject = try container.decodeIfPresent(Bool.self, forKey: .remountAfterUnexpectedEject) ?? false
    }

    /// 只编码当前字段，旧版 permissionMode 键不再写出。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protectedUUIDs, forKey: .protectedUUIDs)
        try container.encode(protectedNames, forKey: .protectedNames)
        try container.encode(requireAuthOpenUI, forKey: .requireAuthOpenUI)
        try container.encode(requireAuthEdit, forKey: .requireAuthEdit)
        try container.encode(requireAuthTemporaryEject, forKey: .requireAuthTemporaryEject)
        try container.encode(requireAuthQuit, forKey: .requireAuthQuit)
        try container.encode(remountAfterUnexpectedEject, forKey: .remountAfterUnexpectedEject)
    }

    public var isProtectedSet: Set<String> { Set(protectedUUIDs) }
}

/// 人类可读的容量格式化。
public enum CapacityFormatter {
    public static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

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

/// 权限模式：
/// - none            「无」：不启用权限保护
/// - requireForEdit  「编辑需要权限」：进入编辑（切换开关）前需要验证一次管理员密码，保存后重置
/// - always          「始终需要权限」：每次编辑操作、查看编辑内容均需验证
public enum PermissionMode: String, Codable, CaseIterable {
    case none
    case requireForEdit
    case always
}

/// 守护进程持久化的配置（保护列表以 UUID 记录，重启后依然生效）。
public struct NopejectConfig: Codable, Equatable {
    public var protectedUUIDs: [String]
    public var protectedNames: [String: String]
    public var permissionMode: PermissionMode

    public init(
        protectedUUIDs: [String] = [],
        protectedNames: [String: String] = [:],
        permissionMode: PermissionMode = .none
    ) {
        self.protectedUUIDs = protectedUUIDs
        self.protectedNames = protectedNames
        self.permissionMode = permissionMode
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

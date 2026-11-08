import Foundation
import Darwin
import DiskArbitration

/// 挂载点枚举器：枚举当前用户会话可见的可浏览宗卷，并补充 DiskArbitration 提供的 UUID。
public enum MountEnumerator {
    public static func enumerate() -> [MountPoint] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsInternalKey,
            .volumeIsBrowsableKey,
            .volumeIsEjectableKey,
            .volumeIsRemovableKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return [] }

        return urls.compactMap { url -> MountPoint? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            guard values.volumeIsBrowsable ?? false else { return nil }

            let path = url.path
            let fs = statfsStruct(forPath: path)
            let isNetwork = ((fs?.f_flags ?? 0) & UInt32(truncatingIfNeeded: MNT_LOCAL)) == 0

            let bsdName = fs.map { fsValue -> String in
                let raw = withUnsafeBytes(of: fsValue.f_mntfromname) { buffer -> String in
                    let bytes = buffer.prefix { $0 != 0 }
                    return String(decoding: bytes, as: UTF8.self)
                }
                return raw
            }
            .flatMap { bsd -> String? in
                // /dev/disk4s1 -> disk4s1
                bsd.hasPrefix("/dev/") ? String(bsd.dropFirst(5)) : bsd
            }
            let info = volumeInfo(bsdName: bsdName)

            let kindRaw: String
            if isNetwork {
                kindRaw = "network"
            } else if info.deviceProtocol == "Virtual Interface" {
                // dmg / ramdisk 等磁盘映像：DA 协议为 Virtual Interface，
                // 资源管理器却把 volumeIsInternal 报成 false，需在物理盘判断前甄别。
                kindRaw = "virtual"
            } else if values.volumeIsInternal ?? false {
                kindRaw = "internal"
            } else {
                kindRaw = "external"
            }

            let ejectable = (values.volumeIsEjectable ?? false)
                || (values.volumeIsRemovable ?? false)
                || kindRaw == "external"
                || kindRaw == "virtual"

            // 内置且不可弹出的宗卷（如 Macintosh HD 系统盘、内置数据卷）本就无法推出，
            // 不纳入可保护列表。
            guard kindRaw != "internal" || ejectable else { return nil }

            // 可用空间以 statfs 为准：volumeAvailableCapacityForImportantUsageKey
            // 在 Time Machine 目标宗卷等场景会返回 0，statfs 的 f_bavail 与 df 一致。
            let blockSize = Int64(fs?.f_bsize ?? 0)
            let freeBytes = (fs.map { Int64($0.f_bavail) * blockSize }) ?? (values.volumeAvailableCapacityForImportantUsage ?? 0)
            let totalBytes = (fs.map { Int64($0.f_blocks) * blockSize })
                .flatMap { $0 > 0 ? $0 : nil }
                ?? Int64(values.volumeTotalCapacity ?? 0)

            return MountPoint(
                uuid: info.uuid,
                name: values.volumeName ?? url.lastPathComponent,
                path: path,
                kindRaw: kindRaw,
                totalBytes: totalBytes,
                freeBytes: freeBytes,
                bsdName: bsdName,
                isEjectable: ejectable
            )
        }
    }

    /// 给定文件系统路径，找到其所属挂载点（最长前缀匹配）。
    public static func mountPoint(containing path: String) -> MountPoint? {
        let standardizing = URL(fileURLWithPath: path).standardizedFileURL.path
        var best: MountPoint?
        var bestLength = -1
        for mount in enumerate() {
            let root = mount.path.hasSuffix("/") ? mount.path : mount.path + "/"
            if standardizing == mount.path || standardizing.hasPrefix(root) {
                if mount.path.count > bestLength {
                    best = mount
                    bestLength = mount.path.count
                }
            }
        }
        return best
    }

    // MARK: - 私有

    private static func statfsStruct(forPath path: String) -> statfs? {
        var fs = statfs()
        let result = path.withCString { statfs($0, &fs) }
        return result == 0 ? fs : nil
    }

    /// 通过 DiskArbitration 由 BSD 设备名取得宗卷 UUID 与设备协议。
    /// 协议用于甄别虚拟磁盘（磁盘映像为 "Virtual Interface"，物理盘为 "USB" 等）。
    private static func volumeInfo(bsdName: String?) -> (uuid: String?, deviceProtocol: String?) {
        guard let bsdName else { return (nil, nil) }
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return (nil, nil) }
        defer { _ = session } // ARC
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, "/dev/\(bsdName)"),
              let desc = DADiskCopyDescription(disk) as? [String: Any] else {
            return (nil, nil)
        }
        let uuid = desc[kDADiskDescriptionVolumeUUIDKey as String]
            .map { unsafeDowncast($0 as AnyObject, to: CFUUID.self) }
            .map { CFUUIDCreateString(kCFAllocatorDefault, $0) as String }
        let protocol_ = desc[kDADiskDescriptionDeviceProtocolKey as String] as? String
        return (uuid, protocol_)
    }
}

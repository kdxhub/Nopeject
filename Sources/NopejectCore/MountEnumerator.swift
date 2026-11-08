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

            let kindRaw: String
            if isNetwork {
                kindRaw = "network"
            } else if values.volumeIsInternal ?? false {
                kindRaw = "internal"
            } else {
                kindRaw = "external"
            }

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
            let uuid = volumeUUID(bsdName: bsdName)

            return MountPoint(
                uuid: uuid,
                name: values.volumeName ?? url.lastPathComponent,
                path: path,
                kindRaw: kindRaw,
                totalBytes: Int64(values.volumeTotalCapacity ?? 0),
                freeBytes: values.volumeAvailableCapacityForImportantUsage ?? 0,
                bsdName: bsdName,
                isEjectable: (values.volumeIsEjectable ?? false) || (values.volumeIsRemovable ?? false) || kindRaw == "external"
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

    /// 通过 DiskArbitration 由 BSD 设备名取得宗卷 UUID。
    private static func volumeUUID(bsdName: String?) -> String? {
        guard let bsdName else { return nil }
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
        defer { _ = session } // ARC
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, "/dev/\(bsdName)"),
              let desc = DADiskCopyDescription(disk) as? [String: Any],
              let cfuuid = desc[kDADiskDescriptionVolumeUUIDKey as String].map({ unsafeDowncast($0 as AnyObject, to: CFUUID.self) }) else {
            return nil
        }
        return CFUUIDCreateString(kCFAllocatorDefault, cfuuid) as String?
    }
}

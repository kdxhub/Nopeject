import Foundation
import DiskArbitration

/// 守护进程配置仓库：UserDefaults（suite）持久化，重启后依然生效。
public final class ConfigStore {
    private let defaults: UserDefaults
    private let key = "nopeject.config.v1"
    private let lock = NSLock()
    private var cached: NopejectConfig

    public init(suiteName: String = "com.neonai.nopeject") {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(NopejectConfig.self, from: data) {
            cached = decoded
        } else {
            cached = NopejectConfig()
        }
    }

    public var current: NopejectConfig {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    public func update(_ newConfig: NopejectConfig) {
        lock.lock()
        cached = newConfig
        let data = try? JSONEncoder().encode(newConfig)
        lock.unlock()
        if let data {
            defaults.set(data, forKey: key)
        }
    }
}

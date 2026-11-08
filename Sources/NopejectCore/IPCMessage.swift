import Foundation

/// IPC 消息：JSON 行协议，一行一条消息。
/// `action` 标识消息类型；`data` 为该类型对应载荷的 JSON 字符串。
public struct IPCMessage: Codable, Equatable {
    public var action: String
    public var data: String?

    public init(action: String, data: String? = nil) {
        self.action = action
        self.data = data
    }

    // MARK: - 动作常量

    public static let hello = "hello"
    public static let challenge = "challenge"
    public static let proof = "proof"
    public static let authOk = "authOk"
    public static let authFail = "authFail"
    public static let getMountPoints = "getMountPoints"
    public static let mountPoints = "mountPoints"
    public static let getConfig = "getConfig"
    public static let config = "config"
    public static let setConfig = "setConfig"
    public static let configSaved = "configSaved"
    public static let blocked = "blocked"
    public static let ejectOnce = "ejectOnce"
    public static let ejectResult = "ejectResult"
    public static let remountResult = "remountResult"
    public static let shutdown = "shutdown"
    public static let ping = "ping"
    public static let pong = "pong"

    // MARK: - 编解码辅助

    public static func encode<T: Encodable>(_ action: String, _ payload: T) -> IPCMessage {
        guard let data = try? JSONEncoder().encode(payload),
              let string = String(data: data, encoding: .utf8) else {
            return IPCMessage(action: action, data: nil)
        }
        return IPCMessage(action: action, data: string)
    }

    public func decode<T: Decodable>(as type: T.Type) -> T? {
        guard let data, let jsonData = data.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: jsonData)
    }

    /// 序列化为一行（含换行符）。
    public func serialized() -> Data? {
        guard let json = try? JSONEncoder().encode(self) else { return nil }
        return json + Data([0x0A])
    }

    public static func deserialize(from line: Data) -> IPCMessage? {
        guard let json = try? JSONDecoder().decode(IPCMessage.self, from: line) else { return nil }
        return json
    }
}

/// 拦截事件载荷（daemon → 前端）。
public struct BlockedEvent: Codable, Equatable {
    public var volumeName: String
    public var uuid: String?
    public var path: String?

    public init(volumeName: String, uuid: String?, path: String?) {
        self.volumeName = volumeName
        self.uuid = uuid
        self.path = path
    }
}

/// 临时弹出结果载荷。
public struct EjectResult: Codable, Equatable {
    public var ok: Bool
    public var message: String

    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }
}

/// 意外推出后重新挂载的结果载荷（daemon → 前端）。
public struct RemountResult: Codable, Equatable {
    public var ok: Bool
    public var volumeName: String

    public init(ok: Bool, volumeName: String) {
        self.ok = ok
        self.volumeName = volumeName
    }
}

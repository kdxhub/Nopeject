import Foundation
import CoreFoundation
import NopejectCore

// 忽略 SIGPIPE：向已断开的 IPC socket 写入（如握手失败回写 authFail）绝不能杀死进程。
signal(SIGPIPE, SIG_IGN)

let daemon = NopejectDaemon()
daemon.run()

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nopeject",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Nopeject", targets: ["NopejectApp"]),
        .executable(name: "nopejectd", targets: ["NopejectDaemon"]),
        .library(name: "NopejectCore", targets: ["NopejectCore"])
    ],
    targets: [
        // 共享核心：数据模型、IPC 协议、安全通道、挂载点枚举
        .target(
            name: "NopejectCore",
            path: "Sources/NopejectCore"
        ),
        // 后端守护进程：DiskArbitration 推出拦截 + IPC 服务端
        .executableTarget(
            name: "NopejectDaemon",
            dependencies: ["NopejectCore"],
            path: "Sources/NopejectDaemon"
        ),
        // 前端菜单栏应用
        .executableTarget(
            name: "NopejectApp",
            dependencies: ["NopejectCore"],
            path: "Sources/NopejectApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)

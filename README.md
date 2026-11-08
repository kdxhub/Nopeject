# Nopeject

Nopeject 是一个轻量级 macOS 菜单栏应用，通过系统回调阻止直接弹出特定宗卷、虚拟磁盘等挂载点。

> 本项目与 Noject 没有任何从属关系或关联，亦与其开发者 ScaleNinja 无关。

## 功能

* 极其轻量的 App，没有多余功能——遥测、借钱、短视频……
* 服务分离，退出 GUI 也不影响拦截
* 双击即用、快速配置
* 拦截成功进行通知
* 完全开源免费

## 实现原理

Nopeject 将在后台启动一个守护服务（`nopejectd`），通过相关系统 API 阻止推出操作，同时与前端进程相通信。

### 架构

```
┌────────────────────────┐        Unix Domain Socket         ┌────────────────────────┐
│  Nopeject（前端）       │  ── HMAC-SHA256 挑战-应答 →         │  nopejectd（后端）      │
│  菜单栏 MenuBarExtra    │  ← JSON 行协议          ──         │  DiskArbitration 拦截   │
│  SwiftUI + 液态玻璃     │                                   │  UserDefaults 持久化    │
└────────────────────────┘                                   └────────────────────────┘
```

* **前端**：注册菜单栏图标，展开后显示可配置挂载点列表。每个条目左侧为系统原生宗卷图标，右侧为加粗挂载点名称 + 淡化的「类型 · 位置 · 容量」第二行，最右为开关（开启 = 阻止推出）。编辑配置后出现保存按钮，保存成功播放动画并变为苹果风格「✓ 已保存」。右键条目可「临时弹出」或「在访达中显示」。macOS 26+ 自动启用液态玻璃效果，低版本回退为高斯模糊（`ultraThinMaterial`）。
* **后端**：调用 `DARegisterDiskUnmountApprovalCallback` 注册卸载审批回调；回调中经 `DADiskCopyDescription` 取得宗卷 UUID（`kDADiskDescriptionVolumeUUIDKey`）与保护列表比对，命中则构造 `DADissenter`（`kDAReturnNotPermitted`）拒绝推出，否则放行。保护列表以 UUID 存入 UserDefaults，重启后依然生效。
* **通信**：Unix domain socket + JSON 行协议。后端与前端断连时**不报错、不退出、不终止**——前端可以单独退出，后端继续独立承担拦截职责。拦截成功后尝试连接前端广播事件，未连接则静默忽略。

### 安全模型

1. socket 固定路径（`~/Library/Application Support/Nopeject/ipc.sock`），文件 0600、目录 0700，其他用户无法触达；
2. 握手前经 `getpeereid` 校验对端 uid 与本进程一致；
3. 共享密钥为首次运行生成的 256-bit 随机值（文件 0600），握手采用一次性 nonce 的 HMAC-SHA256 挑战-应答，抗重放；
4. 应答比较为常数时间实现，抗时序侧信道；SHA-256/HMAC 为本项目内纯 Swift 实现，零外部依赖、便于审计。

### 权限与安全性

提供「无」「编辑需要权限」「始终需要权限」三种模式：

* **无**：不启用权限保护；
* **编辑需要权限**：进入编辑（切换保护开关）前需验证一次管理员密码，保存后验证状态重置；
* **始终需要权限**：每次编辑操作、查看编辑内容均需验证管理员密码。

### 系统能力

* **开机自启动**：macOS 13+ 使用 `SMAppService.mainApp.register()`；
* **后台运行**：`LSUIElement` 菜单栏应用，后端为独立常驻进程；
* **访达快捷操作**：通过 NSServices 接收访达所选目录，判断其所在挂载点并在菜单中高亮提示；
* **通知**：首次打开 App 即申请通知权限；拦截成功立即通知用户。

## 构建

依赖：Swift 5.9+ 工具链（Xcode 26 可编译 LiquidGlass 路径，旧工具链自动降级为高斯模糊）。

```bash
swift build                 # Debug 构建
swift build -c release      # Release 构建
bash scripts/make-app.sh    # 打包 dist/Nopeject.app
```

## 技术栈

* Swift 6 / SwiftUI / AppKit（MenuBarExtra、NSWorkspace、SMAppService、UNUserNotificationCenter）
* DiskArbitration（推出拦截、挂载点枚举、宗卷 UUID）
* POSIX Unix Domain Socket（本地 IPC）
* SwiftPM 构建，零第三方依赖

## 许可证

[MIT](LICENSE)
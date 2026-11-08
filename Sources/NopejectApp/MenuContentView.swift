import SwiftUI
import AppKit
import NopejectCore

/// 菜单主内容：顶部项目名 + 后端状态点、挂载点列表、底部状态与“…”二级菜单。
/// 面板高度由当前页面的自然高度驱动（fixedSize 测量，避免约束回环），
/// 高度变化（列表增减、页面切换）统一走弹簧动画，窗口随之平滑伸缩。
struct MenuContentView: View {
    @ObservedObject private var state = AppState.shared
    @State private var listContentHeight: CGFloat = 0
    /// 当前页面自然高度（nil = 尚未完成首次布局，不参与动画）。
    @State private var panelHeight: CGFloat?
    /// 各挂载点行在窗口坐标（SwiftUI global，原点左上）中的 frame。
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var rightClickMonitor: Any?

    var body: some View {
        Group {
            if state.isUILocked {
                lockScreen.transition(.opacity)
            } else {
                switch state.screen {
                case .main: mainScreen.transition(.opacity)
                case .preferences: PreferencesScreen().transition(.opacity)
                case .about: AboutScreen().transition(.opacity)
                }
            }
        }
        // fixedSize 让内部始终以自然高度布局：外层 frame 动画不会反过来
        // 压缩内容，测量值永远真实，高度动画不会出现回环。
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { proxy in
            proxy.size.height
        }, action: { newValue in
            if panelHeight == nil {
                // 首次布局直接落位，避免打开菜单时内容从零飘入。
                panelHeight = newValue
            } else {
                withAnimation(.spring(duration: 0.35)) {
                    panelHeight = newValue
                }
            }
        })
        .frame(height: panelHeight)
        .clipped()
        .frame(width: 380)
        .animation(.spring(duration: 0.35), value: state.screen)
        .onAppear {
            state.refresh()
            installRightClickMonitor()
            // 每次打开面板都从锁定状态开始（模仿老版 macOS，验证后解锁直至面板关闭）。
            state.isUnlocked = false
        }
        // 界面关闭后重新锁上，下次打开需重新验证。
        .onDisappear {
            state.isUnlocked = false
        }
        .nopejectPanelBackground()
    }

    // MARK: - 界面锁定

    /// 「打开界面需要密码」开启且未验证时显示的锁定页：隐藏全部内容，仅提供验证入口。
    private var lockScreen: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            Text(L10n.t("lock.title"))
                .font(.headline)
            Text(L10n.t("lock.text"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.t("lock.verify")) {
                Task { await state.toggleLock() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
    }

    // MARK: - 主界面

    /// 列表区域的最大高度：整体面板不超过屏幕可视高度的 45%。
    /// 内容不超过该值时窗口随内容自动拉高，超出后才出现滚动。
    private var maxListHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return max(160, screenHeight * 0.45 - 110)
    }

    private var mountList: some View {
        VStack(spacing: 0) {
            ForEach(state.mountPoints) { mount in
                MountPointRow(mount: mount)
                    .background(
                        // 记录每行在窗口坐标中的位置，供右键事件命中判定使用。
                        Color.clear
                            .onGeometryChange(for: CGRect.self, of: { proxy in
                                proxy.frame(in: .global)
                            }, action: { newFrame in
                                rowFrames[mount.id] = newFrame
                            })
                    )
                if mount.id != state.mountPoints.last?.id {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .padding(.vertical, 4)
        .onGeometryChange(for: CGFloat.self, of: { proxy in
            proxy.size.height
        }, action: { newValue in
            if listContentHeight == 0 {
                // 首次布局直接落位，避免打开菜单时内容从零飘入。
                listContentHeight = newValue
            } else {
                // 内容高度变化（挂载点增减、窗口拉高）统一走弹簧动画。
                withAnimation(.spring(duration: 0.35)) {
                    listContentHeight = newValue
                }
            }
        })
    }

    private var mainScreen: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 8)

            if state.mountPoints.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(state.backendRunning ? L10n.t("list.empty") : L10n.t("list.disconnected"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if listContentHeight > maxListHeight {
                ScrollView {
                    mountList
                }
                .frame(height: maxListHeight)
            } else {
                mountList
            }

            Divider().padding(.horizontal, 8)
            footer
        }
        .animation(.spring(duration: 0.35), value: state.mountPoints.count)
        .animation(.spring(duration: 0.35), value: listContentHeight > maxListHeight)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.tint)
            Text("Nopeject")
                .font(.headline)
            Spacer()
            Circle()
                .fill(state.backendRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(state.backendRunning ? L10n.t("status.running") : L10n.t("status.stopped"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if state.hasAuthSwitches {
                LockIconButton()
            }
            if state.saveState == .saved {
                // 保存成功的瞬时反馈（自动保存后短暂显示）。
                Label("\(L10n.t("menu.saved"))", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else if let message = state.statusMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            moreMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.25), value: state.saveState)
    }

    private var moreMenu: some View {
        Menu {
            Button {
                state.restartBackend()
            } label: {
                Label(L10n.t("menu.restartService"), systemImage: "arrow.clockwise")
            }

            Button {
                state.screen = .preferences
            } label: {
                Label(L10n.t("menu.security"), systemImage: "gearshape")
            }

            Button {
                state.screen = .about
            } label: {
                Label(L10n.t("menu.about"), systemImage: "info.circle")
            }

            Divider()

            Menu {
                // 始终禁用的说明项。
                Button(L10n.t("menu.sponsor.note")) {}
                    .disabled(true)
                Button {
                    NSWorkspace.shared.open(AppState.sponsorURL)
                } label: {
                    Label(L10n.t("menu.sponsor.blog"), systemImage: "heart.circle")
                }
            } label: {
                Label(L10n.t("menu.sponsor"), systemImage: "heart")
            }

            Divider()

            Button {
                Task { await state.quitAll() }
            } label: {
                Label(L10n.t("menu.quitAll"), systemImage: "power")
            }

            Button {
                state.quitFrontendOnly()
            } label: {
                Label(L10n.t("menu.quitFrontend"), systemImage: "rectangle.righthalf.inset.filled")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - 右键菜单（本地事件监听）

    /// 在应用内监听 rightMouseDown，按行 frame 命中后弹出原生菜单并高亮该行。
    /// （SwiftUI 的 contextMenu 无法提供开合回调；行背景层 NSView 又收不到事件。）
    private func installRightClickMonitor() {
        guard rightClickMonitor == nil else { return }
        // addLocalMonitorForEvents 的回调固定在主线程执行。
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            handleRightClick(event)
        }
    }

    /// 返回 nil 表示事件已消费（弹出了行右键菜单），否则原样放行。
    private func handleRightClick(_ event: NSEvent) -> NSEvent? {
        guard let window = event.window,
              let mountID = hitRowID(at: event.locationInWindow, window: window),
              let mount = state.mountPoints.first(where: { $0.id == mountID }) else {
            return event
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            state.contextMenuUUID = mountID
        }
        defer {
            withAnimation(.easeInOut(duration: 0.12)) {
                state.contextMenuUUID = nil
            }
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let eject = NSMenuItem(
            title: L10n.t("ctx.temporaryEject"),
            action: #selector(RowMenuTarget.run(_:)),
            keyEquivalent: ""
        )
        eject.image = NSImage(systemSymbolName: "eject.fill", accessibilityDescription: nil)
        eject.isEnabled = mount.isEjectable
        eject.representedObject = RowMenuAction { state.temporaryEject(mount) }

        let reveal = NSMenuItem(
            title: L10n.t("ctx.revealInFinder"),
            action: #selector(RowMenuTarget.run(_:)),
            keyEquivalent: ""
        )
        reveal.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        reveal.isEnabled = true
        reveal.representedObject = RowMenuAction { state.revealInFinder(mount) }

        menu.addItem(eject)
        menu.addItem(reveal)

        let target = RowMenuTarget()
        for item in menu.items { item.target = target }

        // popUp 同步阻塞至菜单关闭。at 需要目标视图自身坐标系：
        // NSHostingView 是翻转的（原点左上），locationInWindow 却是底部原点，
        // 直接传会把上下镜像；用 convert 自动换算，翻转与否都正确。
        if let contentView = window.contentView {
            let point = contentView.convert(event.locationInWindow, from: nil)
            menu.popUp(positioning: nil, at: point, in: contentView)
        }
        return nil
    }

    /// 将窗口底部原坐标转换为 SwiftUI global（顶部原），返回命中的行 ID。
    private func hitRowID(at locationInWindow: NSPoint, window: NSWindow) -> String? {
        let contentHeight = window.contentView?.bounds.height ?? 0
        let point = NSPoint(x: locationInWindow.x, y: contentHeight - locationInWindow.y)
        return rowFrames.first(where: { $0.value.contains(point) })?.key
    }
}

/// 右键菜单动作转发。
private final class RowMenuAction {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
}

private final class RowMenuTarget: NSObject {
    @objc func run(_ sender: NSMenuItem) {
        (sender.representedObject as? RowMenuAction)?.run()
    }
}

// MARK: - 锁图标按钮

/// 模仿老版 macOS 偏好设置的锁：锁定时点击发起验证解锁，解锁时点击重新锁上。
/// 主界面放在左下角，偏好设置页放在右上角；未启用任何密码开关时隐藏。
struct LockIconButton: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Button {
            Task { await state.toggleLock() }
        } label: {
            Image(systemName: state.isUnlocked ? "lock.open" : "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.isUnlocked ? Color.secondary : Color.primary)
        }
        .buttonStyle(.plain)
        .help(state.isUnlocked ? L10n.t("lock.tip.lock") : L10n.t("lock.tip.unlock"))
        .animation(.easeInOut(duration: 0.2), value: state.isUnlocked)
    }
}

// MARK: - 偏好设置

/// 偏好设置：「安全」（按操作细分的三项密码开关）与「推出恢复」。
/// 安全类开关的切换需验证管理员密码；恢复开关直接生效。
struct PreferencesScreen: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BackButton {
                    state.screen = .main
                }
                Spacer()
                Text(L10n.t("menu.security"))
                    .font(.headline)
                Spacer()
                if state.hasAuthSwitches {
                    LockIconButton()
                } else {
                    // 平衡布局的占位
                    Image(systemName: "chevron.left").opacity(0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(L10n.t("pref.section.security"))
                toggleRow(
                    title: L10n.t("pref.auth.openUI.title"),
                    detail: L10n.t("pref.auth.openUI.desc"),
                    keyPath: \.requireAuthOpenUI
                )
                rowDivider
                toggleRow(
                    title: L10n.t("pref.auth.edit.title"),
                    detail: L10n.t("pref.auth.edit.desc"),
                    keyPath: \.requireAuthEdit
                )
                rowDivider
                toggleRow(
                    title: L10n.t("pref.auth.eject.title"),
                    detail: L10n.t("pref.auth.eject.desc"),
                    keyPath: \.requireAuthTemporaryEject
                )
                rowDivider
                toggleRow(
                    title: L10n.t("pref.auth.quit.title"),
                    detail: L10n.t("pref.auth.quit.desc"),
                    keyPath: \.requireAuthQuit
                )

                sectionHeader(L10n.t("pref.section.recovery"))
                    .padding(.top, 14)
                toggleRow(
                    title: L10n.t("pref.remount.title"),
                    detail: L10n.t("pref.remount.desc"),
                    keyPath: \.remountAfterUnexpectedEject,
                    requiresAuth: false
                )
            }
            .padding(14)

            Spacer()
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.vertical, 8)
            .padding(.leading, 0)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
    }

    /// 单个开关行；锁定状态下（requiresAuth 默认 true）切换先验证并解锁，之后免密。
    private func toggleRow(
        title: String,
        detail: String,
        keyPath: WritableKeyPath<NopejectConfig, Bool>,
        requiresAuth: Bool = true
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Toggle(String(), isOn: Binding(
                get: { state.savedConfig[keyPath: keyPath] },
                set: { newValue in
                    Task {
                        await state.setPreference(keyPath, to: newValue, requiresAuth: requiresAuth)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }
}

// MARK: - 关于

struct AboutScreen: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BackButton {
                    state.screen = .main
                }
                Spacer()
                Text(L10n.t("menu.about"))
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.left").opacity(0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 8)

            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("Nopeject")
                    .font(.title3.weight(.semibold))
                Text(L10n.tf("about.version", versionString))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.t("about.tagline"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(L10n.t("about.authors"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.t("about.license"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button {
                    NSWorkspace.shared.open(AppState.githubURL)
                } label: {
                    Label(L10n.t("about.github"), systemImage: "link")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(20)

            Spacer()
        }
    }

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return v ?? "1.0.0"
    }
}

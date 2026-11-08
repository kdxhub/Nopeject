import SwiftUI
import AppKit
import NopejectCore

/// 菜单主内容：顶部项目名 + 后端状态点、挂载点列表、底部保存按钮与“…”二级菜单。
struct MenuContentView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Group {
            switch state.screen {
            case .main: mainScreen
            case .security: SecurityScreen()
            case .about: AboutScreen()
            }
        }
        .frame(width: 380)
        .nopejectPanelBackground()
    }

    // MARK: - 主界面

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
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(state.mountPoints) { mount in
                            MountPointRow(mount: mount)
                            if mount.id != state.mountPoints.last?.id {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider().padding(.horizontal, 8)
            footer
        }
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
        HStack {
            if state.hasPendingEdits || state.saveState != .idle {
                saveButton
                    .transition(.scale.combined(with: .opacity))
            }
            if let message = state.statusMessage {
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
        .animation(.spring(duration: 0.35), value: state.saveState)
        .animation(.spring(duration: 0.35), value: state.hasPendingEdits)
    }

    @ViewBuilder
    private var saveButton: some View {
        switch state.saveState {
        case .idle:
            Button {
                Task { await state.save() }
            } label: {
                Label(L10n.t("menu.save"), systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .saving:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.t("menu.saving"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .saved:
            // 苹果风格「✓ 已保存」
            Label("✓ \(L10n.t("menu.saved"))", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                state.restartBackend()
            } label: {
                Label(L10n.t("menu.restartService"), systemImage: "arrow.clockwise")
            }

            Button {
                state.screen = .security
            } label: {
                Label(L10n.t("menu.security"), systemImage: "hand.raised")
            }

            Button {
                state.screen = .about
            } label: {
                Label(L10n.t("menu.about"), systemImage: "info.circle")
            }

            Divider()

            Button {
                NSWorkspace.shared.open(AppState.sponsorURL)
            } label: {
                Label(L10n.t("menu.sponsor"), systemImage: "heart")
            }

            Divider()

            Button {
                state.quitAll()
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
}

// MARK: - 权限与安全性

/// 「无 / 编辑需要权限 / 始终需要权限」三种模式的设置界面。
/// 任何切换都需要验证管理员密码。
struct SecurityScreen: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    state.screen = .main
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                Spacer()
                Text(L10n.t("menu.security"))
                    .font(.headline)
                Spacer()
                // 平衡布局的占位
                Image(systemName: "chevron.left").opacity(0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 10) {
                modeRow(
                    mode: .none,
                    title: L10n.t("perm.mode.none"),
                    detail: L10n.t("perm.desc.none")
                )
                modeRow(
                    mode: .requireForEdit,
                    title: L10n.t("perm.mode.edit"),
                    detail: L10n.t("perm.desc.edit")
                )
                modeRow(
                    mode: .always,
                    title: L10n.t("perm.mode.always"),
                    detail: L10n.t("perm.desc.always")
                )
                Text(L10n.t("perm.hint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)

            Spacer()
        }
    }

    private func modeRow(mode: PermissionMode, title: String, detail: String) -> some View {
        Button {
            Task { await state.changePermissionMode(to: mode) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: state.permissionMode == mode ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(state.permissionMode == mode ? Color.accentColor : Color.secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 关于

struct AboutScreen: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    state.screen = .main
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
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

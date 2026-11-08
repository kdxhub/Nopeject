import SwiftUI
import AppKit
import NopejectCore

/// 单个挂载点条目：
/// 左侧系统原生宗卷图标；右侧第一行加粗名称，第二行淡化显示类型 / 位置 / 容量；
/// 最右为开关（开启 = 阻止推出）。右键提供临时弹出、在“访达”中显示。
struct MountPointRow: View {
    let mount: MountPoint
    @ObservedObject private var state = AppState.shared

    private var isProtected: Bool {
        state.pendingProtected.contains(mount.id)
    }

    private var subtitle: String {
        let kind = L10n.t("row.kind.\(mount.kindRaw)")
        let free = CapacityFormatter.format(mount.freeBytes)
        let total = CapacityFormatter.format(mount.totalBytes)
        return "\(kind) · \(mount.path) · \(free) / \(total)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: mount.path))
                .resizable()
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(mount.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Toggle(String(), isOn: Binding(
                get: { isProtected },
                set: { newValue in
                    Task { await state.toggle(mount, to: newValue) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            if state.highlightUUID == mount.id {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                state.temporaryEject(mount)
            } label: {
                Label(L10n.t("ctx.temporaryEject"), systemImage: "eject.fill")
            }
            .disabled(!mount.isEjectable)

            Button {
                state.revealInFinder(mount)
            } label: {
                Label(L10n.t("ctx.revealInFinder"), systemImage: "folder")
            }
        }
    }
}

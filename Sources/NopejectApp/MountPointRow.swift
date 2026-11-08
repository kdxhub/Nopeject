import SwiftUI
import AppKit
import NopejectCore

/// 单个挂载点条目：
/// 左侧系统原生宗卷图标；右侧第一行加粗名称，第二行淡化显示介质类型与可用空间，
/// 第三行淡化显示挂载点路径；最右为开关（开启 = 阻止推出）。右键提供临时弹出、在“访达”中显示。
struct MountPointRow: View {
    let mount: MountPoint
    @ObservedObject private var state = AppState.shared

    private var isProtected: Bool {
        state.pendingProtected.contains(mount.id)
    }

    /// 第二行：介质类型 +「可用 / 总量」明确标注的剩余空间。
    private var subtitle: String {
        let kind = L10n.t("row.kind.\(mount.kindRaw)")
        let free = CapacityFormatter.format(mount.freeBytes)
        let total = CapacityFormatter.format(mount.totalBytes)
        return L10n.tf("row.subtitle", kind, free, total)
    }

    private var isHighlighted: Bool {
        state.highlightUUID == mount.id || state.contextMenuUUID == mount.id
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
                    .truncationMode(.tail)
                Text(mount.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
            if isHighlighted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
            }
        }
        .contentShape(Rectangle())
    }
}

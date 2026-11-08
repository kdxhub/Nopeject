import SwiftUI
import AppKit

/// 右键菜单宿主：捕获挂载点行上的右键，弹出原生 NSMenu；
/// 菜单弹出期间通过回调高亮对应行，让用户明确看到操作目标是哪个挂载点。
/// （SwiftUI 的 .contextMenu 不提供打开/关闭回调，故用 NSView 实现。）
struct RowContextMenu: NSViewRepresentable {
    var isEjectable: Bool
    var onOpen: () -> Void
    var onClose: () -> Void
    var onTemporaryEject: () -> Void
    var onRevealInFinder: () -> Void

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> RightClickCatcherView {
        let view = RightClickCatcherView()
        configure(view)
        return view
    }

    func updateNSView(_ view: RightClickCatcherView, context: Context) {
        configure(view)
    }

    private func configure(_ view: RightClickCatcherView) {
        view.onOpen = onOpen
        view.onClose = onClose
        view.menuProvider = { [isEjectable, onTemporaryEject, onRevealInFinder] in
            buildMenu(isEjectable: isEjectable,
                      onTemporaryEject: onTemporaryEject,
                      onRevealInFinder: onRevealInFinder)
        }
    }

    // MARK: - 菜单构建

    private func buildMenu(
        isEjectable: Bool,
        onTemporaryEject: @escaping () -> Void,
        onRevealInFinder: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let eject = NSMenuItem(
            title: L10n.t("ctx.temporaryEject"),
            action: #selector(RightClickCatcherView.MenuTarget.run(_:)),
            keyEquivalent: ""
        )
        eject.image = NSImage(systemSymbolName: "eject.fill", accessibilityDescription: nil)
        eject.isEnabled = isEjectable
        eject.representedObject = RightClickCatcherView.ActionBox(onTemporaryEject)

        let reveal = NSMenuItem(
            title: L10n.t("ctx.revealInFinder"),
            action: #selector(RightClickCatcherView.MenuTarget.run(_:)),
            keyEquivalent: ""
        )
        reveal.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        reveal.isEnabled = true
        reveal.representedObject = RightClickCatcherView.ActionBox(onRevealInFinder)

        menu.addItem(eject)
        menu.addItem(reveal)
        return menu
    }
}

/// 透明的右键捕获视图：左键事件照常穿透给 SwiftUI。
final class RightClickCatcherView: NSView {
    var menuProvider: () -> NSMenu = { NSMenu() }
    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}

    private let target = MenuTarget()

    override func rightMouseDown(with event: NSEvent) {
        onOpen()
        defer { onClose() }
        let menu = menuProvider()
        // NSMenu 本身无 target，把转发器设到每个条目上。
        for item in menu.items { item.target = target }
        let point = convert(event.locationInWindow, from: nil)
        // popUp 在内嵌 run loop 中同步阻塞至菜单关闭。
        menu.popUp(positioning: nil, at: point, in: self)
    }

    // MARK: - 菜单动作转发

    final class ActionBox {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    final class MenuTarget: NSObject {
        @objc func run(_ sender: NSMenuItem) {
            (sender.representedObject as? ActionBox)?.run()
        }
    }
}

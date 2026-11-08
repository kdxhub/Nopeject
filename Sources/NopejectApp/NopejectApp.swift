import SwiftUI

/// Nopeject 菜单栏应用入口。
/// macOS 26+ 下 MenuBarExtra 面板自动呈现液态玻璃质感（由 nopejectPanelBackground 控制）。
@main
struct NopejectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
        } label: {
            Image(systemName: state.backendRunning
                  ? "externaldrive.badge.checkmark"
                  : "externaldrive.badge.exclamationmark")
        }
        .menuBarExtraStyle(.window)
    }
}

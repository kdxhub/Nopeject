import SwiftUI

extension View {
    /// 面板背景：macOS 26+ 自动启用液态玻璃（Liquid Glass），
    /// 低版本回退为高斯模糊材质（ultraThinMaterial）。
    @ViewBuilder
    func nopejectPanelBackground() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        #else
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        #endif
    }
}

import SwiftUI

/// 二级页面返回按钮：
/// 悬停时淡入圆角激活背景，按下时轻微收缩，均为弹簧/缓动动画；
/// 点击切换页面同样使用动画过渡，让窗口高度变化平滑。
struct BackButton: View {
    var action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.35)) {
                action()
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .frame(width: 24, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isHovering ? 0.1 : 0))
                }
                .scaleEffect(isPressed ? 0.88 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.spring(duration: 0.2)) { isPressed = true }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(duration: 0.25)) { isPressed = false }
                }
        )
    }
}

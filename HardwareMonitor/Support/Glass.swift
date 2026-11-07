import SwiftUI
import Combine

// MARK: - 卡面流光开关
// 用 Environment 而不是 EnvironmentObject：悬浮窗、菜单栏等没有注入 AppModel 的视图也能安全取到默认值。
private struct GlassMotionEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var glassMotionEnabled: Bool {
        get { self[GlassMotionEnabledKey.self] }
        set { self[GlassMotionEnabledKey.self] = newValue }
    }
}

private enum GlassMaterial {
    case ultraThin
    case regular
}

/// hover 状态用普通 ObservableObject，不用 @State 宏（这台机器的 Xcode 宏插件会报错）
private final class GlassHoverState: ObservableObject {
    @Published var hovering = false
}

/// 只改一次布尔值，之后由 CoreAnimation 合成层持续动画，不重算视图、不重绘画布。
private final class SheenDrive: ObservableObject {
    @Published var shifted = false
}

// MARK: - 极淡的卡面流光（2.1.6 性能优化版）
/// 2.1.5 之前：每张卡片一个 20fps 定时重绘，每帧在画布里画渐变 + 描边，再叠 4pt 模糊。
/// 主窗口十张卡片同时跑 = 约 200 次画布重绘/秒，是界面卡顿的主因。
///
/// 现在：光带是一个普通的 LinearGradient，用 offset 做 repeatForever 动画。
/// 动画只改图层 transform，由 CoreAnimation 合成，不触发 SwiftUI body 重算、不产生逐帧绘制、不用模糊。
private struct GlassSheen: View {
    let cornerRadius: CGFloat
    let intensity: Double
    let dark: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.glassMotionEnabled) private var motionEnabled
    @StateObject private var drive = SheenDrive()

    private var animated: Bool { motionEnabled && !reduceMotion }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let k = (dark ? 0.055 : 0.075) * intensity

        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.34),
                    .init(color: .white.opacity(k), location: 0.5),
                    .init(color: .clear, location: 0.66),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: max(w * 1.1, 40), height: max(h * 2.4, 40))
            .rotationEffect(.degrees(-16))
            .offset(x: animated ? (drive.shifted ? w * 0.62 : -w * 0.62) : 0)
            .animation(
                animated ? .easeInOut(duration: 19).repeatForever(autoreverses: true) : .default,
                value: drive.shifted
            )
            .onAppear { if animated { drive.shifted = true } }
            .frame(width: w, height: h, alignment: .center)
            .clipShape(shape)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 玻璃表面
private struct GlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let material: GlassMaterial
    let sheenScale: Double
    let shadowRadius: CGFloat

    @StateObject private var hover = GlassHoverState()
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = colorScheme == .dark
        content
            .background(
                ZStack {
                    switch material {
                    case .ultraThin:
                        shape.fill(.ultraThinMaterial)
                    case .regular:
                        shape.fill(.regularMaterial)
                    }

                    shape.fill(
                        LinearGradient(
                            colors: [.white.opacity(dark ? 0.10 : 0.18), .clear, .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                    GlassSheen(
                        cornerRadius: cornerRadius,
                        intensity: sheenScale * (hover.hovering ? 1.5 : 1.0),
                        dark: dark
                    )

                    shape.stroke(.white.opacity(dark ? 0.22 : 0.34), lineWidth: 1)
                }
                .clipShape(shape)
                .shadow(
                    color: .black.opacity(dark ? 0.18 : 0.10),
                    radius: shadowRadius,
                    y: shadowRadius * 0.36
                )
            )
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.25)) { hover.hovering = inside }
            }
    }
}

// MARK: - 对外接口（签名保持不变，所有旧调用点无需改动）
extension View {
    /// 玻璃卡片背景
    func glassBackground(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, material: .ultraThin,
                              sheenScale: 1.0, shadowRadius: 14))
    }

    /// 玻璃面板背景（大圆角，用于整体面板）
    func glassPanelBackground(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, material: .regular,
                              sheenScale: 0.8, shadowRadius: 20))
    }

    /// 主窗口把用户设置注入整棵视图树
    func glassMotion(_ enabled: Bool) -> some View {
        environment(\.glassMotionEnabled, enabled)
    }
}

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

// MARK: - 极淡的卡面流光
/// 2.1.3 起收敛：卡片上只留一条很淡的白色高光带缓慢扫过 + 边缘亮点，
/// 不再铺满彩色光斑和融合光团。液态玻璃的主视觉交给顶部标签栏的滑块。
private struct GlassSheen: View {
    let cornerRadius: CGFloat
    let intensity: Double
    let dark: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.glassMotionEnabled) private var motionEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if reduceMotion || !motionEnabled {
                canvas(phase: 0)
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { context in
                    canvas(phase: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }

    private func canvas(phase: Double) -> some View {
        Canvas { context, size in
            let w = max(size.width, 1)
            let h = max(size.height, 1)
            // 刻意压得很淡，避免卡片看起来「花」
            let k = (dark ? 0.055 : 0.075) * intensity

            let sweep = CGFloat(0.5 + 0.5 * sin(phase * 0.28))
            let start = CGPoint(x: -w * 0.45 + sweep * w * 1.9, y: h * 1.15)
            let end = CGPoint(x: -w * 0.05 + sweep * w * 1.9, y: -h * 0.15)
            context.fill(
                Path(CGRect(x: 0, y: 0, width: w, height: h)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.38),
                        .init(color: .white.opacity(k), location: 0.5),
                        .init(color: .clear, location: 0.62),
                        .init(color: .clear, location: 1)
                    ]),
                    startPoint: start,
                    endPoint: end
                )
            )

            let edge = Path(
                roundedRect: CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1),
                cornerRadius: cornerRadius,
                style: .continuous
            )
            let q = min(0.85, max(0.15, 0.5 + 0.5 * sin(phase * 0.22)))
            context.stroke(
                edge,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0.02), location: 0),
                        .init(color: .white.opacity(min(0.22, k * 2.2)), location: q),
                        .init(color: .white.opacity(0.02), location: 1)
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: w, y: h)
                ),
                lineWidth: 1
            )
        }
        .blur(radius: 4)
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

    /// 玻璃按钮
    func glassButton(cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, material: .ultraThin,
                              sheenScale: 1.25, shadowRadius: 6))
    }

    /// 主窗口把用户设置注入整棵视图树
    func glassMotion(_ enabled: Bool) -> some View {
        environment(\.glassMotionEnabled, enabled)
    }
}

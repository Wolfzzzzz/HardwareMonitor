import SwiftUI
import Combine

// MARK: - 液态玻璃动效开关
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

// MARK: - 玻璃光效总层
/// 所有动态层共用同一个 TimelineView（20fps），父视图 body 不跟着每帧重算。
/// phase 由 TimelineView 提供，不依赖 @State / 宏，兼容 macOS 14+ 与 Xcode-beta。
private struct GlassEffects: View {
    let cornerRadius: CGFloat
    let intensity: Double

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.glassMotionEnabled) private var motionEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = colorScheme == .dark
        Group {
            if reduceMotion || !motionEnabled {
                // 静态玻璃：折射层次还在，但不跑定时器
                layers(phase: 0, dark: dark, shape: shape)
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { context in
                    layers(phase: context.date.timeIntervalSinceReferenceDate, dark: dark, shape: shape)
                }
            }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }

    private func layers(phase: Double, dark: Bool, shape: RoundedRectangle) -> some View {
        ZStack {
            GlassSheenCanvas(cornerRadius: cornerRadius, dark: dark, intensity: intensity, phase: phase)
            // metaball 融合光团：参考官方 demo 的 blur + alphaThreshold 写法
            GlassFluidCanvas(phase: phase)
                .opacity((dark ? 0.13 : 0.17) * min(intensity, 1.8))
        }
        .blur(radius: 1.2)
        .clipShape(shape)
    }
}

// MARK: - 流动高光：光带 + 折射光斑 + 边缘亮点
private struct GlassSheenCanvas: View {
    let cornerRadius: CGFloat
    let dark: Bool
    let intensity: Double
    let phase: Double

    var body: some View {
        Canvas { context, size in
            draw(&context, size: size)
        }
        .blur(radius: 5)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let k = (dark ? 0.13 : 0.19) * intensity

        // 1) 主高光带：沿对角线缓慢扫过，约 19 秒一轮
        let sweep = CGFloat(0.5 + 0.5 * sin(phase * 0.33))
        let start = CGPoint(x: -w * 0.45 + sweep * w * 1.9, y: h * 1.15)
        let end = CGPoint(x: -w * 0.05 + sweep * w * 1.9, y: -h * 0.15)
        ctx.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: h)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.36),
                    .init(color: .white.opacity(k), location: 0.5),
                    .init(color: .clear, location: 0.64),
                    .init(color: .clear, location: 1)
                ]),
                startPoint: start,
                endPoint: end
            )
        )

        // 2) 两枚折射光斑：一冷一暖，各自慢慢漂移
        let spots: [(Color, Double, Double)] = [
            (Color(red: 0.68, green: 0.84, blue: 1.0), 0.21, 0.0),
            (Color(red: 1.0, green: 0.78, blue: 0.62), 0.16, 2.1)
        ]
        for (color, speed, offset) in spots {
            let cx = w * (0.5 + 0.34 * sin(phase * speed + offset))
            let cy = h * (0.5 + 0.30 * cos(phase * speed * 0.8 + offset))
            let r = max(w, h) * 0.52
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(k * 0.85), .clear]),
                    center: CGPoint(x: cx, y: cy),
                    startRadius: 0,
                    endRadius: r
                )
            )
        }

        // 3) 边缘高光：亮部沿边框缓慢移动
        let edge = Path(
            roundedRect: CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1),
            cornerRadius: cornerRadius,
            style: .continuous
        )
        let q = min(0.85, max(0.15, 0.5 + 0.5 * sin(phase * 0.27)))
        ctx.stroke(
            edge,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0.04), location: 0),
                    .init(color: .white.opacity(min(0.6, k * 1.8)), location: q),
                    .init(color: .white.opacity(0.04), location: 1)
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: w, y: h)
            ),
            lineWidth: 1
        )
    }
}

// MARK: - 流体融合光团（metaball）
/// 官方同款做法：先给子图层极限模糊，再用 alphaThreshold 把模糊边缘裁回锐利，
/// 两团靠近时就会出现「拉丝—融合—分开」的液态效果。
private struct GlassFluidCanvas: View {
    let phase: Double

    var body: some View {
        Canvas { context, size in
            let w = max(size.width, 1)
            let h = max(size.height, 1)
            context.addFilter(.alphaThreshold(min: 0.5, color: .white))
            context.addFilter(.blur(radius: 15))
            context.drawLayer { ctx in
                let d = CGFloat(0.5 + 0.5 * sin(phase * 0.30))
                let sep = w * (0.10 + 0.20 * d)
                let a = CGPoint(x: w * 0.5 - sep, y: h * (0.46 + 0.12 * sin(phase * 0.23)))
                let b = CGPoint(x: w * 0.5 + sep, y: h * (0.54 + 0.12 * cos(phase * 0.19 + 1.1)))
                if let one = ctx.resolveSymbol(id: 1) { ctx.draw(one, at: a, anchor: .center) }
                if let two = ctx.resolveSymbol(id: 2) { ctx.draw(two, at: b, anchor: .center) }
            }
        } symbols: {
            ForEach([1, 2], id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: 56, height: 56)
                    .tag(i)
            }
        }
        .blur(radius: 2)
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
        content
            .background(
                ZStack {
                    switch material {
                    case .ultraThin:
                        shape.fill(.ultraThinMaterial)
                    case .regular:
                        shape.fill(.regularMaterial)
                    }

                    // 顶部固定的微亮面，保留原来的玻璃质感
                    shape.fill(
                        LinearGradient(
                            colors: [.white.opacity(colorScheme == .dark ? 0.10 : 0.18), .clear, .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                    GlassEffects(
                        cornerRadius: cornerRadius,
                        intensity: sheenScale * (hover.hovering ? 1.6 : 1.0)
                    )

                    shape.stroke(.white.opacity(colorScheme == .dark ? 0.22 : 0.34), lineWidth: 1)
                }
                .clipShape(shape)
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.18 : 0.10),
                    radius: shadowRadius,
                    y: shadowRadius * 0.36
                )
            )
            // 鼠标移入时高光与融合都变强，形成「被搅动」的反馈
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

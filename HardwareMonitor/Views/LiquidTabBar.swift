import SwiftUI
import Combine

/// 一次切换的起点、终点与开始时刻。
/// 用 ObservableObject 而不是 @State 宏：这台机器的 Xcode 宏插件会报 StateMacro 找不到。
final class LiquidTabMotion: ObservableObject {
    @Published var fromIndex = 0
    @Published var toIndex = 0
    @Published var selectedIndex = 0
    @Published var startedAt = Date.distantPast
    /// 跨越了几个标签
    var span: Int { abs(toIndex - fromIndex) }
}

/// 液态玻璃分段选择栏。
///
/// 优化点：滑块不再只是平移。跨多个标签时（例如「监控」直接切「专注」），
/// 主滑块在中段被拉长，起点留下一枚逐渐缩小的液滴，并断裂出两枚小气泡，
/// 最后一起收敛、融合到目标位置。形变由 TimelineView 逐帧计算，
/// 不依赖 SwiftUI 隐式插值，也不依赖 @State 宏。
struct LiquidTabBar: View {
    @Binding var selection: Int
    let accent: Color

    private let titles = ["监控", "剪贴板", "工具", "专注"]

    @StateObject private var motion = LiquidTabMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let itemWidth = geometry.size.width / CGFloat(titles.count)
            ZStack {
                // 1) 毛玻璃底座
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule().stroke(
                            .white.opacity(colorScheme == .dark ? 0.10 : 0.24),
                            lineWidth: 1
                        )
                    )

                // 2) 液态滑块（Canvas + metaball 滤镜链）
                if reduceMotion {
                    staticSlider(size: geometry.size, itemWidth: itemWidth)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        liquidSlider(date: context.date, size: geometry.size, itemWidth: itemWidth)
                    }
                }

                // 3) 文字与竖线分隔符浮在最上层，保证可读
                HStack(spacing: 0) {
                    ForEach(titles.indices, id: \.self) { i in
                        Text(titles[i])
                            .font(.system(size: 13, weight: motion.selectedIndex == i ? .semibold : .medium))
                            .foregroundStyle(labelColor(i))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = i }

                        if i < titles.count - 1 {
                            Rectangle()
                                .fill(.white.opacity(0.14))
                                .frame(width: 1, height: 14)
                        }
                    }
                }
            }
        }
        .frame(height: 38)
        .onAppear {
            motion.fromIndex = selection
            motion.toIndex = selection
            motion.selectedIndex = selection
        }
        .onChange(of: selection) { _, newValue in
            guard newValue != motion.selectedIndex else { return }
            motion.fromIndex = motion.toIndex
            motion.toIndex = newValue
            motion.selectedIndex = newValue
            motion.startedAt = Date()
        }
    }

    private func labelColor(_ i: Int) -> Color {
        if motion.selectedIndex == i { return .white }
        return colorScheme == .dark ? .white.opacity(0.72) : .primary.opacity(0.65)
    }

    // MARK: 逐帧形变

    /// p: 0 → 1 的一次切换。主滑块拉伸、尾巴缩小、气泡断裂、末端融合。
    private func liquidSlider(date: Date, size: CGSize, itemWidth: CGFloat) -> some View {
        let duration = motion.span > 1 ? 0.78 : 0.52
        let elapsed = date.timeIntervalSince(motion.startedAt)
        let p = min(1, max(0, elapsed / duration))
        let eased = easeOutBack(p)

        let fromX = (CGFloat(motion.fromIndex) + 0.5) * itemWidth
        let toX = (CGFloat(motion.toIndex) + 0.5) * itemWidth
        let travel = toX - fromX
        let x = fromX + travel * CGFloat(eased)

        let h = size.height - 10
        let baseWidth = itemWidth - 12
        // 中段拉得最长，两端收回：像被拽长再弹回
        let stretch = abs(travel) * 0.28 * CGFloat(sin(p * .pi))
        let sliderWidth = baseWidth + stretch

        return Canvas { context, _ in
            // 官方 demo 同款滤镜链：先模糊让相邻形状「粘」在一起，再裁 alpha 把边缘变锐利
            context.addFilter(.alphaThreshold(min: 0.45, color: accent))
            context.addFilter(.blur(radius: 12))
            context.drawLayer { ctx in
                // 主滑块
                let body = Path(
                    roundedRect: CGRect(x: x - sliderWidth / 2,
                                        y: (size.height - h) / 2,
                                        width: sliderWidth,
                                        height: h),
                    cornerRadius: h / 2,
                    style: .continuous
                )
                ctx.fill(body, with: .color(.white))

                // 跨多个标签：起点留尾巴，断裂出小气泡，最后被主滑块重新吸收
                if motion.span >= 2 && p < 0.72 {
                    let q = p / 0.72
                    let tailRadius = h * 0.28 * (1 - q)
                    let tailX = fromX + (x - fromX) * 0.16
                    let cy = size.height / 2

                    ctx.fill(
                        Path(ellipseIn: CGRect(x: tailX - tailRadius, y: cy - tailRadius,
                                               width: tailRadius * 2, height: tailRadius * 2)),
                        with: .color(.white)
                    )

                    // 两枚断裂气泡，朝主滑块方向漂，靠近时又融回去
                    let gap = x - tailX
                    let bubbleRadius = tailRadius * 0.52
                    for k in 0..<2 {
                        let t = 0.34 + 0.26 * CGFloat(k) + 0.16 * CGFloat(q)
                        let bx = tailX + gap * t
                        let by = cy + (k == 0 ? -1 : 1) * h * 0.10 * (1 - q)
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: bx - bubbleRadius, y: by - bubbleRadius,
                                                   width: bubbleRadius * 2, height: bubbleRadius * 2)),
                            with: .color(.white)
                        )
                    }
                }
            }
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
    }

    /// 减少动态效果时：直接把滑块放在目标位置，不做融合
    private func staticSlider(size: CGSize, itemWidth: CGFloat) -> some View {
        let x = (CGFloat(motion.selectedIndex) + 0.5) * itemWidth
        let h = size.height - 10
        return RoundedRectangle(cornerRadius: h / 2, style: .continuous)
            .fill(accent.opacity(0.85))
            .frame(width: itemWidth - 12, height: h)
            .position(x: x, y: size.height / 2)
            .allowsHitTesting(false)
    }

    /// 带一点点回弹的缓出曲线，让液体停住时晃一下
    private func easeOutBack(_ p: Double) -> Double {
        let c1 = 1.42
        let c3 = c1 + 1
        let t = p - 1
        return 1 + c3 * t * t * t + c1 * t * t
    }
}

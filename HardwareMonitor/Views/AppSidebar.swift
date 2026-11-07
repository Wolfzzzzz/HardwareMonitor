import SwiftUI
import Combine

/// 记录侧边栏每一行的真实位置，不靠硬编码行高猜坐标
private struct SidebarRowFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 一次切换的起点、终点、开始时刻；用 ObservableObject 避开 @State 宏
final class SidebarMotion: ObservableObject {
    @Published var fromIndex = 0
    @Published var toIndex = 0
    @Published var selectedIndex = 0
    @Published var startedAt = Date.distantPast
    @Published var frames: [Int: CGRect] = [:]
    var span: Int { abs(toIndex - fromIndex) }
}

/// 苹果原生侧边栏（List + .sidebar 材质 + 系统选中高亮），
/// 上面叠一层液态玻璃选中光晕。
///
/// 跨多行切换（例如「监控」直接点「专注」）时，滑块在垂直方向被拉长，
/// 起点留一枚逐渐缩小的液滴并断裂出两枚小气泡，最后融合到目标行。
struct AppSidebar: View {
    @Binding var selection: Int
    let accent: Color

    @StateObject private var motion = SidebarMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let items: [(title: String, icon: String)] = [
        ("监控", "gauge.with.dots.needle.50percent"),
        ("剪贴板", "clipboard"),
        ("工具", "wrench.and.screwdriver"),
        ("专注", "timer")
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1) 原生列表栏：系统材质、系统选中高亮、SF Symbols
            List(selection: Binding<Int?>(
                get: { selection },
                set: { if let value = $0 { selection = value } }
            )) {
                ForEach(items.indices, id: \.self) { i in
                    Label(items[i].title, systemImage: items[i].icon)
                        .font(.system(size: 13))
                        .frame(height: 34)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: SidebarRowFrameKey.self,
                                    value: [i: geo.frame(in: .named("sidebarSpace"))]
                                )
                            }
                        )
                        .tag(i)
                }
            }
            .listStyle(.sidebar)
            .tint(accent)

            // 2) 液态选中光晕：低透明度叠在行上，不挡文字、不抢点击
            Group {
                if reduceMotion {
                    staticHighlight()
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        liquidHighlight(date: context.date)
                    }
                }
            }
            .opacity(0.32)
            .allowsHitTesting(false)
        }
        .coordinateSpace(name: "sidebarSpace")
        .onPreferenceChange(SidebarRowFrameKey.self) { motion.frames = $0 }
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

    // MARK: 逐帧形变（垂直版）

    private func liquidHighlight(date: Date) -> some View {
        let duration = motion.span > 1 ? 0.78 : 0.52
        let p = min(1, max(0, date.timeIntervalSince(motion.startedAt) / duration))
        let eased = easeOutBack(p)

        let fallback = CGRect(x: 12, y: 8, width: 176, height: 34)
        let from = motion.frames[motion.fromIndex] ?? fallback
        let to = motion.frames[motion.toIndex] ?? from
        let fromY = from.midY
        let travel = to.midY - fromY
        let y = fromY + travel * CGFloat(eased)

        let width = min(from.width, to.width) - 8
        let baseHeight = min(from.height, to.height) - 4
        let stretch = abs(travel) * 0.28 * CGFloat(sin(p * .pi))
        let height = baseHeight + stretch
        let x = to.midX

        return Canvas { context, _ in
            context.addFilter(.alphaThreshold(min: 0.45, color: accent))
            context.addFilter(.blur(radius: 11))
            context.drawLayer { ctx in
                let body = Path(
                    roundedRect: CGRect(x: x - width / 2, y: y - height / 2,
                                        width: width, height: height),
                    cornerRadius: 9,
                    style: .continuous
                )
                ctx.fill(body, with: .color(.white))

                // 跨多行：起点留液滴、断裂出两枚气泡，后段重新融合
                if motion.span >= 2 && p < 0.72 {
                    let q = p / 0.72
                    let radius = height * 0.28 * (1 - q)
                    let tailY = fromY + (y - fromY) * 0.16
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - radius, y: tailY - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .color(.white)
                    )
                    let gap = y - tailY
                    let bubble = radius * 0.52
                    for k in 0..<2 {
                        let t = 0.34 + 0.26 * CGFloat(k) + 0.16 * CGFloat(q)
                        let by = tailY + gap * t
                        let bx = x + (k == 0 ? -1 : 1) * width * 0.10 * (1 - q)
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: bx - bubble, y: by - bubble,
                                                   width: bubble * 2, height: bubble * 2)),
                            with: .color(.white)
                        )
                    }
                }
            }
        }
    }

    /// 减少动态效果：直接把高亮放在目标行
    private func staticHighlight() -> some View {
        let rect = motion.frames[motion.selectedIndex]
            ?? CGRect(x: 12, y: 8, width: 176, height: 34)
        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(accent.opacity(0.55))
            .frame(width: rect.width - 8, height: rect.height - 4)
            .position(x: rect.midX, y: rect.midY)
    }

    private func easeOutBack(_ p: Double) -> Double {
        let c1 = 1.42
        let c3 = c1 + 1
        let t = p - 1
        return 1 + c3 * t * t * t + c1 * t * t
    }
}

import SwiftUI
import Combine

// MARK: - 侧边栏数据

private struct SidebarItem: Identifiable {
    let id: Int
    let title: String
    let icon: String
}

/// 一次切换的形变进度。用 ObservableObject 存状态，避开本机 Xcode-beta 的 @State 宏插件问题。
final class SidebarGlowMotion: ObservableObject {
    /// 0 → 1，由 withAnimation 逐帧插值给 Shape.animatableData
    @Published var progress: CGFloat = 1
    /// 跨多行切换 = 1，相邻切换 = 0.3，静态 = 0
    @Published var intensity: CGFloat = 0
}

/// 选中行内部的柔和光晕。
///
/// 关键：**只画在选中行自己的 frame 里**，不跨行、不读全局坐标、不猜行位置。
/// 位置完全由 SwiftUI 的列表行决定，所以永远不会盖到别的行上。
/// 跨多行切换时短暂拉长、留一枚缩小的液滴和两枚小气泡，再收回成圆角矩形。
private struct LiquidRowGlow: Shape {
    var progress: CGFloat
    var intensity: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let p = min(1, max(0, progress))
        // 中段拉长，两端收回；上限锁在行高附近，绝不越出这一行
        let stretch = 1 - intensity * 0.08 * CGFloat(sin(p * .pi))
        let h = rect.height * stretch
        let body = CGRect(x: rect.minX, y: rect.midY - h / 2,
                          width: rect.width, height: h)
        var path = Path(roundedRect: body, cornerRadius: 7, style: .continuous)

        if intensity > 0.5 && p < 0.8 {
            let q = p / 0.8
            let r = max(0, rect.height * 0.15 * (1 - q))
            if r > 0.6 {
                path.addEllipse(in: CGRect(x: rect.minX + r * 0.7,
                                           y: rect.midY - r,
                                           width: r * 2, height: r * 2))
                let bubble = r * 0.38
                for k in 0..<2 {
                    let bx = rect.minX + rect.width * (0.40 + 0.19 * CGFloat(k))
                    let by = rect.midY + (k == 0 ? -1 : 1) * r * 0.75
                    path.addEllipse(in: CGRect(x: bx - bubble, y: by - bubble,
                                               width: bubble * 2, height: bubble * 2))
                }
            }
        }
        return path
    }
}

// MARK: - 原生侧边栏

/// 苹果原生列表栏：List + .listStyle(.sidebar)，系统材质与系统蓝色选中高亮。
///
/// 2.1.5 起不再叠加独立的光晕绘制层：那一层用自定义坐标空间猜行位置，
/// 会和系统选中高亮错开，出现「褐色椭圆横在两行之间」的 bug。
/// 现在光晕挂在选中行自己的背景上，跟随行走，坐标天然对齐。
struct AppSidebar: View {
    @Binding var selection: Int

    @StateObject private var motion = SidebarGlowMotion()
    @Environment(\.glassMotionEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let items: [SidebarItem] = [
        SidebarItem(id: 0, title: "监控", icon: "gauge.with.dots.needle.50percent"),
        SidebarItem(id: 1, title: "剪贴板", icon: "clipboard"),
        SidebarItem(id: 2, title: "工具", icon: "wrench.and.screwdriver"),
        SidebarItem(id: 3, title: "专注", icon: "timer")
    ]

    var body: some View {
        List(selection: Binding<Int?>(
            get: { selection },
            set: { if let value = $0 { selection = value } }
        )) {
            ForEach(items) { item in
                row(item)
                    .tag(item.id)
            }
        }
        .listStyle(.sidebar)
        // 系统强调色：选中高亮由 macOS 自己画，形状、圆角、颜色都跟原生 App 一致
        .tint(.accentColor)
        .onChange(of: selection) { oldValue, newValue in
            let span = abs(newValue - oldValue)
            guard !reduceMotion, motionEnabled else {
                motion.intensity = 0
                motion.progress = 1
                return
            }
            motion.intensity = span > 1 ? 1 : 0.3
            motion.progress = 0
            withAnimation(.spring(response: span > 1 ? 0.62 : 0.44,
                                  dampingFraction: 0.78)) {
                motion.progress = 1
            }
        }
    }

    /// 固定图标槽 + 统一字号 + 统一行高，四行文字左边缘严格对齐
    private func row(_ item: SidebarItem) -> some View {
        HStack(spacing: 9) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .medium))
                .imageScale(.medium)
                .frame(width: 22, height: 22, alignment: .center)
            Text(item.title)
                .font(.system(size: 13))
            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
        .background {
            if selection == item.id && motionEnabled {
                LiquidRowGlow(progress: motion.progress, intensity: motion.intensity)
                    .fill(Color.accentColor.opacity(0.13))
                    .blur(radius: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
    }
}

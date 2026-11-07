import SwiftUI
import Combine

/// 液态玻璃融合预览的状态。
/// 不用 @State 宏：这台机器的 Xcode 宏插件会报 StateMacro 找不到，
/// 统一放 ObservableObject，和 AppModel 的写法保持一致。
final class LiquidGlassPreviewState: ObservableObject {
    @Published var offsetOne = CGSize(width: -58, height: 0)
    @Published var offsetTwo = CGSize(width: 58, height: 0)
    @Published var startOne = CGSize(width: -58, height: 0)
    @Published var startTwo = CGSize(width: 58, height: 0)
}

/// 官方 demo 同款 metaball：两枚玻璃球靠近时会拉丝、融合、再分开。
/// Canvas 子图层先极限模糊，再用 alphaThreshold 把边缘裁回锐利；
/// 由于 Canvas 里的 symbol 收不到手势，上面覆盖一层透明热区来分发拖拽。
struct LiquidGlassPreview: View {
    @StateObject private var state = LiquidGlassPreviewState()

    private let blobSize: CGFloat = 96
    private let blurRadius: CGFloat = 16
    private let alphaThreshold: CGFloat = 0.5

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.30, green: 0.62, blue: 0.95),
                        Color(red: 0.60, green: 0.42, blue: 0.92),
                        Color(red: 0.95, green: 0.52, blue: 0.62),
                        Color(red: 0.98, green: 0.72, blue: 0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Canvas { context, _ in
                    context.addFilter(.alphaThreshold(min: alphaThreshold, color: .white))
                    context.addFilter(.blur(radius: blurRadius))
                    context.drawLayer { ctx in
                        let p1 = CGPoint(x: center.x + state.offsetOne.width,
                                         y: center.y + state.offsetOne.height)
                        let p2 = CGPoint(x: center.x + state.offsetTwo.width,
                                         y: center.y + state.offsetTwo.height)
                        if let one = ctx.resolveSymbol(id: 1) { ctx.draw(one, at: p1, anchor: .center) }
                        if let two = ctx.resolveSymbol(id: 2) { ctx.draw(two, at: p2, anchor: .center) }
                    }
                } symbols: {
                    ForEach([1, 2], id: \.self) { i in
                        ZStack {
                            Circle().fill(.ultraThinMaterial)
                            Circle().stroke(.white.opacity(0.55), lineWidth: 1.5)
                        }
                        .frame(width: blobSize, height: blobSize)
                        .tag(i)
                    }
                }

                // 两个透明手势热区，位置与 Canvas 里的球保持同步
                Color.clear
                    .frame(width: blobSize, height: blobSize)
                    .position(x: center.x + state.offsetOne.width,
                              y: center.y + state.offsetOne.height)
                    .contentShape(Circle())
                    .gesture(drag(for: 1))

                Color.clear
                    .frame(width: blobSize, height: blobSize)
                    .position(x: center.x + state.offsetTwo.width,
                              y: center.y + state.offsetTwo.height)
                    .contentShape(Circle())
                    .gesture(drag(for: 2))

                Text("拖动两枚玻璃球")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.22)))
                    .position(x: center.x, y: geometry.size.height - 16)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(height: 176)
    }

    private func drag(for which: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let base = which == 1 ? state.startOne : state.startTwo
                let next = CGSize(width: base.width + value.translation.width,
                                  height: base.height + value.translation.height)
                if which == 1 { state.offsetOne = next } else { state.offsetTwo = next }
            }
            .onEnded { _ in
                if which == 1 { state.startOne = state.offsetOne } else { state.startTwo = state.offsetTwo }
            }
    }
}

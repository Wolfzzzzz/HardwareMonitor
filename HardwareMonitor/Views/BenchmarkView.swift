import SwiftUI

/// 独立 Geekbench 风格跑分界面（全屏 Sheet）
struct BenchmarkView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // 深色背景
            Color(red: 0.06, green: 0.06, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                scoreRow
                Spacer(minLength: 12)
                animationArea
                    .frame(height: 220)
                Spacer(minLength: 8)
                workloadProgressList
                    .padding(.horizontal, 32)
                Spacer(minLength: 4)
                bottomBar
                    .padding(.bottom, 24)
            }
            .padding(.top, 20)
        }
        .frame(width: 560, height: 620)
        .onAppear {
            // 打开即跑
            if !model.benchmarkRunning {
                model.runBenchmark()
            }
        }
    }

    // MARK: - 顶部

    private var topBar: some View {
        VStack(spacing: 4) {
            Text("CPU 性能跑分")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(model.benchmarkStage.title + (model.benchmarkRunning ? "…" : ""))
                .font(.caption)
                .foregroundStyle(model.benchmarkRunning ? .orange : .secondary)
        }
        .padding(.bottom, 12)
    }

    // MARK: - 分数区

    private var scoreRow: some View {
        HStack(spacing: 28) {
            scoreCard(title: "单核", score: singleScoreDisplay, color: model.accentColor)
            scoreCard(title: "多核", score: multiScoreDisplay, color: .orange)
        }
        .padding(.bottom, 8)
    }

    private func scoreCard(title: String, score: Int?, color: Color) -> some View {
        VStack(spacing: 0) {
            if let s = score {
                Text("\(s)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("--")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var singleScoreDisplay: Int? {
        model.benchmarkStage == .done ? model.benchmarkResult?.singleScore : nil
    }
    private var multiScoreDisplay: Int? {
        model.benchmarkStage == .done ? model.benchmarkResult?.multiScore : nil
    }

    // MARK: - 动画区（按 currentWorkload 切换）

    private var animationArea: some View {
        Group {
            switch model.currentWorkload {
            case .integer: HashCascadeView()
            case .float:   FloatCubeView()
            case .memory:  MemoryStreamView()
            case .bitwise: BitGridView()
            case nil:      IdlePulseView()
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.horizontal, 32)
    }

    // MARK: - 4 段进度条

    private var workloadProgressList: some View {
        VStack(spacing: 8) {
            ForEach(Benchmark.Workload.allCases, id: \.self) { w in
                HStack(spacing: 10) {
                    Text(w.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    stageProgress(for: w)
                        .frame(height: 10)
                }
            }
        }
    }

    /// 每负载进度：单核/多核各占一半，根据 stage + currentWorkload 填充
    private func stageProgress(for w: Benchmark.Workload) -> some View {
        let ws = Benchmark.Workload.allCases
        let idx = ws.firstIndex(of: w) ?? 0
        let total = ws.count
        // 单核进度 0..0.5，多核进度 0.5..1
        var singleP: Double = 0
        var multiP: Double = 0
        if model.benchmarkStage == .single, model.currentWorkload == w {
            singleP = Double(idx) / Double(total)
        } else if model.benchmarkStage == .single, let cw = model.currentWorkload, let ci = ws.firstIndex(of: cw), ci > idx {
            singleP = 1
        }
        if model.benchmarkStage == .multi, model.currentWorkload == w {
            multiP = Double(idx) / Double(total)
        } else if model.benchmarkStage == .multi, let cw = model.currentWorkload, let ci = ws.firstIndex(of: cw), ci > idx {
            multiP = 1
        }
        if model.benchmarkStage == .done {
            singleP = 1; multiP = 1
        }
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08)).frame(height: 10)
                HStack(spacing: 0) {
                    Rectangle().fill(model.accentColor)
                        .frame(width: geo.size.width * 0.5 * singleP, height: 10)
                    Rectangle().fill(Color.orange)
                        .frame(width: geo.size.width * 0.5 * multiP, height: 10)
                }
            }
        }
    }

    // MARK: - 底部按钮

    private var bottomBar: some View {
        HStack {
            Spacer()
            if model.benchmarkRunning {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.orange)
            } else if model.benchmarkStage == .done {
                Button("再跑一次") { model.runBenchmark() }
                    .buttonStyle(.borderedProminent)
                    .tint(model.accentColor)
            }
            Button(model.benchmarkStage == .done ? "完成" : "关闭") {
                model.benchmarkStage = .idle
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - 4 种负载动画

/// ① 整数：滚动哈希瀑布
struct HashCascadeView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            Canvas { c, size in
                let now = ctx.date.timeIntervalSinceReferenceDate
                let seed = UInt64(now * 1000)
                var rng = Seeded(seed: seed)
                let lineH: CGFloat = 18
                let count = Int(size.height / lineH) + 2
                let offset = CGFloat(now.truncatingRemainder(dividingBy: 0.6)) * 30
                for i in 0..<count {
                    let h = UInt64.random(in: 0...UInt64.max, using: &rng)
                    let str = String(h, radix: 16).padding(toLength: 16, withPad: "0", startingAt: 0)
                    var y = CGFloat(i) * lineH - offset
                    while y > size.height { y -= size.height }
                    if y < -lineH { continue }
                    let alpha = i < count - 1 ? 1.0 : 0.5
                    c.draw(
                        Text(str)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.orange.opacity(alpha)),
                        at: CGPoint(x: size.width / 2, y: y + lineH / 2)
                    )
                }
            }
        }
    }
}

/// ② 浮点：旋转 3D 立方体线框
struct FloatCubeView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
            Canvas { c, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2
                let cy = size.height / 2
                let s: CGFloat = min(size.width, size.height) * 0.32
                let ax = t * 0.9
                let ay = t * 1.4
                func rot(_ p: (Double,Double,Double)) -> (Double,Double) {
                    var (x, y, z) = p
                    let cy2 = cos(ay), sy = sin(ay)
                    let nx = x * cy2 + z * sy
                    let nz = -x * sy + z * cy2
                    x = nx; z = nz
                    let cx2 = cos(ax), sx2 = sin(ax)
                    let ny = y * cx2 - z * sx2
                    let nz2 = y * sx2 + z * cx2
                    y = ny; z = nz2
                    let persp = 6.0 / (6.0 + z)
                    return (cx + CGFloat(x * persp * s), cy + CGFloat(y * persp * s))
                }
                let verts: [(Double,Double,Double)] = [
                    (-1,-1,-1), (1,-1,-1), (1,1,-1), (-1,1,-1),
                    (-1,-1,1), (1,-1,1), (1,1,1), (-1,1,1)
                ]
                let p = verts.map(rot)
                let edges = [
                    (0,1),(1,2),(2,3),(3,0),
                    (4,5),(5,6),(6,7),(7,4),
                    (0,4),(1,5),(2,6),(3,7)
                ]
                let colors: [Color] = [.orange, .yellow, .pink, .red, .cyan, .purple, .green, .blue, .orange, .yellow, .pink, .red]
                for (i, e) in edges.enumerated() {
                    var path = Path()
                    path.move(to: CGPoint(x: p[e.0].0, y: p[e.0].1))
                    path.addLine(to: CGPoint(x: p[e.1].0, y: p[e.1].1))
                    c.stroke(path, with: .color(colors[i % colors.count].opacity(0.85)), lineWidth: 2)
                }
                for v in p {
                    c.fill(Path(ellipseIn: CGRect(x: v.0 - 3, y: v.1 - 3, width: 6, height: 6)),
                           with: .color(.white.opacity(0.9)))
                }
            }
        }
    }
}

/// ③ 内存：横向流动光带
struct MemoryStreamView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            Canvas { c, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let barRect = CGRect(x: 0, y: size.height - 30, width: size.width, height: 30)
                c.fill(Path(roundedRect: barRect, cornerRadius: 4),
                       with: .linearGradient(
                        Gradient(colors: [.purple, .blue]),
                        startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)
                       ))
                for i in 0..<6 {
                    let phase = t + Double(i) * 0.5
                    let x = (CGFloat(phase.truncatingRemainder(dividingBy: 4)) / 4) * size.width
                    c.fill(Path(ellipseIn: CGRect(x: x - 12, y: barRect.midY - 12, width: 24, height: 24)),
                           with: .radialGradient(
                            Gradient(colors: [.white.opacity(0.8), .clear]),
                            center: CGPoint(x: x, y: barRect.midY),
                            startRadius: 0, endRadius: 12
                           ))
                }
                for i in 0..<32 {
                    let phase = t * 2 + Double(i) * 0.3
                    let col = i % 8
                    let row = i / 8
                    let x = CGFloat(col) * (size.width / 8) + 4
                    let y = CGFloat(row) * 18 + 6
                    let alpha = (sin(phase) + 1) * 0.5 * 0.6 + 0.2
                    c.fill(Path(roundedRect: CGRect(x: x, y: y, width: size.width / 8 - 8, height: 12), cornerRadius: 2),
                           with: .color(.cyan.opacity(alpha)))
                }
            }
        }
    }
}

/// ④ 位运算：闪烁方块阵列
struct BitGridView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
            Canvas { c, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let cols = 16
                let rows = 8
                let cw = size.width / CGFloat(cols) * 0.85
                let ch = size.height / CGFloat(rows) * 0.85
                let ox = (size.width - CGFloat(cols) * (cw + 4)) / 2
                let oy = (size.height - CGFloat(rows) * (ch + 4)) / 2
                for r in 0..<rows {
                    for cidx in 0..<cols {
                        let phase = t * 4 + Double(r * cols + cidx) * 0.13
                        let bit = (Int(phase * 3) & 1) == 1
                        let alpha = bit ? 0.95 : 0.2
                        let color = bit ? Color.orange : Color.white.opacity(0.3)
                        let x = ox + CGFloat(cidx) * (cw + 4)
                        let y = oy + CGFloat(r) * (ch + 4)
                        c.fill(Path(roundedRect: CGRect(x: x, y: y, width: cw, height: ch), cornerRadius: 2),
                               with: .color(color.opacity(alpha)))
                    }
                }
            }
        }
    }
}

/// 待机（未跑分）
struct IdlePulseView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            Canvas { c, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let pulse = (sin(t * 2) + 1) * 0.5
                let cx = size.width / 2
                let cy = size.height / 2
                for r in stride(from: CGFloat(0), to: CGFloat(80), by: 8) {
                    let alpha = pulse * (1 - r / 80) * 0.5
                    c.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r * 0.6, width: r * 2, height: r * 1.2)),
                             with: .color(.orange.opacity(alpha)), lineWidth: 1)
                }
            }
        }
    }
}

/// 简易确定性随机
struct Seeded: RandomNumberGenerator {
    var seed: UInt64
    mutating func next() -> UInt64 {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return seed
    }
}
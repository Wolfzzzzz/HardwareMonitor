import SwiftUI

/// 高级界面（Premium Deluxe 专属）：传感器矩阵 / 风扇 / 性能评分 / 进程 / 自定义皮肤
struct PremiumView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.isPremium {
                    scoreSection
                    sensorMatrixSection
                    fanSection
                    processSection
                    customSkinSection
                } else {
                    lockedSection
                }
            }
            .padding(18)
        }
    }

    // MARK: 锁定提示

    private var lockedSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("高级功能仅 Premium Deluxe 可用")
                .font(.headline)
            Text("升级到 Premium Deluxe（¥68）解锁：传感器矩阵、风扇转速、性能健康评分、进程资源详情、自定义皮肤")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    // MARK: 性能健康评分

    private var scoreSection: some View {
        AdvancedCard(title: "性能健康评分", icon: "heart.text.square") {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(model.healthScore) / 100)
                        .stroke(model.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(model.healthScore)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(healthLabel).font(.headline)
                    Text("基于芯片温度、CPU 与内存占用综合评估")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var healthLabel: String {
        switch model.healthScore {
        case 90...: return "非常健康"
        case 75..<90: return "状态良好"
        case 60..<75: return "注意散热"
        default: return "需要关注"
        }
    }

    // MARK: 传感器矩阵

    private var sensorMatrixSection: some View {
        AdvancedCard(title: "传感器矩阵", icon: "square.grid.3x3") {
            let temps = model.snapshot.smcTemperatures.isEmpty ? model.snapshot.hidTemperatures : model.snapshot.smcTemperatures
            if temps.isEmpty {
                Text("暂无传感器数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(0..<temps.count, id: \.self) { idx in
                        let t = temps[idx]
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.0)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(String(format: "%.1f°", t.1))
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(tempColor(t.1))
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(model.themeCard)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.themeBorder, lineWidth: 0.5))
                        )
                    }
                }
            }
        }
    }

    private func tempColor(_ v: Double) -> Color {
        v > 90 ? .red : (v > 75 ? .orange : .green)
    }

    // MARK: 风扇

    private var fanSection: some View {
        AdvancedCard(title: "风扇转速", icon: "fan") {
            let fans = model.snapshot.smcFans
            if fans.isEmpty {
                Text("本机未检测到风扇（Apple Silicon 常无独立风扇转速接口）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(0..<fans.count, id: \.self) { idx in
                    let f = fans[idx]
                    HStack {
                        Text(f.0).font(.caption.monospaced())
                        Spacer()
                        Text("\(Int(f.1)) RPM")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: 进程资源

    private var processSection: some View {
        AdvancedCard(title: "进程资源 TOP 10", icon: "list.number") {
            let procs = model.snapshot.topProcesses
            if procs.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(0..<procs.count, id: \.self) { idx in
                        let p = procs[idx]
                        HStack(spacing: 8) {
                            Text("\(idx + 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(p.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(String(format: "%.0f%%", p.cpuPercent))
                                .font(.caption.monospacedDigit())
                            Text(String(format: "%.0f MB", p.memoryMB))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        if idx < procs.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    // MARK: 自定义皮肤

    private var customSkinSection: some View {
        AdvancedCard(title: "自定义皮肤", icon: "paintpalette") {
            Toggle("使用自定义强调色", isOn: Binding(
                get: { model.themeID == "custom" },
                set: { on in model.themeID = on ? "custom" : "aurora" }
            ))
            .toggleStyle(.switch)
            if model.themeID == "custom" {
                HStack {
                    ColorPicker("强调色", selection: Binding(
                        get: { model.colorFromHex(model.customAccentHex) },
                        set: { c in model.customAccentHex = c.toHex() }
                    ))
                    Spacer()
                }
                .padding(.top, 4)
            }
            Text("自定义色立即应用到全局（悬浮窗/主窗口/卡片）")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }
}

/// 高级卡片容器
private struct AdvancedCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

extension Color {
    /// Color → hex
    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .orange
        return String(format: "%02X%02X%02X",
                      Int(ns.redComponent * 255), Int(ns.greenComponent * 255), Int(ns.blueComponent * 255))
    }
}

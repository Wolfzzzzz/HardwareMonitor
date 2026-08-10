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
                    systemInfoSection
                    batteryReportSection
                    diskScanSection
                    benchmarkSection
                    alertHistorySection
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

    // MARK: 系统信息

    private var systemInfoSection: some View {
        AdvancedCard(title: "系统信息全览", icon: "info.circle") {
            infoRow("CPU", model.cpuBrand.isEmpty ? "Apple Silicon" : model.cpuBrand)
            infoRow("架构", model.chipArch)
            infoRow("核心数", "\(ProcessInfo.processInfo.activeProcessorCount) 核")
            infoRow("系统", model.systemVersion)
            infoRow("内存总量", Fmt.bytes(model.snapshot.memTotal))
            infoRow("磁盘", "\(Fmt.bytes(model.snapshot.diskFree)) 可用 / \(Fmt.bytes(model.snapshot.diskTotal))")
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }

    // MARK: 电池健康报告

    private var batteryReportSection: some View {
        AdvancedCard(title: "电池健康报告", icon: "battery.100") {
            let snap = model.snapshot
            if snap.batteryPresent == false {
                Text("未检测到电池")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                infoRow("健康度", snap.batteryHealth.map { "\($0)%" } ?? "--")
                infoRow("循环次数", snap.batteryCycles.map { "\($0) 次" } ?? "--")
                infoRow("当前电量", snap.batteryPercent.map { "\($0)%" } ?? "--")
                infoRow("充电状态", snap.batteryCharging ? "充电中" : "未充电")
                infoRow("电池温度", snap.batteryTempC.map { String(format: "%.1f°C", $0) } ?? "--")
                Text(batteryAdvice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private var batteryAdvice: String {
        guard let h = model.snapshot.batteryHealth, let c = model.snapshot.batteryCycles else { return "" }
        if c > 800 || h < 80 { return "💡 电池循环已较高，建议关注电池寿命，长期插电使用时可开启低电量模式。" }
        if c > 400 { return "💡 电池状态良好，建议避免经常用到 0% 再充电。" }
        return "💡 电池状态健康，保持 20%-80% 区间使用效果最佳。"
    }

    // MARK: 磁盘大文件扫描

    private var diskScanSection: some View {
        AdvancedCard(title: "磁盘大文件扫描", icon: "internaldrive") {
            HStack {
                Text(model.scanningDisk ? "扫描中，请稍候…" : "扫描主目录中 ≥50MB 的大文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.scanningDisk ? "扫描中…" : "开始扫描") { model.scanBigFiles() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.scanningDisk)
            }
            if !model.bigFiles.isEmpty {
                VStack(spacing: 0) {
                    ForEach(0..<min(model.bigFiles.count, 10), id: \.self) { idx in
                        let f = model.bigFiles[idx]
                        HStack(spacing: 8) {
                            Text("\(idx + 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(f.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(Fmt.bytes(UInt64(f.size)))
                                .font(.caption.monospacedDigit())
                        }
                        .padding(.vertical, 4)
                        if idx < min(model.bigFiles.count, 10) - 1 { Divider() }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: CPU 跑分

    private var benchmarkSection: some View {
        AdvancedCard(title: "CPU 性能跑分", icon: "gauge.with.dots.needle.67percent") {
            HStack {
                if let score = model.benchmarkScore {
                    Text("\(score)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(model.accentColor)
                    Text("多核得分（越大越快）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.benchmarkRunning ? "跑分中…（约 10 秒）" : "测试 CPU 多线程性能")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.benchmarkRunning ? "跑分中…" : (model.benchmarkScore == nil ? "开始跑分" : "重测")) {
                    model.runBenchmark()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.benchmarkRunning)
            }
        }
    }

    // MARK: 告警历史

    private var alertHistorySection: some View {
        AdvancedCard(title: "告警历史", icon: "bell.badge") {
            let items = model.alertHistory
            if items.isEmpty {
                Text("暂无告警记录（告警触发后会记录在这里）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(0..<min(items.count, 15), id: \.self) { idx in
                        let a = items[idx]
                        HStack(alignment: .top, spacing: 8) {
                            Text(a.time, style: .time)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.title).font(.caption.weight(.semibold))
                                Text(a.body).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        if idx < min(items.count, 15) - 1 { Divider() }
                    }
                }
                if items.count > 15 {
                    Text("另有 \(items.count - 15) 条…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button("清空记录") { model.clearAlertHistory() }
                    .controlSize(.small)
                    .padding(.top, 2)
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
        .glassBackground(cornerRadius: 12)
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

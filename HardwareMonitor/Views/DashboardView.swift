import SwiftUI

/// 悬浮小窗主界面：概览卡片网格 + 图表 + 进程排行
struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            header
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    if model.showTemp { tempCard }
                    if model.showCPU { cpuCard }
                    if model.showMemory { memoryCard }
                    if model.showDisk { diskCard }
                    if model.showBattery { batteryCard }
                    if model.showNetwork { networkCard }
                    if model.showBrightness { brightnessCard }
                }

                if model.showTemp, !allTemps.isEmpty {
                    DisclosureGroup(isExpanded: $model.showTempDetail) {
                        tempDetailList
                            .padding(.top, 6)
                    } label: {
                        Label("温度详情（\(allTemps.count) 个传感器）", systemImage: "thermometer.variable")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.top, 4)
                }

                if model.showMemory || model.showDisk || model.showProcess {
                    DisclosureGroup(isExpanded: $model.showDetailCharts) {
                        DetailChartsView(snapshot: model.snapshot)
                            .padding(.top, 6)
                    } label: {
                        Label("占比图与柱状图", systemImage: "chart.pie")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.top, 4)
                }

                if model.showProcess {
                    DisclosureGroup(isExpanded: $model.showProcessPanel) {
                        ProcessListView(processes: model.snapshot.topProcesses)
                            .padding(.top, 6)
                    } label: {
                        Label("进程资源占用 TOP 10", systemImage: "list.number")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.top, 4)
                }
            }

            if model.showCPU || model.showMemory || model.showNetwork || model.showTemp {
                DisclosureGroup(isExpanded: $model.showCharts) {
                    ChartsView(history: model.chartHistory)
                        .padding(.top, 6)
                } label: {
                    Label("趋势图", systemImage: "chart.xyaxis.line")
                        .font(.caption.weight(.semibold))
                }
            }

            footer
        }
        .padding(14)
        .frame(width: 400, height: 600)
        .background(
            LinearGradient(colors: model.themeGradient, startPoint: .top, endPoint: .bottom)
        )
    }

    /// 当前温度来源列表（HID 优先，SMC 备用）
    private var allTemps: [(key: String, value: Double)] {
        if !model.snapshot.hidTemperatures.isEmpty { return model.snapshot.hidTemperatures }
        return model.snapshot.smcTemperatures
    }

    private var tempDetailList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(allTemps.sorted { $0.value > $1.value }, id: \.key) { t in
                    HStack {
                        Text(t.key)
                            .font(.caption2)
                        Spacer()
                        Text(String(format: "%.1f°C", t.value))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(t.value >= 70 ? .red : (t.value >= 60 ? .orange : .primary))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
            }
        }
        .frame(maxHeight: 160)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .foregroundStyle(.blue)
            Text("硬件监控")
                .font(.headline)
            Spacer()
            if let src = model.tempSource {
                Text(src == "SMC" ? "SMC" : "HID 传感器")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if !model.temperatureAvailable {
                Text("温度不可用")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Button {
                model.hidePanel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        HStack {
            Text("刷新 \(Int(model.refreshInterval))s")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if model.snapshot.smcFans.isEmpty {
                Text("风扇需系统权限")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("风扇 \(String(format: "%.0f rpm", model.snapshot.smcFans.first?.rpm ?? 0))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(Fmt.temp(model.snapshot.referenceTempC))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 卡片

    private var tempCard: some View {
        StatCard(
            title: "温度",
            icon: "thermometer",
            color: .orange,
            value: tempValue,
            sub: tempSub,
            progress: tempProgress
        )
    }

    private var tempValue: String {
        if let t = model.snapshot.cpuTempC { return Fmt.temp(t) }
        if let t = model.snapshot.batteryTempC { return Fmt.temp(t) }
        return model.temperatureAvailable ? "--" : "不可用"
    }
    private var tempSub: String {
        if let t = model.snapshot.cpuTempC {
            return "GPU " + Fmt.temp(model.snapshot.gpuTempC) + " · \(model.snapshot.hidTemperatures.count) 个传感器"
        }
        if let t = model.snapshot.batteryTempC { return LZ.t("电池 ", "Battery ") + Fmt.temp(t) }
        return "系统未开放温度接口"
    }
    private var tempProgress: Double? {
        guard let t = model.snapshot.referenceTempC else { return nil }
        return max(0, min(1, t / 110))
    }

    private var cpuCard: some View {
        StatCard(
            title: "CPU 占用",
            icon: "cpu",
            color: .blue,
            value: String(format: "%.0f%%", model.snapshot.cpuPercentValue),
            sub: "\(ProcessInfo.processInfo.activeProcessorCount) 核",
            progress: model.snapshot.cpuUsage
        )
    }

    private var memoryCard: some View {
        StatCard(
            title: "内存",
            icon: "memorychip",
            color: .purple,
            value: String(format: "%.0f%%", model.snapshot.memPercentValue * 100),
            sub: "\(Fmt.bytes(model.snapshot.memUsed)) / \(Fmt.bytes(model.snapshot.memTotal))",
            progress: model.snapshot.memPercent
        )
    }

    private var diskCard: some View {
        StatCard(
            title: "磁盘",
            icon: "internaldrive",
            color: .teal,
            value: String(format: "%.0f%%", model.snapshot.diskPercentValue * 100),
            sub: "剩余 \(Fmt.bytes(model.snapshot.diskFree)) / \(Fmt.bytes(model.snapshot.diskTotal))",
            progress: model.snapshot.diskPercent
        )
    }

    private var batteryCard: some View {
        StatCard(
            title: "电池",
            icon: batteryIcon,
            color: .green,
            value: model.snapshot.batteryPercent.map { "\($0)%" } ?? "--",
            sub: batterySub,
            progress: model.snapshot.batteryPercent.map { Double($0) / 100 }
        )
    }
    private var batteryIcon: String {
        model.snapshot.batteryCharging ? "battery.100percent.bolt" : "battery.75percent"
    }
    private var batterySub: String {
        var parts: [String] = []
        if let h = model.snapshot.batteryHealthDisplay { parts.append("健康 \(h)%") }
        if let c = model.snapshot.batteryCycles { parts.append("\(c) 次") }
        if model.snapshot.batteryCharging { parts.append("充电中") }
        return parts.isEmpty ? "未检测到电池" : parts.joined(separator: " · ")
    }

    private var networkCard: some View {
        StatCard(
            title: "网络",
            icon: "arrow.up.arrow.down",
            color: .cyan,
            value: Fmt.speed(model.snapshot.netDown),
            sub: "↑ " + Fmt.speed(model.snapshot.netUp),
            progress: nil
        )
    }

    private var brightnessCard: some View {
        StatCard(
            title: "屏幕亮度",
            icon: "sun.max",
            color: .yellow,
            value: model.snapshot.brightness.map { String(format: "%.0f%%", $0 * 100) } ?? "--",
            sub: "等级 \(model.snapshot.brightness.map { String(format: "%.1f", $0 * 10) } ?? "--") / 10",
            progress: model.snapshot.brightness
        )
    }
}

/// 通用统计卡片
struct StatCard: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let icon: String
    let color: Color
    let value: String
    let sub: String
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(sub)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let p = progress {
                ProgressView(value: max(0, min(1, p)))
                    .tint(color)
                    .scaleEffect(y: 0.6)
                    .frame(height: 6)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(model.themeCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(model.themeBorder, lineWidth: 1)
                )
        )
    }
}

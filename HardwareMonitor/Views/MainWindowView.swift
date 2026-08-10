import SwiftUI

/// 主窗口界面（平时隐藏，菜单栏「打开主界面」显示；关闭即隐藏）
struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
            Picker("", selection: $model.mainTab) {
                Text("监控").tag(0)
                Text("剪贴板").tag(1)
                Text("工具").tag(2)
                Text("专业").tag(3)
                Text("高级").tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            if model.mainTab == 0 {
                monitorContent
            } else if model.mainTab == 1 {
                ClipboardView()
                    .environmentObject(model)
            } else if model.mainTab == 2 {
                ToolsView()
                    .environmentObject(model)
            } else if model.mainTab == 3 {
                ProView()
                    .environmentObject(model)
            } else {
                PremiumView()
                    .environmentObject(model)
            }
        }
        .onAppear { model.setMainWindowVisible(true) }
        .onDisappear { model.setMainWindowVisible(false) }
        .tint(model.accentColor)
        .preferredColorScheme(model.preferredColorScheme)
        .frame(minWidth: 780, minHeight: 560)
        .background(
            LinearGradient(colors: model.themeGradient, startPoint: .top, endPoint: .bottom)
                .overlay(Color.black.opacity(0.25))
        )
    }

    /// 监控页内容
    private var monitorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                overviewGrid
                Divider()
                HStack(alignment: .top, spacing: 14) {
                    trendsColumn
                    rightColumn
                }
                Divider()
                processSection
            }
            .padding(18)
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("硬件监控")
                .font(.title2.weight(.bold))
            if let src = model.tempSource {
                Text(src == "SMC" ? "SMC 数据" : "HID 传感器")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
            }
            Spacer()
            Text(LZ.t("更新于 ", "Updated ") + (model.lastUpdated.map { Fmt.time($0) } ?? "--"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("刷新 \(Int(model.refreshInterval))s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 概览卡片

    /// 温度卡副标题（GPU + 风扇，风扇为 Deluxe 功能）
    private var tempSubText: String {
        var s = model.snapshot.gpuTempC.map { "GPU " + Fmt.temp($0) } ?? "GPU 该机型不提供"
        if model.isDeluxe, let fan = model.snapshot.smcFans.first {
            s += " · 风扇 \(Int(fan.1)) RPM"
        }
        return s
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatCard(title: "芯片温度", icon: "thermometer", color: .orange,
                     value: Fmt.temp(model.snapshot.cpuTempC),
                     sub: tempSubText,
                     progress: model.snapshot.referenceTempC.map { max(0, min(1, $0 / 110)) })
            StatCard(title: "CPU 占用", icon: "cpu", color: .blue,
                     value: String(format: "%.0f%%", model.snapshot.cpuPercentValue),
                     sub: "\(ProcessInfo.processInfo.activeProcessorCount) 核",
                     progress: model.snapshot.cpuUsage)
            StatCard(title: "内存", icon: "memorychip", color: .purple,
                     value: String(format: "%.0f%%", model.snapshot.memPercentValue * 100),
                     sub: "\(Fmt.bytes(model.snapshot.memUsed)) / \(Fmt.bytes(model.snapshot.memTotal))",
                     progress: model.snapshot.memPercent)
            StatCard(title: "磁盘", icon: "internaldrive", color: .teal,
                     value: String(format: "%.0f%%", model.snapshot.diskPercentValue * 100),
                     sub: "剩余 \(Fmt.bytes(model.snapshot.diskFree))",
                     progress: model.snapshot.diskPercent)
            StatCard(title: "电池", icon: model.snapshot.batteryCharging ? "battery.100percent.bolt" : "battery.75percent",
                     color: .green,
                     value: model.snapshot.batteryPercent.map { "\($0)%" } ?? "--",
                     sub: batterySub,
                     progress: model.snapshot.batteryPercent.map { Double($0) / 100 })
            StatCard(title: "网络下行", icon: "arrow.down", color: .cyan,
                     value: Fmt.speed(model.snapshot.netDown),
                     sub: LZ.t("上行 ", "Up ") + Fmt.speed(model.snapshot.netUp),
                     progress: nil)
            StatCard(title: "屏幕亮度", icon: "sun.max", color: .yellow,
                     value: model.snapshot.brightness.map { String(format: "%.0f%%", $0 * 100) } ?? "--",
                     sub: "等级 \(model.snapshot.brightness.map { String(format: "%.1f", $0 * 10) } ?? "--") / 10",
                     progress: model.snapshot.brightness)
            StatCard(title: "风扇", icon: "fan", color: .gray,
                     value: model.snapshot.smcFans.first.map { String(format: "%.0f rpm", $0.rpm) } ?? "--",
                     sub: model.snapshot.smcFans.isEmpty ? "需系统权限" : "\(model.snapshot.smcFans.count) 个风扇",
                     progress: nil)
        }
    }

    private var batterySub: String {
        var parts: [String] = []
        if let h = model.snapshot.batteryHealthDisplay { parts.append("健康 \(h)%") }
        if let c = model.snapshot.batteryCycles { parts.append("\(c) 次") }
        if let t = model.snapshot.batteryTempC { parts.append(String(format: "%.0f°C", t)) }
        return parts.isEmpty ? "未检测到电池" : parts.joined(separator: " · ")
    }

    // MARK: 左列：趋势曲线

    private var trendsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("实时趋势")
                .font(.headline)
            ChartsView(history: model.chartHistory)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 右列：温度详情 + 饼图柱状图

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            tempDetail
            DetailChartsView(snapshot: model.snapshot)
        }
        .frame(width: 360)
    }

    private var allTemps: [(key: String, value: Double)] {
        if !model.snapshot.hidTemperatures.isEmpty { return model.snapshot.hidTemperatures }
        return model.snapshot.smcTemperatures
    }

    private var tempDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("全部温度传感器（\(allTemps.count)）")
                .font(.subheadline.weight(.semibold))
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(allTemps.sorted { $0.value > $1.value }, id: \.key) { t in
                        HStack {
                            Text(t.key)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1f°C", t.value))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(t.value >= 70 ? .red : (t.value >= 60 ? .orange : .primary))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    // MARK: 进程区

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("进程资源占用 TOP 10")
                .font(.headline)
            HStack(alignment: .top, spacing: 14) {
                ProcessListView(processes: model.snapshot.topProcesses)
                    .frame(maxWidth: .infinity)
                DetailChartsView(snapshot: model.snapshot).processOnly
            }
        }
    }
}

// 给进程柱状图提供单独暴露
extension DetailChartsView {
    /// 仅进程柱状图（主窗口进程区用）
    var processOnly: some View { processBar }
}

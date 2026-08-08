import SwiftUI

/// 设置页（中文）
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    private var tempDetail: String {
        if model.smcAvailable { return "SMC 可用" }
        if model.hidAvailable { return "HID 传感器可用（CPU 温度 = 芯片 tdie 最大值）" }
        return "当前系统未开放温度接口"
    }

    var body: some View {
        Form {
            Section("刷新与采样") {
                Picker("刷新间隔", selection: $model.refreshInterval) {
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                    Text("3 秒").tag(3.0)
                    Text("5 秒").tag(5.0)
                }
                .pickerStyle(.segmented)
                .onChange(of: model.refreshInterval) { _ in
                    model.restartSampling()
                }
                Text("刷新间隔越小，数据越实时，占用会略高")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("启用告警", isOn: $model.alertsEnabled)
                Toggle("告警提示音", isOn: $model.alertSound)
            } header: {
                Text("告警开关")
            }

            Section("告警阈值") {
                ThresholdRow(
                    title: "CPU 温度",
                    detail: tempDetail,
                    value: $model.cpuTempThreshold,
                    unit: "°C", range: 60...105, step: 5
                )
                ThresholdRow(
                    title: "GPU 温度",
                    detail: tempDetail,
                    value: $model.gpuTempThreshold,
                    unit: "°C", range: 65...110, step: 5
                )
                ThresholdRow(
                    title: "CPU 占用率",
                    detail: nil,
                    value: $model.cpuUsageThreshold,
                    unit: "%", range: 50...100, step: 5
                )
                ThresholdRow(
                    title: "内存占用率",
                    detail: nil,
                    value: $model.memUsageThreshold,
                    unit: "%", range: 50...100, step: 5
                )
                ThresholdRow(
                    title: "磁盘剩余空间",
                    detail: nil,
                    value: $model.diskFreeThreshold,
                    unit: "GB", range: 5...100, step: 5
                )
                ThresholdRow(
                    title: "电池电量",
                    detail: nil,
                    value: $model.batteryPercentThreshold,
                    unit: "%", range: 5...50, step: 5
                )
            }

            Section("悬浮窗显示模块") {
                Toggle("温度与风扇", isOn: $model.showTemp)
                Toggle("CPU 占用", isOn: $model.showCPU)
                Toggle("内存", isOn: $model.showMemory)
                Toggle("磁盘", isOn: $model.showDisk)
                Toggle("电池", isOn: $model.showBattery)
                Toggle("网络", isOn: $model.showNetwork)
                Toggle("屏幕亮度", isOn: $model.showBrightness)
                Toggle("进程排行", isOn: $model.showProcess)
            }

            Section("开机自启") {
                Toggle("登录时自动启动", isOn: $model.launchAtLogin)
                    .onChange(of: model.launchAtLogin) { _ in
                        model.toggleLaunchAtLogin()
                    }
                if let err = model.launchAtLoginError {
                    Text("自启设置失败：\(err)\n请将 App 拖入「应用程序」文件夹后再试")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("数据来源") {
                    Text("IOKit / 系统内核接口")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("版本") {
                    Text("1.0.0").foregroundStyle(.secondary)
                }
            } header: {
                Text("关于")
            } footer: {
                Text("本应用仅读取硬件数据，不进行任何写入或调节。\n温度与风扇依赖系统 SMC 接口：当前 macOS 27 beta 未开放时自动降级为电池温度参考。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("硬件监控设置")
    }
}

/// 阈值调节行
struct ThresholdRow: View {
    let title: String
    let detail: String?
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) \(unit)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
                .tint(.blue)
        }
        .padding(.vertical, 2)
    }
}

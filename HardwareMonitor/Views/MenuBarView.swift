import SwiftUI

/// 菜单栏点击后的概览窗口
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private func openMainWindow() {
        openWindow(id: "main")
        // 等 SwiftUI 创建完窗口再提到最前（菜单栏 App 窗口默认落在底层）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            model.activateMainWindow()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            overviewGrid
            Divider()
            actions
        }
        .padding(12)
        .frame(width: 300)
    }

    private var header: some View {
        HStack {
            Text("硬件监控")
                .font(.headline)
            Spacer()
            if let t = model.lastUpdated {
                Text(LZ.t("更新于 ", "Updated ") + Fmt.time(t))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            MenuStatRow(icon: "cpu", title: "CPU 占用", value: String(format: "%.0f%%", model.snapshot.cpuPercentValue))
            MenuStatRow(icon: "memorychip", title: "内存", value: String(format: "%.0f%%", model.snapshot.memPercentValue * 100))
            MenuStatRow(icon: "internaldrive", title: "磁盘已用", value: String(format: "%.0f%%", model.snapshot.diskPercentValue * 100))
            MenuStatRow(icon: "battery.75percent", title: "电池电量", value: batteryText)
            MenuStatRow(icon: "sun.max", title: "屏幕亮度", value: brightnessText)
            MenuStatRow(icon: "arrow.up.arrow.down", title: "网络", value: netText)
            MenuStatRow(icon: "thermometer", title: "芯片温度", value: tempText)
            MenuStatRow(icon: "fan", title: "风扇", value: fanText)
        }
    }

    private var batteryText: String {
        guard let p = model.snapshot.batteryPercent else { return "--" }
        let bolt = model.snapshot.batteryCharging ? "⚡" : ""
        return "\(p)%\(bolt)"
    }

    private var brightnessText: String {
        guard let b = model.snapshot.brightness else { return "--" }
        return String(format: "%.0f%%", b * 100)
    }

    private var netText: String {
        let d = Fmt.speed(model.snapshot.netDown)
        let u = Fmt.speed(model.snapshot.netUp)
        return "↓\(d) ↑\(u)"
    }

    private var tempText: String {
        if let t = model.snapshot.cpuTempC { return Fmt.temp(t) }
        if let t = model.snapshot.batteryTempC { return Fmt.temp(t) + "(电池)" }
        return model.temperatureAvailable ? "--" : "不可用"
    }

    private var fanText: String {
        if let f = model.snapshot.smcFans.first { return String(format: "%.0f rpm", f.rpm) }
        return "--"
    }

    private var actions: some View {
        VStack(spacing: 2) {
            Button {
                openMainWindow()
            } label: {
                Label("打开主界面", systemImage: "macwindow.on.rectangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                model.togglePanel()
            } label: {
                Label(model.isPanelVisible ? "隐藏悬浮窗" : "显示悬浮窗", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                openSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    model.activateSettingsWindow()
                }
            } label: {
                Label("设置…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                model.quit()
            } label: {
                Label("退出", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

/// 菜单栏小行
struct MenuStatRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }
}

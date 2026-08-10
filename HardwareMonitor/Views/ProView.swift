import SwiftUI
import AppKit

/// 专业功能页：远程监控 / 外观主题 / 报告导出 / 压力测试 / 启动项 / 快捷键
struct ProView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                remoteSection
                appearanceSection
                reportSection
                pressureSection
                launchItemsSection
                hotkeySection
            }
            .padding(18)
        }
    }

    // MARK: 远程监控

    private var remoteSection: some View {
        SectionCard(title: "局域网远程监控", icon: "wifi") {
            Toggle("开启远程监控服务", isOn: Binding(
                get: { model.remoteRunning },
                set: { if $0 { model.startRemote() } else { model.stopRemote() } }
            ))
            .toggleStyle(.switch)

            if model.remoteRunning {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("访问地址")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("复制") {
                            if let url = model.remoteURLString {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url, forType: .string)
                            }
                        }
                        .controlSize(.small)
                    }
                    if let url = model.remoteURLString {
                        Text(url)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    HStack {
                        Text("端口")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", value: Binding(
                            get: { Double(model.remotePort) },
                            set: { model.remotePort = Int($0) }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    }
                    Text("同一 WiFi 下，用手机/平板浏览器打开上面的地址，即可实时查看本机状态。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: 外观

    private var appearanceSection: some View {
        SectionCard(title: "外观与主题", icon: "paintpalette") {
            HStack {
                Text("主题皮肤")
                Spacer()
                Picker("", selection: $model.themeID) {
                    ForEach(0..<AppThemes.all.count, id: \.self) { idx in
                        let t = AppThemes.all[idx]
                        Label {
                            Text(t.name)
                        } icon: {
                            Circle().fill(t.accent).frame(width: 10, height: 10)
                        }
                        .tag(t.id)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            HStack(spacing: 6) {
                ForEach(0..<AppThemes.all.count, id: \.self) { idx in
                    let t = AppThemes.all[idx]
                    Circle()
                        .fill(t.accent)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle().stroke(Color.white.opacity(model.themeID == t.id ? 0.9 : 0.25), lineWidth: 2)
                        )
                        .scaleEffect(model.themeID == t.id ? 1.15 : 1.0)
                        .onTapGesture { model.themeID = t.id }
                }
                Spacer()
                Text("点击色点快速切换")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("外观模式")
                Spacer()
                Picker("", selection: $model.appearanceID) {
                    Text("跟随系统").tag("system")
                    Text("深色").tag("dark")
                    Text("浅色").tag("light")
                }
                .labelsHidden()
                .frame(width: 130)
            }
            Toggle("Dock 图标显示 CPU 温度角标", isOn: $model.dockBadgeEnabled)
                .toggleStyle(.switch)
        }
    }

    // MARK: 报告导出

    private var reportSection: some View {
        SectionCard(title: "性能报告导出", icon: "doc.badge.arrow.up") {
            HStack {
                Text("导出最近 \(model.history.count) 条采样记录（温度/CPU/内存/网络）为 CSV")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("导出 CSV") { model.exportHistoryCSV() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.history.isEmpty)
            }
        }
    }

    // MARK: 压力测试

    private var pressureSection: some View {
        SectionCard(title: "CPU 压力测试", icon: "flame") {
            HStack {
                Text("线程数")
                Stepper("\(Int(model.pressureThreads))", value: $model.pressureThreads, in: 1...32)
                    .frame(width: 120)
                Spacer()
                if model.pressureRunning {
                    Button("停止") { model.togglePressure() }
                        .buttonStyle(.bordered)
                } else {
                    Button("开始") { model.togglePressure() }
                        .buttonStyle(.borderedProminent)
                }
            }
            Text("用于散热与稳定性测试。测试期间 CPU 会满负荷运行，注意温度！结束后温度曲线会留在趋势图里。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 启动项

    private var launchItemsSection: some View {
        SectionCard(title: "启动项管理（只读）", icon: "gearshape.2") {
            let items = LaunchItems.scan()
            if items.isEmpty {
                Text("未发现启动项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LaunchItemsList(items: items)
                Button("打开 LaunchAgents 文件夹") { LaunchItems.openUserFolder() }
                    .controlSize(.small)
                    .padding(.top, 4)
                Text("此处仅展示，不做修改；如需管理请在文件夹中操作。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: 快捷键

    private var hotkeySection: some View {
        SectionCard(title: "全局快捷键", icon: "keyboard") {
            Toggle("启用全局快捷键", isOn: $model.hotkeysEnabled)
                .toggleStyle(.switch)
            if model.hotkeysEnabled {
                VStack(spacing: 4) {
                    hotkeyRow("显示 / 隐藏悬浮窗", "⌃⌘⌥H")
                    hotkeyRow("锁屏", "⌃⌘⌥L")
                    hotkeyRow("显示器休眠", "⌃⌘⌥S")
                    hotkeyRow("清空剪贴板历史", "⌃⌘⌥C")
                }
                .padding(.top, 2)
            }
        }
    }

    private func hotkeyRow(_ name: String, _ key: String) -> some View {
        HStack {
            Text(name).font(.caption)
            Spacer()
            Text(key)
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
        }
    }
}

/// 启动项列表（文本拼接展示，避免动态行视图）
private struct LaunchItemsList: View {
    let items: [LaunchItem]

    var body: some View {
        Text(items.map { ($0.user ? "· " : "· ") + $0.name }.joined(separator: "\n"))
            .font(.caption.monospaced())
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 分区卡片容器
private struct SectionCard<Content: View>: View {
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

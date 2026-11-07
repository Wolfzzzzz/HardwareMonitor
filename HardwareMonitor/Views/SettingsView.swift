import SwiftUI

/// 设置页（中文）
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    private var tempDetail: LocalizedStringKey {
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
                .onChange(of: model.refreshInterval) { _, _ in
                    model.restartSampling()
                }
                Text("刷新间隔越小，数据越实时，占用会略高")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("启用告警", isOn: $model.alertsEnabled)
                Toggle("告警提示音", isOn: $model.alertSound)
                Button("检查通知权限") { model.checkNotificationPermission() }
                if let msg = model.notificationStatusMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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

            Section {
                Picker("显示内容", selection: Binding(
                    get: { model.menuBarStyle },
                    set: { model.menuBarStyle = $0 }
                )) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Toggle("显示图标", isOn: Binding(
                    get: { model.menuBarShowIcon },
                    set: { model.menuBarShowIcon = $0 }
                ))
                Toggle("显示数值文字", isOn: Binding(
                    get: { model.menuBarShowText },
                    set: { model.menuBarShowText = $0 }
                ))
                LabeledContent("当前预览") {
                    Text(model.menuBarText)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(model.menuBarColor)
                }
            } header: {
                Text("菜单栏显示")
            } footer: {
                Text("只显示图标最省空间；开启数值文字后可直接在菜单栏看实时读数。图标与文字都关闭时会自动回退为图标。")
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
                    .onChange(of: model.launchAtLogin) { _, _ in
                        model.toggleLaunchAtLogin()
                    }
                if let err = model.launchAtLoginError {
                    Text("自启设置失败：\(err)\n请将 App 拖入「应用程序」文件夹后再试")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("启用噪音检测", isOn: Binding(
                    get: { model.focusNoise.enabled },
                    set: { model.focusNoise.setEnabled($0) }
                ))
                Text(model.focusNoise.authorized ? "麦克风权限已授权" : "未授权：开启噪音检测时会请求麦克风权限")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Divider()
                Toggle("番茄钟结束提示音", isOn: Binding(
                    get: { model.focusSound.enabled },
                    set: { model.focusSound.enabled = $0 }
                ))

                Picker("音源", selection: Binding(
                    get: { model.focusSound.useCustom ? 1 : 0 },
                    set: { model.focusSound.useCustom = ($0 == 1) }
                )) {
                    Text("内置音效").tag(0)
                    Text("自定义音频").tag(1)
                }
                .pickerStyle(.segmented)

                if model.focusSound.useCustom {
                    HStack(spacing: 8) {
                        Text(model.focusSound.customFileName ?? "尚未选择音频文件")
                            .font(.caption)
                            .foregroundStyle(model.focusSound.customFileName == nil ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer()
                        Button("选择…") { model.focusSound.importCustomFile() }
                            .controlSize(.small)
                        if model.focusSound.customFileName != nil {
                            Button("移除") { model.focusSound.removeCustom() }
                                .controlSize(.small)
                        }
                    }
                } else {
                    Picker("内置音效", selection: Binding(
                        get: { model.focusSound.systemSoundName },
                        set: { newValue in
                            model.focusSound.systemSoundName = newValue
                            model.focusSound.preview()
                        }
                    )) {
                        ForEach(FocusSoundPlayer.systemSounds, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Image(systemName: model.focusSound.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { model.focusSound.volume },
                        set: { model.focusSound.volume = $0 }
                    ), in: 0...1)
                    Text("\(Int(model.focusSound.volume * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Button("试听提示音") { model.focusSound.preview() }
                    Spacer()
                    Text(model.focusSound.currentDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("专注与噪音")
            } footer: {
                Text("噪音检测关闭后完全不占用麦克风，系统麦克风指示灯会熄灭。\n提示音支持内置音效或自定义音频文件（mp3 / wav / m4a / aiff / caf），可单独调音量。")
            }

            Section {
                Toggle("启用背景照片", isOn: Binding(
                    get: { model.focusBackground.enabled },
                    set: { model.focusBackground.enabled = $0 }
                ))
                HStack(spacing: 8) {
                    Text(model.focusBackground.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("选择照片…") { model.focusBackground.importImage() }
                        .controlSize(.small)
                    if model.focusBackground.hasImage {
                        Button("移除") { model.focusBackground.removeImage() }
                            .controlSize(.small)
                    }
                }
                HStack(spacing: 10) {
                    Text("蒙版强度").font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { model.focusBackground.overlayOpacity },
                        set: { model.focusBackground.overlayOpacity = $0 }
                    ), in: 0.25...0.9)
                    Text("\(Int(model.focusBackground.overlayOpacity * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }
            } header: {
                Text("专注界面背景")
            } footer: {
                Text("照片会复制到应用支持目录，原始文件不会被改动。照片上自动叠加黑色蒙版（最低 25%），保证专注页与全屏专注的文字清晰。")
            }

            Section {
                Button("重新播放新手引导") {
                    UserDefaults.standard.set(false, forKey: "onboardingCompletedV1")
                    NotificationCenter.default.post(name: .restartOnboardingTour, object: nil)
                }
            } header: {
                Text("新手引导")
            }

            Section {
                Toggle("液态玻璃流动光效", isOn: $model.glassMotionEnabled)
                Text("卡片上只有一条极淡的高光带缓慢扫过，鼠标移入时略微变亮。这层光带用系统图层动画驱动，不逐帧重绘。关闭后是静态玻璃，侧边栏选中行也会去掉那层极淡的液态光晕。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: {
                Text("液态玻璃")
            } footer: {
                Text("系统开启「减少动态效果」时会自动变为静态。动画只重绘玻璃层，不会连带刷新监控数据。")
            }

            Section {
                LabeledContent("数据来源") {
                    Text("IOKit / 系统内核接口")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("版本") {
                    Text(AppVersion.display).foregroundStyle(.secondary)
                }
            } header: {
                Text("关于")
            } footer: {
                Text("本应用仅读取硬件数据，不进行任何写入或调节。\n温度与风扇依赖系统 SMC 接口：当前 macOS 27 beta 未开放时自动降级为电池温度参考。")
            }

            Section {
                Link("通过邮件反馈", destination: URL(string: "mailto:zhang429500@icloud.com?subject=HardwareMonitor%20反馈")!)
                Link("在 GitHub 提交 Issue", destination: URL(string: "https://github.com/Wolfzzzzz/HardwareMonitor/issues")!)
            } header: {
                Text("反馈")
            }

            Section {
                Picker("语言 / Language", selection: $model.pendingLanguage) {
                    Text("跟随系统").tag("system")
                    Text("English").tag("en")
                    Text("Français").tag("fr")
                    Text("简体中文（中国大陆）").tag("zh-Hans")
                    Text("繁體中文（香港）").tag("zh-Hant-HK")
                    Text("繁體中文（台灣）").tag("zh-Hant-TW")
                    Text("Русский").tag("ru")
                }
                .pickerStyle(.menu)
                .onChange(of: model.pendingLanguage) { _, _ in
                    model.requestLanguageConfirm()
                }
                .alert("切换语言", isPresented: $model.showLanguageConfirm) {
                    Button("重启生效") { model.confirmPendingLanguage() }
                    Button("取消", role: .cancel) { model.cancelPendingLanguage() }
                } message: {
                    Text("切换语言后应用会自动重启以生效")
                }
            } header: {
                Text("语言 / Language")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("硬件监控设置")
    }
}

/// 阈值调节行（title/detail 走 LocalizedStringKey，自动按当前语言查表）
struct ThresholdRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    @Binding var value: Double
    let unit: String  // °C 这种通用符号各语言一致，无需翻译
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

extension Notification.Name {
    /// 设置页触发：重新播放新手引导（由主窗口接收）
    static let restartOnboardingTour = Notification.Name("hwmon.restartOnboardingTour")
}

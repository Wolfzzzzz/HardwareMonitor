//
//  FocusView.swift
//  HardwareMonitor
//
//  版本 26DF10Q1beta1.0.7 —— 专注页（主窗口第 4 个 tab）
//  包含：精确时钟 / 番茄钟 / 噪音检测 / 结束提示音 / 今日统计
//

import SwiftUI

// MARK: - 专注页

struct FocusView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FocusClockCard(engine: model.focusEngine)
                        .id("focus.clock")
                    FocusTimerCard(engine: model.focusEngine)
                        .id("focus.timer")
                    FocusNoiseCard(noise: model.focusNoise)
                        .id("focus.noise")
                    FocusSoundCard(sound: model.focusSound)
                        .id("focus.sound")
                    FocusStatsCard(engine: model.focusEngine)
                }
                .padding(16)
            }
            .onReceive(NotificationCenter.default.publisher(for: OnboardingController.scrollNotification)) { note in
                guard let id = note.object as? String else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}

// MARK: - 通用小工具

/// 卡片标题
private struct FocusCardHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
    }
}

/// 键值行
private struct FocusInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
        }
    }
}

/// 秒 → 「1 小时 20 分」
private func focusDurationText(_ seconds: Double) -> String {
    let totalMinutes = Int((max(0, seconds) / 60).rounded())
    if totalMinutes >= 60 {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return m > 0 ? "\(h) 小时 \(m) 分" : "\(h) 小时"
    }
    return "\(totalMinutes) 分钟"
}

// MARK: - 1. 精确时钟卡

private struct FocusClockCard: View {
    @ObservedObject var engine: FocusEngine
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(engine.preciseTimeText)
                    .font(.system(size: 50, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 8) {
                    Text(Self.dateText(engine.nowDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(engine.clockSourceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "±%.1f ms", engine.syncQualityMs))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(engine.syncQualityMs < 5 ? Color.green : Color.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.07))
                        )
                }
            }

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                FocusInfoRow(title: "开机时长", value: model.uptimeText)
                FocusInfoRow(title: "CPU 温度", value: tempText)
                FocusInfoRow(title: "CPU 占用", value: String(format: "%.0f%%", model.snapshot.cpuPercentValue))
            }
            .frame(width: 190)
        }
        .padding(16)
        .glassBackground(cornerRadius: 14)
        .tourAnchor("focus.clock")
    }

    private var tempText: String {
        if let t = model.snapshot.cpuTempC {
            return String(format: "%.1f ℃", t)
        }
        return "不可用"
    }

    private static func dateText(_ date: Date) -> String {
        FocusClockCard.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = LZ.t("M 月 d 日 EEEE", "EEE, MMM d")
        return f
    }()
}

// MARK: - 2. 番茄钟卡

private struct FocusTimerCard: View {
    @ObservedObject var engine: FocusEngine
    @EnvironmentObject private var model: AppModel

    private let presets: [Int] = [15, 25, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FocusCardHeader(icon: "timer", title: "番茄钟")

            HStack(alignment: .top, spacing: 22) {
                ring

                VStack(alignment: .leading, spacing: 14) {
                    focusLengthControls
                    breakControls
                    Divider()
                    actionButtons
                    summaryRow
                }
            }
        }
        .padding(16)
        .glassBackground(cornerRadius: 14)
        .tourAnchor("focus.timer")
    }

    // MARK: 进度环

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: 14)

            Circle()
                .trim(from: 0, to: max(0.001, engine.progress))
                .stroke(
                    AngularGradient(
                        colors: [model.accentColor, model.accentColor.opacity(0.55), model.accentColor],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: engine.progress)

            VStack(spacing: 4) {
                Text(engine.remainingText)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(engine.phaseLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 196, height: 196)
        .padding(.leading, 4)
    }

    // MARK: 专注时长

    private var focusLengthControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("专注时长")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(engine.focusMinutes) 分钟")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }

            Slider(value: focusLengthBinding, in: 1...120, step: 1)
                .tint(model.accentColor)

            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { m in
                    Button {
                        engine.setFocusMinutes(m)
                    } label: {
                        Text("\(m)")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .frame(minWidth: 34)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(engine.focusMinutes == m
                                          ? model.accentColor.opacity(0.22)
                                          : Color.primary.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(engine.focusMinutes == m
                                            ? model.accentColor.opacity(0.55)
                                            : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private var focusLengthBinding: Binding<Double> {
        Binding(
            get: { Double(engine.focusMinutes) },
            set: { engine.setFocusMinutes(Int($0.rounded())) }
        )
    }

    // MARK: 休息设置

    private var breakControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Stepper("短休 \(engine.shortBreakMinutes) 分", value: $engine.shortBreakMinutes, in: 1...60)
                    .font(.caption)
                Stepper("长休 \(engine.longBreakMinutes) 分", value: $engine.longBreakMinutes, in: 1...120)
                    .font(.caption)
            }
            HStack(spacing: 16) {
                Stepper("每 \(engine.roundsBeforeLongBreak) 轮长休", value: $engine.roundsBeforeLongBreak, in: 2...8)
                    .font(.caption)
                Spacer()
            }
            HStack(spacing: 18) {
                Toggle("自动开始休息", isOn: $engine.autoStartBreak)
                    .toggleStyle(.switch)
                    .font(.caption)
                Toggle("自动开始下一个", isOn: $engine.autoStartNext)
                    .toggleStyle(.switch)
                    .font(.caption)
            }
        }
    }

    // MARK: 操作按钮

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                engine.toggle()
            } label: {
                Label(primaryTitle, systemImage: primaryIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minWidth: 78)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.accentColor)

            Button {
                engine.skip()
            } label: {
                Label("跳过", systemImage: "forward.end")
                    .font(.system(size: 12))
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            Button {
                engine.reset()
            } label: {
                Label("重置", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12))
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)

            Button {
                model.enterFocusFullScreen()
            } label: {
                Label("进入专注全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tourAnchor("focus.fullscreen")
        }
    }

    private var primaryTitle: String {
        switch engine.phase {
        case .idle: return "开始"
        case .focusing, .breaking: return "暂停"
        case .paused, .breakPaused: return "继续"
        }
    }

    private var primaryIcon: String {
        switch engine.phase {
        case .idle: return "play.fill"
        case .focusing, .breaking: return "pause.fill"
        case .paused, .breakPaused: return "play.fill"
        }
    }

    // MARK: 汇总

    private var summaryRow: some View {
        HStack(spacing: 18) {
            statChip(title: "今日番茄", value: "\(engine.completedToday) 个")
            statChip(title: "今日专注", value: focusDurationText(engine.focusSecondsToday))
            statChip(title: "本轮", value: engine.roundIndex > 0 ? "第 \(engine.roundIndex) 个" : "—")
            Spacer()
        }
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
    }
}

// MARK: - 3. 噪音检测卡

private struct FocusNoiseCard: View {
    @ObservedObject var noise: NoiseMonitor
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FocusCardHeader(icon: "waveform", title: "噪音检测")

            Toggle("开启环境噪音检测", isOn: $noise.enabled)
                .toggleStyle(.switch)
                .font(.system(size: 12))
                .onChange(of: noise.enabled) { _, newValue in
                    noise.setEnabled(newValue)
                }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.0f", noise.db))
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("dB")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(noise.band.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(noise.band.color)
                }
                .frame(width: 92, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    levelBar
                    historyWave
                    HStack(spacing: 10) {
                        Text(noise.statusText)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        Text(String(format: "峰值 %.0f dB", noise.peakDb))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("重置") { noise.resetPeak() }
                            .buttonStyle(.link)
                            .font(.system(size: 10))
                    }
                }
            }

            if !noise.authorized && noise.enabled {
                HStack(spacing: 8) {
                    Image(systemName: "mic.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("需要麦克风权限才能检测噪音")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("授予麦克风权限") { noise.requestPermission() }
                        .buttonStyle(.bordered)
                        .font(.system(size: 11))
                }
            }

            Text(noise.band.advice)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text("关闭后不占用麦克风，系统麦克风指示灯会熄灭")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .glassBackground(cornerRadius: 14)
        .tourAnchor("focus.noise")
        .onAppear {
            noise.refreshAuthorization()
            if noise.enabled { noise.start() }
        }
    }

    private var levelBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.30, green: 0.78, blue: 0.45),
                                Color(red: 0.92, green: 0.74, blue: 0.25),
                                Color(red: 0.95, green: 0.55, blue: 0.22),
                                Color(red: 0.92, green: 0.30, blue: 0.30)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, min(1, noise.level)) * geo.size.width)
                    .animation(.easeInOut(duration: 0.25), value: noise.level)
            }
        }
        .frame(height: 9)
    }

    private var historyWave: some View {
        GeometryReader { geo in
            ZStack {
                if noise.history.count < 2 {
                    Text("暂无采样")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    wavePath(size: geo.size)
                        .stroke(model.accentColor.opacity(0.85), lineWidth: 1.5)
                }
            }
        }
        .frame(height: 40)
    }

    private func wavePath(size: CGSize) -> Path {
        var path = Path()
        let values = noise.history
        guard values.count > 1, size.width > 0, size.height > 0 else { return path }
        let step = size.width / CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * step
            let clamped = CGFloat(min(1, max(0, value)))
            let y = size.height * (1 - clamped)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

// MARK: - 4. 提示音卡

private struct FocusSoundCard: View {
    @ObservedObject var sound: FocusSoundPlayer
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FocusCardHeader(icon: "speaker.wave.2", title: "结束提示音")

            Toggle("番茄钟 / 休息结束时播放提示音", isOn: $sound.enabled)
                .toggleStyle(.switch)
                .font(.system(size: 12))

            HStack(spacing: 12) {
                Picker("内置音", selection: $sound.systemSoundName) {
                    ForEach(FocusSoundPlayer.systemSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 170)
                .disabled(sound.useCustom)

                Button("选择音频文件…") { sound.importCustomFile() }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))

                Button("试听") { sound.preview() }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))

                Spacer()
            }

            if sound.customFileName != nil {
                HStack(spacing: 8) {
                    Image(systemName: sound.useCustom ? "waveform.circle.fill" : "waveform.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(sound.useCustom ? model.accentColor : Color.secondary)
                    Text(sound.currentDescription)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("移除") { sound.removeCustom() }
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                    Spacer()
                    Toggle("使用自定义", isOn: $sound.useCustom)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))
                }
            } else {
                Text("当前：\(sound.currentDescription)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Slider(value: $sound.volume, in: 0...1)
                    .tint(model.accentColor)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", sound.volume * 100))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            Text("支持 mp3 / wav / m4a / aiff / caf，文件会复制到应用支持目录")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .glassBackground(cornerRadius: 14)
        .tourAnchor("focus.sound")
    }
}

// MARK: - 5. 今日统计卡

private struct FocusStatsCard: View {
    @ObservedObject var engine: FocusEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FocusCardHeader(icon: "chart.bar", title: "今日统计")

            HStack(spacing: 12) {
                metric(title: "完成番茄", value: "\(engine.completedToday)", unit: "个")
                metric(title: "专注总时长", value: focusDurationValue, unit: "")
                metric(title: "平均每个番茄", value: averageValue, unit: "分钟")
            }
        }
        .padding(16)
        .glassBackground(cornerRadius: 14)
    }

    private var focusDurationValue: String {
        focusDurationText(engine.focusSecondsToday)
    }

    private var averageValue: String {
        guard engine.completedToday > 0 else { return "—" }
        let minutes = engine.focusSecondsToday / 60 / Double(engine.completedToday)
        return String(format: "%.0f", minutes)
    }

    private func metric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

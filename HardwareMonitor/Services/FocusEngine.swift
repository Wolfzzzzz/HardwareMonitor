//
//  FocusEngine.swift
//  HardwareMonitor
//
//  版本 26DF10Q1beta1.0.7 —— 专注模块：精确番茄钟引擎
//  计时采用「单调时钟锚点法」：不靠 Timer 累减，而是记录起始锚点（CACurrentMediaTime）
//  与起始剩余时间，每次 tick 用锚点差重新推算剩余，因此 UI 抖动、主线程卡顿均不影响精度。
//  睡眠唤醒 / 系统时钟变更时重新锚定，并按墙钟流逝补足睡眠期间的时间。
//

import Foundation
import AppKit
import QuartzCore

/// 番茄钟引擎
@MainActor
final class FocusEngine: ObservableObject {

    // MARK: - 阶段

    enum Phase: String {
        case idle          // 待开始
        case focusing      // 专注中
        case paused        // 专注暂停
        case breaking      // 休息中
        case breakPaused   // 休息暂停
    }

    // MARK: - 状态

    @Published private(set) var phase: Phase = .idle
    /// 剩余秒数
    @Published private(set) var remaining: Double = 25 * 60
    /// 当前阶段总秒数
    @Published private(set) var total: Double = 25 * 60

    // MARK: 设置项（持久化）

    /// 专注时长（分钟）
    @Published var focusMinutes: Int = 25 {
        didSet {
            let v = max(1, min(120, focusMinutes))
            if v != focusMinutes {
                focusMinutes = v
            } else {
                UserDefaults.standard.set(v, forKey: "focusMinutes")
            }
        }
    }
    /// 短休息（分钟）
    @Published var shortBreakMinutes: Int = 5 {
        didSet {
            let v = max(1, min(60, shortBreakMinutes))
            if v != shortBreakMinutes {
                shortBreakMinutes = v
            } else {
                UserDefaults.standard.set(v, forKey: "focusShortBreak")
            }
        }
    }
    /// 长休息（分钟）
    @Published var longBreakMinutes: Int = 15 {
        didSet {
            let v = max(1, min(120, longBreakMinutes))
            if v != longBreakMinutes {
                longBreakMinutes = v
            } else {
                UserDefaults.standard.set(v, forKey: "focusLongBreak")
            }
        }
    }
    /// 几轮后进入长休息
    @Published var roundsBeforeLongBreak: Int = 4 {
        didSet {
            let v = max(1, min(12, roundsBeforeLongBreak))
            if v != roundsBeforeLongBreak {
                roundsBeforeLongBreak = v
            } else {
                UserDefaults.standard.set(v, forKey: "focusRounds")
            }
        }
    }
    /// 专注结束后自动开始休息
    @Published var autoStartBreak: Bool = true {
        didSet { UserDefaults.standard.set(autoStartBreak, forKey: "focusAutoBreak") }
    }
    /// 休息结束后自动开始下一个番茄
    @Published var autoStartNext: Bool = false {
        didSet { UserDefaults.standard.set(autoStartNext, forKey: "focusAutoNext") }
    }

    // MARK: 统计

    /// 今日完成番茄数
    @Published private(set) var completedToday: Int = 0
    /// 今日专注总秒数
    @Published private(set) var focusSecondsToday: Double = 0
    /// 本轮第几个番茄（0 表示尚未开始）
    @Published private(set) var roundIndex: Int = 0

    /// 精确时钟（20Hz 刷新，驱动毫秒级时间显示）
    @Published private(set) var nowDate: Date = Date()
    /// 系统时间与单调时钟的短窗口偏差（ms），正常 < 5ms
    @Published private(set) var syncQualityMs: Double = 0

    // MARK: 回调

    /// 阶段自然结束回调（跳过 / 重置不会触发）
    var onFinish: ((Phase) -> Void)?

    // MARK: 计时内部状态

    private var timer: Timer?
    /// 单调时钟锚点
    private var anchorMono: CFTimeInterval = CACurrentMediaTime()
    /// 墙钟锚点（用于睡眠补时与偏差评估）
    private var anchorWall: TimeInterval = Date().timeIntervalSince1970
    /// 锚点时刻的剩余秒数
    private var anchorRemaining: Double = 25 * 60
    /// 上次写入 @Published 的剩余值（节流）
    private var lastPublishedRemaining: Double = -1
    /// 上次 tick 的时钟采样（用于偏差估计）
    private var lastTickMono: CFTimeInterval = 0
    private var lastTickWall: TimeInterval = 0
    /// 主线程卡顿也可能导致 tick 间隔变大，故用 0.05s 阈值写入
    private let writeDelta: Double = 0.05
    /// 自动休息关闭时，暂存「即将进入的休息分钟数」
    private var pendingBreakMinutes: Int?
    /// 下一拍才应用的休息阶段：保证 onFinish 回调（上抛到主线程队列）读取 total 时仍是本段专注时长
    private var pendingBreakStart: (minutes: Int, auto: Bool)?
    /// 跨天检测计数
    private var tickCount: Int = 0
    private var lastDayString: String = ""

    // MARK: - 初始化

    init() {
        let d = UserDefaults.standard

        focusMinutes = max(1, min(120, d.object(forKey: "focusMinutes") as? Int ?? 25))
        shortBreakMinutes = max(1, min(60, d.object(forKey: "focusShortBreak") as? Int ?? 5))
        longBreakMinutes = max(1, min(120, d.object(forKey: "focusLongBreak") as? Int ?? 15))
        roundsBeforeLongBreak = max(1, min(12, d.object(forKey: "focusRounds") as? Int ?? 4))
        autoStartBreak = (d.object(forKey: "focusAutoBreak") as? Bool) ?? true
        autoStartNext = (d.object(forKey: "focusAutoNext") as? Bool) ?? false

        let startSeconds = Double(focusMinutes) * 60
        total = startSeconds
        remaining = startSeconds
        anchorRemaining = startSeconds
        lastPublishedRemaining = startSeconds
        lastDayString = FocusEngine.dayString()

        loadStats()
        startClock()
        observeSystemEvents()
    }

    // MARK: - 控制

    /// 开始 / 继续（idle 时开始专注；自动休息关闭时开始预设的休息）
    func start() {
        switch phase {
        case .paused, .breakPaused:
            resume()
        case .focusing, .breaking:
            break
        case .idle:
            if pendingBreakStart != nil {
                applyPendingBreakStart()
            }
            if let pending = pendingBreakMinutes {
                beginBreak(minutes: pending)
            } else if phase == .idle {
                beginFocus()
            }
        }
    }

    /// 暂停
    func pause() {
        guard phase == .focusing || phase == .breaking else { return }
        let snapshot = currentRemaining()
        remaining = snapshot
        anchorRemaining = snapshot
        lastPublishedRemaining = snapshot
        phase = (phase == .focusing) ? .paused : .breakPaused
    }

    /// 继续
    func resume() {
        guard phase == .paused || phase == .breakPaused else { return }
        let resuming: Phase = (phase == .paused) ? .focusing : .breaking
        anchor(remaining: max(0, remaining))
        phase = resuming
    }

    /// 开始 / 暂停切换
    func toggle() {
        switch phase {
        case .idle:
            start()
        case .focusing, .breaking:
            pause()
        case .paused, .breakPaused:
            resume()
        }
    }

    /// 重置：回到专注待开始状态（不计入统计）
    func reset() {
        pendingBreakMinutes = nil
        pendingBreakStart = nil
        roundIndex = 0
        let seconds = Double(focusMinutes) * 60
        total = seconds
        remaining = seconds
        anchor(remaining: seconds)
        phase = .idle
    }

    /// 跳过当前阶段（不计入统计、不播提示音）
    func skip() {
        pendingBreakStart = nil
        switch phase {
        case .focusing, .paused:
            phase = .idle
            scheduleBreakAfterFocus()
        case .breaking, .breakPaused:
            phase = .idle
            let rounds = max(1, roundsBeforeLongBreak)
            if roundIndex > 0 && roundIndex % rounds == 0 { roundIndex = 0 }
            if autoStartNext {
                beginFocus()
            } else {
                prepareIdleFocus()
            }
        case .idle:
            prepareIdleFocus()
        }
    }

    /// 设置专注时长（非运行状态下立即同步到显示）
    func setFocusMinutes(_ m: Int) {
        focusMinutes = m
        if phase == .idle && pendingBreakMinutes == nil {
            let seconds = Double(focusMinutes) * 60
            total = seconds
            remaining = seconds
            anchor(remaining: seconds)
        }
    }

    // MARK: - 阶段流转

    private func beginFocus() {
        pendingBreakMinutes = nil
        roundIndex += 1
        let seconds = Double(focusMinutes) * 60
        total = seconds
        remaining = seconds
        anchor(remaining: seconds)
        phase = .focusing
    }

    private func beginBreak(minutes: Int) {
        pendingBreakMinutes = nil
        let seconds = Double(max(1, minutes)) * 60
        total = seconds
        remaining = seconds
        anchor(remaining: seconds)
        phase = .breaking
    }

    private func prepareIdleFocus() {
        pendingBreakMinutes = nil
        let seconds = Double(focusMinutes) * 60
        total = seconds
        remaining = seconds
        anchor(remaining: seconds)
        phase = .idle
    }

    /// 专注结束后安排休息
    private func scheduleBreakAfterFocus() {
        let rounds = max(1, roundsBeforeLongBreak)
        let useLong = roundIndex > 0 && roundIndex % rounds == 0
        let minutes = useLong ? longBreakMinutes : shortBreakMinutes

        if autoStartBreak {
            beginBreak(minutes: minutes)
        } else {
            pendingBreakMinutes = minutes
            let seconds = Double(minutes) * 60
            total = seconds
            remaining = seconds
            anchor(remaining: seconds)
            phase = .idle
        }
    }

    /// 当前阶段自然结束
    private func completeCurrentPhase() {
        let finished = phase
        if finished == .focusing {
            completedToday += 1
            focusSecondsToday += total
            saveStats()

            phase = .idle
            // 注意：此处 total 仍是本段专注时长，回调方（通知文案）需要读到它
            onFinish?(.focusing)

            let rounds = max(1, roundsBeforeLongBreak)
            let useLong = roundIndex > 0 && roundIndex % rounds == 0
            let minutes = useLong ? longBreakMinutes : shortBreakMinutes
            // 休息阶段延后到下一拍应用，避免立刻改写 total
            pendingBreakStart = (minutes: minutes, auto: autoStartBreak)
        } else if finished == .breaking {
            phase = .idle
            onFinish?(.breaking)

            // 长休息完成 → 开启新一轮
            let rounds = max(1, roundsBeforeLongBreak)
            if roundIndex > 0 && roundIndex % rounds == 0 { roundIndex = 0 }

            if autoStartNext {
                beginFocus()
            } else {
                prepareIdleFocus()
            }
        }
    }

    /// 应用上一段专注结束后排队的休息阶段
    private func applyPendingBreakStart() {
        guard let pending = pendingBreakStart else { return }
        pendingBreakStart = nil

        if pending.auto {
            beginBreak(minutes: pending.minutes)
        } else {
            pendingBreakMinutes = pending.minutes
            let seconds = Double(pending.minutes) * 60
            total = seconds
            remaining = seconds
            anchor(remaining: seconds)
            phase = .idle
        }
    }

    // MARK: - 时钟

    private func startClock() {
        timer?.invalidate()
        // 50ms 驱动 UI；真实精度来自锚点法，与 tick 间隔无关
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = Date()
        let mono = CACurrentMediaTime()
        let wall = now.timeIntervalSince1970

        // 刷新精确时钟
        nowDate = now

        // 时钟质量：相邻两拍的墙钟增量与单调时钟增量之差
        if lastTickMono > 0 {
            let deltaMono = mono - lastTickMono
            let deltaWall = wall - lastTickWall
            if deltaMono > 0 {
                let deviation = abs(deltaWall - deltaMono) * 1000
                // 超过 500ms 视为睡眠/时钟跳变，不计入质量评估
                if deviation < 500 {
                    syncQualityMs = syncQualityMs * 0.9 + deviation * 0.1
                }
            }
        }
        lastTickMono = mono
        lastTickWall = wall

        // 每 ~10 秒检查一次跨天
        tickCount += 1
        if tickCount % 200 == 0 {
            refreshDayIfNeeded()
        }

        // 上一段专注结束后排队中的休息阶段（延后一拍应用）
        if pendingBreakStart != nil {
            applyPendingBreakStart()
            return
        }

        guard phase == .focusing || phase == .breaking else { return }

        let next = max(0, anchorRemaining - (mono - anchorMono))
        if next <= 0.0001 {
            remaining = 0
            lastPublishedRemaining = 0
            completeCurrentPhase()
            return
        }
        if next <= lastPublishedRemaining - writeDelta || next > lastPublishedRemaining {
            remaining = next
            lastPublishedRemaining = next
        }
    }

    /// 当前剩余（运行中用锚点实时推算，暂停/待机用已存值）
    private func currentRemaining() -> Double {
        guard phase == .focusing || phase == .breaking else { return remaining }
        return max(0, anchorRemaining - (CACurrentMediaTime() - anchorMono))
    }

    /// 重新锚定
    private func anchor(remaining r: Double) {
        anchorMono = CACurrentMediaTime()
        anchorWall = Date().timeIntervalSince1970
        anchorRemaining = r
        lastPublishedRemaining = r
    }

    /// 睡眠唤醒 / 系统时钟变更：按真实流逝重算并重新锚定
    private func realignAfterSystemEvent() {
        let mono = CACurrentMediaTime()
        let wall = Date().timeIntervalSince1970

        if phase == .focusing || phase == .breaking {
            let monoElapsed = mono - anchorMono
            let wallElapsed = wall - anchorWall
            // 睡眠期间单调时钟暂停，取较大者补足真实流逝；墙钟被回拨时以单调时钟为准
            let realElapsed = max(monoElapsed, wallElapsed)
            let next = max(0, anchorRemaining - realElapsed)

            remaining = next
            lastPublishedRemaining = next

            if next <= 0.0001 {
                anchorRemaining = 0
                anchorMono = mono
                anchorWall = wall
                syncQualityMs = 0
                lastTickMono = mono
                lastTickWall = wall
                completeCurrentPhase()
                return
            }
        }

        anchorRemaining = remaining
        anchorMono = mono
        anchorWall = wall
        lastTickMono = mono
        lastTickWall = wall
        syncQualityMs = 0
    }

    private func observeSystemEvents() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.realignAfterSystemEvent() }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.realignAfterSystemEvent() }
        }
    }

    // MARK: - 统计持久化

    private func loadStats() {
        let d = UserDefaults.standard
        if d.string(forKey: "focusStatsDate") == FocusEngine.dayString() {
            completedToday = max(0, d.integer(forKey: "focusCompletedToday"))
            focusSecondsToday = max(0, d.double(forKey: "focusSecondsToday"))
        } else {
            completedToday = 0
            focusSecondsToday = 0
            d.set(FocusEngine.dayString(), forKey: "focusStatsDate")
            d.set(0, forKey: "focusCompletedToday")
            d.set(0.0, forKey: "focusSecondsToday")
        }
    }

    private func saveStats() {
        let d = UserDefaults.standard
        d.set(FocusEngine.dayString(), forKey: "focusStatsDate")
        d.set(completedToday, forKey: "focusCompletedToday")
        d.set(focusSecondsToday, forKey: "focusSecondsToday")
    }

    /// 跨天清零今日统计
    private func refreshDayIfNeeded() {
        let today = FocusEngine.dayString()
        guard today != lastDayString else { return }
        lastDayString = today
        completedToday = 0
        focusSecondsToday = 0
        saveStats()
    }

    private static func dayString(_ date: Date = Date()) -> String {
        FocusEngine.dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // MARK: - 展示

    /// 阶段进度 0...1
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, (total - remaining) / total))
    }

    /// 倒计时文本（mm:ss；超过 1 小时用 h:mm:ss）
    var remainingText: String {
        let seconds = Int(ceil(max(0, remaining)))
        let m = seconds / 60
        let s = seconds % 60
        if m >= 60 {
            return String(format: "%d:%02d:%02d", m / 60, m % 60, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// 精确当前时间（毫秒）
    var preciseTimeText: String {
        FocusEngine.timeFormatter.string(from: nowDate)
    }

    /// 时钟来源说明
    var clockSourceText: String {
        LZ.t("系统时间 · 单调时钟校准", "System time · monotonic calibrated")
    }

    /// 阶段名称
    var phaseLabel: String {
        switch phase {
        case .idle:
            return pendingBreakMinutes != nil
                ? LZ.t("待休息", "Break ready")
                : LZ.t("待开始", "Ready")
        case .focusing:
            return LZ.t("专注中", "Focusing")
        case .paused:
            return LZ.t("已暂停", "Paused")
        case .breaking:
            return LZ.t("休息中", "On break")
        case .breakPaused:
            return LZ.t("已暂停", "Paused")
        }
    }

    /// 是否处于运行中（专注或休息）
    var isRunning: Bool {
        phase == .focusing || phase == .breaking
    }
}

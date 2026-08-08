import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications

/// 全局应用状态：配置（UserDefaults 持久化）+ 快照 + 历史 + 采样调度 + 悬浮窗
///
/// 说明：由于当前 Xcode 27 beta 的 Swift 宏（@Observable/@State）不可用（swift-plugin-server
/// 报 malformed response），本工程统一使用 ObservableObject + @Published（属性包装器）。
@MainActor
final class AppModel: ObservableObject {

    // MARK: - 配置（UserDefaults 持久化，didSet 直写，不访问 self）

    @Published var refreshInterval: Double = 1 { didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") } }

    @Published var alertsEnabled: Bool = true { didSet { UserDefaults.standard.set(alertsEnabled, forKey: "alertsEnabled") } }
    @Published var alertSound: Bool = true { didSet { UserDefaults.standard.set(alertSound, forKey: "alertSound") } }

    @Published var cpuTempThreshold: Double = 90 { didSet { UserDefaults.standard.set(cpuTempThreshold, forKey: "cpuTempThreshold") } }
    @Published var gpuTempThreshold: Double = 95 { didSet { UserDefaults.standard.set(gpuTempThreshold, forKey: "gpuTempThreshold") } }
    @Published var cpuUsageThreshold: Double = 90 { didSet { UserDefaults.standard.set(cpuUsageThreshold, forKey: "cpuUsageThreshold") } }
    @Published var memUsageThreshold: Double = 90 { didSet { UserDefaults.standard.set(memUsageThreshold, forKey: "memUsageThreshold") } }
    @Published var diskFreeThreshold: Double = 20 { didSet { UserDefaults.standard.set(diskFreeThreshold, forKey: "diskFreeThreshold") } }
    @Published var batteryPercentThreshold: Double = 20 { didSet { UserDefaults.standard.set(batteryPercentThreshold, forKey: "batteryPercentThreshold") } }

    @Published var showTemp: Bool = true { didSet { UserDefaults.standard.set(showTemp, forKey: "showTemp") } }
    @Published var showCPU: Bool = true { didSet { UserDefaults.standard.set(showCPU, forKey: "showCPU") } }
    @Published var showMemory: Bool = true { didSet { UserDefaults.standard.set(showMemory, forKey: "showMemory") } }
    @Published var showDisk: Bool = true { didSet { UserDefaults.standard.set(showDisk, forKey: "showDisk") } }
    @Published var showNetwork: Bool = true { didSet { UserDefaults.standard.set(showNetwork, forKey: "showNetwork") } }
    @Published var showBattery: Bool = true { didSet { UserDefaults.standard.set(showBattery, forKey: "showBattery") } }
    @Published var showBrightness: Bool = true { didSet { UserDefaults.standard.set(showBrightness, forKey: "showBrightness") } }
    @Published var showProcess: Bool = true { didSet { UserDefaults.standard.set(showProcess, forKey: "showProcess") } }

    // 自启（由设置页 onChange 触发应用，避免 didSet 中的 self 问题）
    @Published var launchAtLogin: Bool = false
    @Published var launchAtLoginError: String?

    // 界面语言：system / en / fr / zh-Hans / zh-Hant-HK / zh-Hant-TW / ru（持久化 + AppleLanguages 覆盖）
    @Published var appLanguage: String {
        didSet { UserDefaults.standard.set(appLanguage, forKey: "appLanguage") }
    }

    // MARK: - 数据状态

    @Published var snapshot = SystemSnapshot()
    @Published var history: [HistoryPoint] = []
    /// 图表专用历史（每 3 次快照更新一次，降低图表重绘开销）
    @Published var chartHistory: [HistoryPoint] = []
    @Published var isPanelVisible = false
    @Published var alertActive = false
    @Published var lastUpdated: Date?
    @Published var showCharts = true
    @Published var showProcessPanel = true
    @Published var showTempDetail = false
    @Published var showDetailCharts = true

    // 主窗口标签：0 监控 / 1 剪贴板 / 2 工具
    @Published var mainTab = 0
    @Published var copiedInfoKey: String?

    // 剪贴板历史
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var clipboardEnabled: Bool = true { didSet { UserDefaults.standard.set(clipboardEnabled, forKey: "clipboardEnabled") } }
    @Published var lastCopiedID: UUID?
    private var clipboardTimer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    let clipboardLimit = 60

    // MARK: - 内部

    private let hub = SensorHub()
    private let alertEngine = AlertEngine()
    private let panelController = FloatingPanelController()
    private var historyCapacity = 300
    private var uiTick = 0
    /// 主窗口是否可见（图表仅在可见时同步，省后台开销）
    @Published var mainWindowVisible = false

    func setMainWindowVisible(_ visible: Bool) {
        mainWindowVisible = visible
        if visible { chartHistory = history }  // 打开瞬间立即有数据
    }
    private var hasStarted = false

    var smcAvailable: Bool { hub.smcAvailable }
    var hidAvailable: Bool { hub.hidAvailable }
    var temperatureAvailable: Bool { hub.smcAvailable || hub.hidAvailable }
    var tempSource: String? { snapshot.tempSource }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "refreshInterval": 1.0, "alertsEnabled": true, "alertSound": true,
            "cpuTempThreshold": 90.0, "gpuTempThreshold": 95.0,
            "cpuUsageThreshold": 90.0, "memUsageThreshold": 90.0,
            "diskFreeThreshold": 20.0, "batteryPercentThreshold": 20.0,
            "showTemp": true, "showCPU": true, "showMemory": true, "showDisk": true,
            "showNetwork": true, "showBattery": true, "showBrightness": true, "showProcess": true,
            "clipboardEnabled": true
        ])
        refreshInterval = d.double(forKey: "refreshInterval")
        alertsEnabled = d.bool(forKey: "alertsEnabled")
        alertSound = d.bool(forKey: "alertSound")
        cpuTempThreshold = d.double(forKey: "cpuTempThreshold")
        gpuTempThreshold = d.double(forKey: "gpuTempThreshold")
        cpuUsageThreshold = d.double(forKey: "cpuUsageThreshold")
        memUsageThreshold = d.double(forKey: "memUsageThreshold")
        diskFreeThreshold = d.double(forKey: "diskFreeThreshold")
        batteryPercentThreshold = d.double(forKey: "batteryPercentThreshold")
        showTemp = d.bool(forKey: "showTemp")
        showCPU = d.bool(forKey: "showCPU")
        showMemory = d.bool(forKey: "showMemory")
        showDisk = d.bool(forKey: "showDisk")
        showNetwork = d.bool(forKey: "showNetwork")
        showBattery = d.bool(forKey: "showBattery")
        showBrightness = d.bool(forKey: "showBrightness")
        showProcess = d.bool(forKey: "showProcess")
        clipboardEnabled = d.object(forKey: "clipboardEnabled") == nil ? true : d.bool(forKey: "clipboardEnabled")
        noteText = d.string(forKey: "noteText") ?? ""
        launchAtLogin = SMAppService.mainApp.status == .enabled
        appLanguage = d.string(forKey: "appLanguage") ?? "system"
    }

    // MARK: - 界面语言切换

    /// 写入 AppleLanguages 覆盖并重启应用（SwiftUI 本地化在启动时加载，必须重启生效）
    func applyLanguageChange() {
        if appLanguage == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([appLanguage], forKey: "AppleLanguages")
        }
        // 用子进程延迟重启：先让本进程退出，再 open 启动新实例
        // （直接 open + terminate 会因为 open 复用当前运行实例导致只退出不重开）
        let bundlePath = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1 && open \"\(bundlePath)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: - 采样

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        alertEngine.requestAuthorizationIfNeeded()

        NotificationCenter.default.addObserver(forName: .floatingPanelClosed, object: nil, queue: .main) { [weak self] _ in
            self?.isPanelVisible = false
        }

        hub.onSnapshot = { [weak self] snap, _ in
            guard let self else { return }
            self.snapshot = snap
            self.lastUpdated = Date()
            self.appendHistory(snap)
            // 图表数据仅在界面可见时同步（每 3 次快照一次），窗口全关时零刷新零触发
            self.uiTick += 1
            if self.uiTick % 3 == 1, self.mainWindowVisible || self.isPanelVisible {
                self.chartHistory = self.history
            }
            self.alertEngine.check(snap, model: self)
            self.refreshAlertActive(snap)
        }
        hub.start(interval: refreshInterval)
        hub.sampleNow()
        startClipboardMonitor()
    }

    func stop() {
        hub.stop()
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    /// 刷新间隔变化后重启采样定时器
    func restartSampling() {
        guard hasStarted else { return }
        hub.start(interval: refreshInterval)
        hub.sampleNow()
    }

    private func appendHistory(_ snap: SystemSnapshot) {
        let point = HistoryPoint(
            time: Date(),
            cpuPercent: snap.cpuPercentValue,
            memPercent: snap.memPercentValue,
            cpuTemp: snap.cpuTempC,
            gpuTemp: snap.gpuTempC,
            netDownMBs: snap.netDown / 1024 / 1024,
            netUpMBs: snap.netUp / 1024 / 1024
        )
        history.append(point)
        if history.count > historyCapacity {
            history.removeFirst(history.count - historyCapacity)
        }
    }

    private func refreshAlertActive(_ snap: SystemSnapshot) {
        var active = false
        if let t = snap.cpuTempC, t >= cpuTempThreshold { active = true }
        if let t = snap.gpuTempC, t >= gpuTempThreshold { active = true }
        if snap.cpuPercentValue >= cpuUsageThreshold { active = true }
        if snap.memPercentValue * 100 >= memUsageThreshold { active = true }
        if snap.diskTotal > 0, Double(snap.diskFree) / 1e9 <= diskFreeThreshold { active = true }
        if let p = snap.batteryPercent, p <= Int(batteryPercentThreshold) { active = true }
        alertActive = active
    }

    // MARK: - 自启

    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = error.localizedDescription
        }
    }

    // MARK: - 悬浮窗

    func togglePanel() {
        isPanelVisible.toggle()
        if isPanelVisible {
            panelController.show {
                DashboardView()
                    .environmentObject(self)
            }
        } else {
            panelController.hide()
        }
    }

    func hidePanel() {
        isPanelVisible = false
        panelController.hide()
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 窗口激活（打开时临时浮到最前，不常驻置顶）

    /// 把主界面窗口提到最前并激活（菜单栏 App 打开后常落在底层，需手动前置）
    func activateMainWindow() {
        if let w = NSApp.windows.first(where: { $0.title == "硬件监控" }) {
            w.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 把设置窗口提到最前并激活
    func activateSettingsWindow() {
        if let w = NSApp.windows.first(where: {
            $0.title.contains("设置") || $0.title.contains("Settings")
        }) {
            w.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 剪贴板历史

    private func startClipboardMonitor() {
        clipboardTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        RunLoop.main.add(timer, forMode: .common)
        clipboardTimer = timer
    }

    private func checkClipboard() {
        guard clipboardEnabled else { return }
        let pb = NSPasteboard.general
        let cc = pb.changeCount
        guard cc != lastChangeCount else { return }
        lastChangeCount = cc
        guard let str = pb.string(forType: .string) else { return }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 去重（固定条目保留）
        if let idx = clipboardItems.firstIndex(where: { $0.text == trimmed && !$0.pinned }) {
            clipboardItems.remove(at: idx)
        }
        clipboardItems.insert(ClipboardItem(text: trimmed), at: 0)
        if clipboardItems.count > clipboardLimit {
            clipboardItems.removeLast(clipboardItems.count - clipboardLimit)
        }
    }

    /// 复制剪贴板条目回系统剪贴板
    func copyClipboardItem(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        lastCopiedID = item.id
        // 反馈提示 1.5s 后清除
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.lastCopiedID = nil
        }
    }

    func togglePin(_ item: ClipboardItem) {
        if let idx = clipboardItems.firstIndex(where: { $0.id == item.id }) {
            clipboardItems[idx].pinned.toggle()
            // 固定条目置顶
            let it = clipboardItems.remove(at: idx)
            clipboardItems.insert(it, at: 0)
        }
    }

    func deleteClipboardItem(_ item: ClipboardItem) {
        clipboardItems.removeAll { $0.id == item.id }
    }

    func clearClipboardHistory() {
        clipboardItems.removeAll()
        lastCopiedID = nil
    }

    // MARK: - 快捷工具

    /// 锁屏（macOS 27 已移除 CGSession，改用系统锁屏快捷键 ⌃⌘Q；首次需允许「辅助功能」权限）
    func lockScreen() {
        let script = "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }

    /// 显示器休眠
    func sleepDisplay() {
        runProcess("/usr/bin/pmset", args: ["displaysleepnow"])
    }

    /// 清空系统剪贴板
    func clearSystemClipboard() {
        NSPasteboard.general.clearContents()
        lastChangeCount = NSPasteboard.general.changeCount
        clearClipboardHistory()
    }

    private func runProcess(_ path: String, args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }

    // MARK: - 工具页状态

    // 工具侧栏选中项
    @Published var toolTab = 0

    // 二维码
    @Published var qrText = "https://www.apple.com"

    // 单位换算
    @Published var convertCategory = 0
    @Published var convertValue = "1"
    @Published var convertFrom = 0
    @Published var convertTo = 1

    // 文本统计
    @Published var statText = ""

    // 编码工具
    @Published var encodeInput = ""
    @Published var encodeMode = 0
    @Published var encodeOutput = ""

    // 颜色工具
    @Published var colorHex = "#4F8CFF"

    // 番茄钟
    @Published var pomoMinutes = 25
    @Published var pomoRemaining = 25 * 60
    @Published var pomoRunning = false
    private var pomoTimer: Timer?

    // 便签（自动保存）
    @Published var noteText: String = "" {
        didSet { UserDefaults.standard.set(noteText, forKey: "noteText") }
    }

    // MARK: - 番茄钟

    func setPomodoroMinutes(_ m: Int) {
        pomoMinutes = max(1, min(120, m))
        if !pomoRunning { pomoRemaining = pomoMinutes * 60 }
    }

    func startPomodoro() {
        stopPomodoro()
        pomoRemaining = pomoMinutes * 60
        pomoRunning = true
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.pomodoroTick() }
        RunLoop.main.add(t, forMode: .common)
        pomoTimer = t
    }

    func stopPomodoro() {
        pomoTimer?.invalidate()
        pomoTimer = nil
        pomoRunning = false
    }

    func resetPomodoro() {
        stopPomodoro()
        pomoRemaining = pomoMinutes * 60
    }

    private func pomodoroTick() {
        guard pomoRunning else { return }
        if pomoRemaining > 0 {
            pomoRemaining -= 1
            if pomoRemaining == 0 {
                stopPomodoro()
                // 完成通知
                let content = UNMutableNotificationContent()
                content.title = LZ.t("番茄钟完成", "Pomodoro Finished")
                content.body = LZ.t("\(pomoMinutes) 分钟专注结束，休息一下吧", "\(pomoMinutes) minutes of focus done. Take a break.")
                content.sound = .default
                UNUserNotificationCenter.current().add(UNNotificationRequest(
                    identifier: "hwmon.pomo.\(Date().timeIntervalSince1970)",
                    content: content, trigger: nil))
                NSSound.beep()
            }
        }
    }
}

import SwiftUI
import AppKit
import CoreGraphics
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
    /// 语言选择暂存：设置页先改这里，确认后才应用（避免误触）
    @Published var pendingLanguage: String = "system"
    @Published var showLanguageConfirm = false

    // MARK: - 专业功能（Pro）

    /// 当前版本档位（激活码激活，持久化）：free / deluxe / premium
    @Published var proTier: ProTier = .free
    /// 激活提示信息
    @Published var licenseMessage: String?
    /// 激活码输入框内容
    @Published var licenseInput = ""

    /// 是否 Deluxe 及以上
    var isDeluxe: Bool { proTier == .deluxe || proTier == .premium }

    // MARK: - Premium 分析状态

    @Published var bigFiles: [DiskScanner.BigFile] = []
    @Published var scanningDisk = false
    @Published var benchmarkResult: Benchmark.Result?
    @Published var benchmarkRunning = false
    @Published var benchmarkStage: Benchmark.Stage = .idle
    @Published var currentWorkload: Benchmark.Workload? = nil
    @Published var showBenchmarkSheet = false
    /// 单核 divisor（校准到 Geekbench 6 单核量级）
    private let singleDivisors: [Benchmark.Workload: Double] = [
        .integer: 142_000, .float: 200_000, .memory: 634_000, .bitwise: 108_000,
    ]
    /// 多核 divisor（单核 ×2：避免多核子负载分数触顶 cap，并贴合 Geekbench 6 多核量级）
    private let multiDivisors: [Benchmark.Workload: Double] = [
        .integer: 284_000, .float: 400_000, .memory: 1_268_000, .bitwise: 216_000,
    ]
    private let singleCap: Double = 10_000
    private let multiCap: Double = 25_000
    private let diskScanner = DiskScanner()

    /// 扫描磁盘大文件（后台）
    func scanBigFiles() {
        guard !scanningDisk else { return }
        scanningDisk = true
        Task {
            let result = await diskScanner.scan(top: 20)
            await MainActor.run {
                bigFiles = result
                scanningDisk = false
            }
        }
    }

    /// CPU 跑分（独立 sheet：单核 4 步 + 多核 4 步，依次更新 currentWorkload 驱动进度）
    func runBenchmark() {
        guard !benchmarkRunning else { return }
        benchmarkRunning = true
        benchmarkResult = nil
        let ws = Benchmark.Workload.allCases
        let cores = ProcessInfo.processInfo.activeProcessorCount
        Task { @MainActor in
            var singleSubs: [Int] = []
            var multiSubs: [Int] = []
            // 单核阶段
            benchmarkStage = .single
            for w in ws {
                currentWorkload = w
                let iters = await Task.detached(priority: .userInitiated) {
                    Benchmark.runSingleWorkload(workload: w, threads: 1)
                }.value
                singleSubs.append(workloadScore(w, totalIters: iters, isMulti: false))
            }
            // 多核阶段
            benchmarkStage = .multi
            for w in ws {
                currentWorkload = w
                let iters = await Task.detached(priority: .userInitiated) {
                    Benchmark.runSingleWorkload(workload: w, threads: cores)
                }.value
                multiSubs.append(workloadScore(w, totalIters: iters, isMulti: true))
            }
            // 完成（多核 divisor 已校准到 Geekbench 6 多核量级，无需再乘效率系数）
            let singleScore = singleSubs.reduce(0, +) / max(1, singleSubs.count)
            let multiScore = multiSubs.reduce(0, +) / max(1, multiSubs.count)
            benchmarkResult = Benchmark.Result(
                singleScore: singleScore, multiScore: multiScore,
                workloads: ws, singleSub: singleSubs, multiSub: multiSubs
            )
            benchmarkStage = .done
            currentWorkload = nil
            benchmarkRunning = false
        }
    }

    /// 跑分辅助：单次负载迭代数 → 分数（单核/多核分别换算）
    private func workloadScore(_ w: Benchmark.Workload, totalIters: Double, isMulti: Bool) -> Int {
        let tps = totalIters / 0.35
        let div = (isMulti ? multiDivisors : singleDivisors)[w] ?? 200_000
        let cap = isMulti ? multiCap : singleCap
        return Int(min(cap, max(1, tps / div)))
    }

    /// 告警历史（Premium）
    var alertHistory: [AlertEngine.AlertRecord] { alertEngine.history }
    func clearAlertHistory() { alertEngine.clearHistory() }

    // MARK: - WiFi 详情（Deluxe+）

    @Published var wifiInfo: WiFiInfo?
    @Published var wifiUpdatedAt: Date?

    func refreshWiFiInfo() {
        // 后台执行（CoreWLAN + 3 个子进程，避免阻塞主线程）
        DispatchQueue.global(qos: .userInitiated).async {
            let info = fetchWiFiInfo()
            DispatchQueue.main.async {
                self.wifiInfo = info
                self.wifiUpdatedAt = Date()
            }
        }
    }

    // MARK: - 磁盘健康（Premium）

    @Published var diskHealth: DiskHealth?
    @Published var diskHealthCheckedAt: Date?

    func checkDiskHealth() {
        // 后台执行（diskutil 子进程耗时长，避免阻塞主线程）
        DispatchQueue.global(qos: .userInitiated).async {
            let h = fetchDiskHealth()
            DispatchQueue.main.async {
                self.diskHealth = h
                self.diskHealthCheckedAt = Date()
            }
        }
    }

    // MARK: - 网络测速（Premium）

    @Published var speedTestResult: SpeedTestResult?
    @Published var speedTesting = false
    @Published var speedProgress: Double = 0
    @Published var speedStageText = ""
    private let speedEngine = SpeedTestEngine()

    func runSpeedTest() {
        guard !speedTesting else { return }
        speedTesting = true
        speedProgress = 0
        speedStageText = "准备中…"
        speedEngine.run(progress: { [weak self] p, stage in
            Task { @MainActor in
                self?.speedProgress = p
                self?.speedStageText = stage
            }
        }, completion: { [weak self] result in
            Task { @MainActor in
                self?.speedTestResult = result
                self?.speedTesting = false
                self?.speedProgress = 1
                self?.speedStageText = "完成"
            }
        })
    }
    /// 是否 Premium Deluxe
    var isPremium: Bool { proTier == .premium }

    /// 退出激活（回到 Standard 免费版）
    func deactivatePro() {
        proTier = .free
        UserDefaults.standard.set("free", forKey: "proTier")
        licenseMessage = nil
    }

    /// 尝试用激活码解锁（按激活码档位激活对应版本）
    func tryActivate(_ code: String) -> Bool {
        let tier = License.tier(of: code)
        guard tier != .free else {
            licenseMessage = "激活码无效，请检查后重试"
            return false
        }
        proTier = tier
        UserDefaults.standard.set(tier.rawValue, forKey: "proTier")
        licenseMessage = nil
        return true
    }

    /// 主题皮肤 id（aurora/ocean/forest/magma/sakura/graphite）
    @Published var themeID: String = "aurora" { didSet { UserDefaults.standard.set(themeID, forKey: "themeID") } }
    /// 外观强制：system/dark/light
    @Published var appearanceID: String = "system" { didSet { UserDefaults.standard.set(appearanceID, forKey: "appearanceID") } }
    /// Dock 图标角标显示 CPU 温度（开启时切到普通模式让 Dock 图标可见）
    @Published var dockBadgeEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(dockBadgeEnabled, forKey: "dockBadgeEnabled")
            switchActivationPolicy(dockVisible: dockBadgeEnabled)
            updateDockBadge()
        }
    }

    /// 远程监控
    @Published var remoteEnabled: Bool = false { didSet { UserDefaults.standard.set(remoteEnabled, forKey: "remoteEnabled") } }
    @Published var remotePort: Int = 8900 { didSet { UserDefaults.standard.set(remotePort, forKey: "remotePort") } }
    @Published var remoteRunning = false
    private let remoteServer = RemoteMonitorServer()

    /// 语言选择变更（Picker onChange 触发）→ 弹确认框
    func requestLanguageConfirm() {
        showLanguageConfirm = true
    }

    /// 确认：应用语言 + 重启
    func confirmPendingLanguage() {
        showLanguageConfirm = false
        appLanguage = pendingLanguage
        applyLanguageChange()
    }

    /// 取消：还原选择，不重启
    func cancelPendingLanguage() {
        showLanguageConfirm = false
        pendingLanguage = appLanguage
    }

    // MARK: - 主题

    /// 当前主题皮肤
    var currentTheme: ThemeConfig { AppThemes.byID(themeID) }

    /// 是否深色外观（考虑"外观模式"设置 + 系统跟随）
    var isDarkMode: Bool {
        switch appearanceID {
        case "dark": return true
        case "light": return false
        default: return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    /// 自定义强调色（Premium Deluxe 专属，hex 持久化）
    @Published var customAccentHex: String = "FF9F43" { didSet { UserDefaults.standard.set(customAccentHex, forKey: "customAccentHex") } }

    /// 当前强调色（主题；custom 主题用自定义色）
    var accentColor: Color {
        if themeID == "custom", isPremium {
            return colorFromHex(customAccentHex)
        }
        return currentTheme.accent
    }

    func colorFromHex(_ hex: String) -> Color {
        var h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if h.count == 6 { h = "FF" + h }
        guard let val = UInt64(h, radix: 16) else { return .accentColor }
        return Color(
            red: Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8) & 0xFF) / 255,
            blue: Double(val & 0xFF) / 255
        )
    }

    // MARK: - 系统信息（Premium）

    /// CPU 型号字符串
    var cpuBrand: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf).trimmingCharacters(in: .whitespaces)
    }

    /// 芯片架构（arm64/x86_64）
    var chipArch: String {
        var uts = utsname()
        uname(&uts)
        return withUnsafePointer(to: &uts.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
    }

    /// 系统版本
    var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// 识别出的芯片（参考对比）
    var detectedChip: ChipDB.Chip? { ChipDB.detect(from: cpuBrand) }

    /// 芯片对比列表（全部，按分数升序；含本机）
    var chipComparison: [ChipDB.Chip] {
        var arr = ChipDB.all
        if let me = detectedChip, !arr.contains(where: { $0.id == me.id }) {
            arr.append(me)
        }
        return arr.sorted { $0.score < $1.score }
    }

    /// 性能健康评分（0-100，温度越低越接近 100）
    var healthScore: Int {
        var score = 100
        if let t = snapshot.cpuTempC {
            if t > 95 { score -= 40 } else if t > 85 { score -= 25 } else if t > 75 { score -= 12 } else if t > 65 { score -= 5 }
        }
        if snapshot.cpuPercentValue > 0.9 { score -= 10 } else if snapshot.cpuPercentValue > 0.75 { score -= 5 }
        if snapshot.memPercentValue > 0.9 { score -= 8 } else if snapshot.memPercentValue > 0.8 { score -= 4 }
        return max(0, min(100, score))
    }
    /// 当前皮肤背景渐变（随外观模式切换深浅套）
    var themeGradient: [Color] { currentTheme.gradient(isDark: isDarkMode) }
    /// 当前皮肤卡片色
    var themeCard: Color { currentTheme.card(isDark: isDarkMode) }
    /// 当前皮肤卡片描边
    var themeBorder: Color { currentTheme.border(isDark: isDarkMode) }

    /// 外观强制
    var preferredColorScheme: ColorScheme? {
        appearanceID == "dark" ? .dark : (appearanceID == "light" ? .light : nil)
    }

    // MARK: - Dock 温度角标

    /// 切换激活模式时保护主窗口：切回 accessory 前先把窗口隐藏（否则系统会关闭它，表现为"闪退"），切换后再恢复
    private func switchActivationPolicy(dockVisible: Bool) {
        let wasMainVisible = mainWindowVisible
        let mainWin = NSApp.windows.first { $0.title == "硬件监控" }
        if !dockVisible, let mainWin, mainWin.isVisible {
            mainWin.orderOut(nil)
        }
        NSApp.setActivationPolicy(dockVisible ? .regular : .accessory)
        if !dockVisible, wasMainVisible, let mainWin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                // 窗口可能已被系统销毁，需确认仍存在
                guard NSApp.windows.contains(where: { $0 === mainWin }) else { return }
                mainWin.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func updateDockBadge() {
        if dockBadgeEnabled, let t = snapshot.cpuTempC {
            NSApp.dockTile.badgeLabel = "\(Int(t.rounded()))°"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    // MARK: - 免费功能：系统概览

    /// 开机时长（秒）
    var uptimeSeconds: TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &boot, &size, nil, 0)
        return Date().timeIntervalSince1970 - TimeInterval(boot.tv_sec)
    }

    /// 开机时长文案
    var uptimeText: String {
        let s = Int(uptimeSeconds)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d) 天 \(h) 小时" }
        if h > 0 { return "\(h) 小时 \(m) 分" }
        return "\(m) 分钟"
    }

    /// 今日流量（累计，MB）
    @Published var todayTrafficInMB: Double = 0
    @Published var todayTrafficOutMB: Double = 0
    private var lastNetBytes: (UInt64, UInt64)?
    private var trafficDay = ""
    private var trafficTick = 0

    /// 主线程累加网络差值（读取已在后台完成）
    private func accumulateTraffic(_ b: (UInt64, UInt64)) {
        let day = Date().formatted(.dateTime.day().month())
        if trafficDay != day {
            trafficDay = day
            todayTrafficInMB = 0
            todayTrafficOutMB = 0
            lastNetBytes = b
            saveTraffic()
            return
        }
        if let last = lastNetBytes {
            if b.0 >= last.0 { todayTrafficInMB += Double(b.0 - last.0) / 1_000_000 }
            if b.1 >= last.1 { todayTrafficOutMB += Double(b.1 - last.1) / 1_000_000 }
        }
        lastNetBytes = b
        saveTraffic()
    }

    private func saveTraffic() {
        UserDefaults.standard.set(todayTrafficInMB, forKey: "todayTrafficInMB")
        UserDefaults.standard.set(todayTrafficOutMB, forKey: "todayTrafficOutMB")
        UserDefaults.standard.set(trafficDay, forKey: "trafficDay")
    }

    /// 读取 en0 网络计数器（netstat -ib：Ibytes=列6，Obytes=列9）
    private func readNetBytes() -> (UInt64, UInt64)? {
        guard let out = runCommandCapture("/usr/sbin/netstat", ["-ib"]) else { return nil }
        for line in out.components(separatedBy: "\n") {
            let cols = line.split(separator: " ").map(String.init)
            if cols.count > 10, cols[0] == "en0", cols[2].hasPrefix("<Link") {
                if let i = UInt64(cols[6]), let o = UInt64(cols[9]) {
                    return (i, o)
                }
            }
        }
        return nil
    }

    /// 写入 App Group 共享快照（桌面小组件读取）
    private func writeSharedSnapshot(_ snap: SystemSnapshot) {
        struct Shared: Codable {
            let cpuTemp: Double?
            let cpuPercent: Double
            let memPercent: Double
            let batteryPercent: Int?
            let netDownMBs: Double
            let netUpMBs: Double
            let topProc: String?
            let timestamp: Date
        }
        let obj = Shared(
            cpuTemp: snap.cpuTempC,
            cpuPercent: snap.cpuPercentValue,
            memPercent: snap.memPercentValue,
            batteryPercent: snap.batteryPercent,
            netDownMBs: snap.netDown / 1024 / 1024,
            netUpMBs: snap.netUp / 1024 / 1024,
            topProc: snap.topProcesses.first?.name,
            timestamp: Date()
        )
        guard let data = try? JSONEncoder().encode(obj) else { return }
        UserDefaults(suiteName: "group.com.zzn.hardwaremonitor")?.set(data, forKey: "hwmon_snapshot")
    }

    // MARK: - 远程监控

    var localIP: String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let addr = ptr.pointee.ifa_addr
            guard let addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  let name = String(cString: ptr.pointee.ifa_name, encoding: .utf8),
                  name.hasPrefix("en") || name.hasPrefix("utun") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if !ip.hasPrefix("127."), ip != "0.0.0.0" { return ip }
        }
        return nil
    }

    var remoteURLString: String? {
        localIP.map { "http://\($0):\(remotePort)" }
    }

    func toggleRemote() {
        remoteRunning ? stopRemote() : startRemote()
    }

    func startRemote() {
        remoteServer.port = UInt16(max(1024, min(65535, remotePort)))
        remoteServer.onSnapshot = { [weak self] in self?.snapshot }
        remoteServer.onAction = { [weak self] action in
            Task { @MainActor in
                switch action {
                case "lock": self?.lockScreen()
                case "sleep": self?.sleepDisplay()
                default: break
                }
            }
        }
        do {
            try remoteServer.start()
            remoteRunning = true
            remoteEnabled = true
        } catch {
            remoteRunning = false
        }
    }

    func stopRemote() {
        remoteServer.stop()
        remoteRunning = false
    }

    // MARK: - 压力测试

    private let pressureEngine = PressureTestEngine()
    @Published var pressureRunning = false
    @Published var pressureThreads: Double = 4 { didSet { UserDefaults.standard.set(pressureThreads, forKey: "pressureThreads") } }

    func togglePressure() {
        pressureEngine.isRunning ? stopPressure() : startPressure()
    }

    func startPressure() {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let count = max(1, min(Int(pressureThreads), cores * 2))
        pressureEngine.start(count: count)
        pressureRunning = true
    }

    func stopPressure() {
        pressureEngine.stop()
        pressureRunning = false
    }

    // MARK: - CSV 报告导出

    func exportHistoryCSV() {
        guard !history.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "HardwareMonitor-\(df.string(from: Date())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var csv = "time,cpuPercent,memPercent,cpuTempC,gpuTempC,netDownMBs,netUpMBs\n"
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        for p in history {
            let cpuT = p.cpuTemp.map { String(format: "%.1f", $0) } ?? ""
            let gpuT = p.gpuTemp.map { String(format: "%.1f", $0) } ?? ""
            csv += "\(tf.string(from: p.time)),\(Int(p.cpuPercent)),\(Int(p.memPercent * 100)),\(cpuT),\(gpuT),\(String(format: "%.2f", p.netDownMBs)),\(String(format: "%.2f", p.netUpMBs))\n"
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - 全局快捷键

    @Published var hotkeysEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(hotkeysEnabled, forKey: "hotkeysEnabled")
            updateHotkeys()
        }
    }
    private let hotkeyManager = HotkeyManager()

    func updateHotkeys() {
        if hotkeysEnabled {
            hotkeyManager.start { [weak self] action in
                Task { @MainActor in self?.handleHotkey(action) }
            }
        } else {
            hotkeyManager.stop()
        }
    }

    private func handleHotkey(_ action: HotkeyAction) {
        switch action {
        case .togglePanel: togglePanel()
        case .lockScreen: lockScreen()
        case .sleepDisplay: sleepDisplay()
        case .clearClipboard: clearClipboardHistory()
        }
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
    private var historyCapacity: Int { historyLimit }
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
        pendingLanguage = appLanguage
        themeID = d.string(forKey: "themeID") ?? "aurora"
        appearanceID = d.string(forKey: "appearanceID") ?? "system"
        proTier = ProTier(rawValue: d.string(forKey: "proTier") ?? "") ?? .free
        todayTrafficInMB = d.double(forKey: "todayTrafficInMB")
        todayTrafficOutMB = d.double(forKey: "todayTrafficOutMB")
        trafficDay = d.string(forKey: "trafficDay") ?? ""
        customAccentHex = d.string(forKey: "customAccentHex") ?? "FF9F43"
        dockBadgeEnabled = d.bool(forKey: "dockBadgeEnabled")
        // init 中首次赋值不触发 didSet，需手动同步激活模式
        NSApp.setActivationPolicy(dockBadgeEnabled ? .regular : .accessory)
        updateDockBadge()
        remoteEnabled = d.bool(forKey: "remoteEnabled")
        remotePort = d.object(forKey: "remotePort") == nil ? 8900 : d.integer(forKey: "remotePort")
        pressureThreads = d.object(forKey: "pressureThreads") == nil ? 4 : d.double(forKey: "pressureThreads")
        hotkeysEnabled = d.bool(forKey: "hotkeysEnabled")
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
            Task { @MainActor in self?.isPanelVisible = false }
        }

        hub.onSnapshot = { [weak self] snap, _ in
            guard let self else { return }
            self.snapshot = snap
            self.lastUpdated = Date()
            self.appendHistory(snap)
            self.uiTick += 1
            // 图表：5 秒节流 + 只渲染最近 300 点（全量 1200 点每秒重绘是卡顿主因）
            if self.uiTick % 5 == 1, self.mainWindowVisible || self.isPanelVisible {
                self.chartHistory = Array(self.history.suffix(300))
            }
            self.alertEngine.check(snap, model: self)
            self.refreshAlertActive(snap)
            self.updateDockBadge()
            // 菜单栏文本 2 秒节流（MenuBarExtra 高频刷新卡菜单栏）
            if self.uiTick % 2 == 1 {
                let t = snap.cpuTempC
                self.menuBarText = (t.map { String(format: "%.0f°", $0) } ?? "--")
                    + " · " + String(format: "%.0f%%", snap.cpuPercentValue * 100)
                self.menuBarColor = t.map { $0 > 85 ? .red : ($0 > 70 ? .orange : .primary) } ?? .primary
            }
            // 重活移后台：widget 共享 JSON 编码 + netstat 流量（约 30 秒一次）
            self.trafficTick += 1
            if self.trafficTick % 30 == 0 {
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let self else { return }
                    let bytes = self.readNetBytes()
                    DispatchQueue.main.async {
                        guard let bytes else { return }
                        self.accumulateTraffic(bytes)
                    }
                }
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.writeSharedSnapshot(snap)
            }
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

    /// 菜单栏文本（每 2 次采样更新，避免 MenuBarExtra 高频刷新卡菜单栏）
    @Published var menuBarText = "-- · --%"
    @Published var menuBarColor: Color = .primary

    /// 历史采样点上限（按版本）
    var historyLimit: Int {
        switch proTier {
        case .free: return 300
        case .deluxe: return 600
        case .premium: return 1200
        }
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

    /// 通知权限状态提示
    @Published var notificationStatusMessage: String?

    /// 检查（或请求）通知权限
    func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let msg: String
            switch settings.authorizationStatus {
            case .authorized: msg = "通知权限已开启 ✅"
            case .denied: msg = "通知权限被拒绝 ❌ 请到 系统设置 → 通知 → HardwareMonitor 打开"
            case .notDetermined: msg = "尚未询问，正在请求…"
            default: msg = "通知权限状态未知"
            }
            Task { @MainActor in self.notificationStatusMessage = msg }
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
                    Task { @MainActor in
                        self.notificationStatusMessage = ok ? "通知权限已开启 ✅" : "通知权限被拒绝 ❌ 请到 系统设置 → 通知 → HardwareMonitor 打开"
                    }
                }
            }
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
            Task { @MainActor in self?.checkClipboard() }
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
        // 锁屏通过模拟快捷键（⌃⌘Q）实现，需要「辅助功能」权限；无权限时明确引导而非静默失败
        guard CGPreflightPostEventAccess() else {
            let alert = NSAlert()
            alert.messageText = "锁屏需要辅助功能权限"
            alert.informativeText = "锁屏通过模拟系统快捷键实现，需要「辅助功能」权限。\n\n请到 系统设置 → 隐私与安全性 → 辅助功能 → 打开 HardwareMonitor 的开关，然后重试。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "去设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }
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

    // MARK: - 快捷操作（菜单栏面板）

    @Published var showHiddenFiles: Bool = UserDefaults.standard.bool(forKey: "showHiddenFiles")

    func clearUserCaches() {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        try? fm.removeItem(atPath: "\(home)/Library/Caches")
    }

    func takeScreenshot() {
        // 屏幕录制权限预检（截图必需）
        guard CGPreflightScreenCaptureAccess() else {
            let alert = NSAlert()
            alert.messageText = "截图需要屏幕录制权限"
            alert.informativeText = "请到「系统设置 → 隐私与安全性 → 屏幕录制」打开 HardwareMonitor 的开关，\n然后**退出 App 并重新打开**（macOS 修改权限后必须重启 App 才生效）。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "去设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }
        // 后台线程执行截图（screencapture 需 2-5 秒，避免阻塞主线程）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let dir = NSHomeDirectory() + "/Pictures/HardwareMonitor"
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let path = dir + "/截图-" + formatter.string(from: Date()) + ".png"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", path]
            let errPipe = Pipe()
            p.standardError = errPipe
            p.standardOutput = Pipe()
            do {
                try p.run()
                p.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "截图启动失败"
                    alert.informativeText = "无法启动 screencapture：\(error.localizedDescription)"
                    alert.runModal()
                }
                return
            }
            let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let exitCode = p.terminationStatus
            let size = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            DispatchQueue.main.async {
                if exitCode == 0, size > 0 {
                    // 成功：弹窗显示位置
                    let alert = NSAlert()
                    alert.messageText = "✅ 截图成功"
                    alert.informativeText = "已保存到：\n\(path)"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "打开所在文件夹")
                    alert.addButton(withTitle: "打开图片")
                    alert.addButton(withTitle: "好")
                    let resp = alert.runModal()
                    if resp == .alertFirstButtonReturn {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    } else if resp == .alertSecondButtonReturn {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    return
                }
                // 失败诊断
                let alert = NSAlert()
                alert.messageText = "截图失败"
                var detail = "退出码 \(exitCode)，stderr: \(errStr.isEmpty ? "(空)" : errStr)\n\n"
                detail += "⚠️ macOS 修改屏幕录制权限后必须**退出 App 并重新打开**才会生效。\n\n"
                detail += "请右键右上角菜单栏图标 → 「退出 HardwareMonitor」，再从「启动台」或「应用程序」重新打开。"
                alert.informativeText = detail
                alert.alertStyle = .warning
                alert.addButton(withTitle: "退出 App 并重启")
                alert.addButton(withTitle: "取消")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        UserDefaults.standard.set(showHiddenFiles, forKey: "showHiddenFiles")
        runProcess("/usr/bin/defaults", args: ["write", "com.apple.finder", "AppleShowAllFiles", showHiddenFiles ? "-bool" : "-bool", showHiddenFiles ? "YES" : "NO"])
        runProcess("/usr/bin/killall", args: ["Finder"])
    }

    /// 杀占用：排除自身与系统关键进程，并弹确认框防止误杀
    func killTopProcess() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        // 系统关键进程与自身黑名单（误杀会导致崩溃/黑屏）
        let protectedNames: Set<String> = [
            "kernel_task", "WindowServer", "launchd", "loginwindow",
            "SystemUIServer", "Finder", "ControlCenter", "HardwareMonitor",
            "sysmond", "runningboardd", "backboardd", "notifyd"
        ]
        // 在 TOP 列表里找第一个可安全结束的进程
        guard let p = snapshot.topProcesses.first(where: {
            $0.pid != myPID && !protectedNames.contains($0.name)
        }) else { return }

        let alert = NSAlert()
        alert.messageText = "确定要结束进程吗？"
        alert.informativeText = "将强制结束「\(p.name)」(PID \(p.pid))。\n\n正在运行的程序会被立即关闭，未保存的内容可能丢失。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "结束进程")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            runProcess("/bin/kill", args: ["-9", String(p.pid)])
        }
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
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pomodoroTick() }
        }
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

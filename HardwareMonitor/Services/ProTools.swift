import Foundation
import AppKit

// MARK: - CPU 压力测试引擎

/// 多线程忙循环压测，模拟满载负载（散热/稳定性测试用）
final class PressureTestEngine {
    private var threads: [Thread] = []
    private var lock = NSLock()
    private var shouldStop = false

    private(set) var isRunning = false
    private(set) var threadCount = 0

    func start(count: Int) {
        stop()
        lock.lock()
        shouldStop = false
        isRunning = true
        threadCount = count
        lock.unlock()
        for _ in 0..<count {
            let t = Thread {
                while true {
                    self.lock.lock(); let stop = self.shouldStop; self.lock.unlock()
                    if stop { return }
                    var x = 1.0
                    for _ in 0..<300000 { x = x * 1.0000001 + 0.25 }
                    _ = x
                }
            }
            t.qualityOfService = .utility   // 低优先级，避免满载时抢 UI 线程导致 App 无响应
            t.name = "hwmon-pressure"
            t.start()
            threads.append(t)
        }
    }

    func stop() {
        lock.lock(); shouldStop = true; lock.unlock()
        threads.removeAll()
        lock.lock(); isRunning = false; threadCount = 0; lock.unlock()
    }
}

// MARK: - 启动项扫描（只读展示，不做任何修改）

struct LaunchItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let user: Bool  // true=用户级 ~/Library/LaunchAgents
}

enum LaunchItems {
    static func scan() -> [LaunchItem] {
        var items: [LaunchItem] = []
        let dirs: [(String, Bool)] = [
            (NSHomeDirectory() + "/Library/LaunchAgents", true),
            ("/Library/LaunchAgents", false),
        ]
        for (dir, user) in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for f in files where f.hasSuffix(".plist") {
                items.append(LaunchItem(name: f, path: dir + "/" + f, user: user))
            }
        }
        return items.sorted { $0.name < $1.name }
    }

    static func openUserFolder() {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/LaunchAgents")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 全局快捷键

enum HotkeyAction: CaseIterable, Identifiable {
    case togglePanel, lockScreen, sleepDisplay, clearClipboard
    var id: Self { self }
    var key: String {
        switch self {
        case .togglePanel: return "⌃⌘⌥H"
        case .lockScreen: return "⌃⌘⌥L"
        case .sleepDisplay: return "⌃⌘⌥S"
        case .clearClipboard: return "⌃⌘⌥C"
        }
    }
    var keyCode: UInt16 {
        switch self {
        case .togglePanel: return 4    // H
        case .lockScreen: return 37    // L
        case .sleepDisplay: return 1   // S
        case .clearClipboard: return 8 // C
        }
    }
}

/// 全局快捷键监听（NSEvent 全局监听，组合键 ⌃⌘⌥ + 字母）
final class HotkeyManager {
    private var monitor: Any?

    func start(handler: @escaping (HotkeyAction) -> Void) {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.control, .command, .option, .shift])
            guard flags.contains(.control), flags.contains(.command), flags.contains(.option),
                  !flags.contains(.shift) else { return }
            for action in HotkeyAction.allCases where event.keyCode == action.keyCode {
                handler(action)
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

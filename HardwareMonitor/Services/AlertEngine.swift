import Foundation
import UserNotifications
import AppKit

/// 告警引擎：阈值检查 + 系统通知 + 提示音，同类告警防抖
@MainActor
final class AlertEngine {
    private var lastFired: [String: Date] = [:]
    private let cooldown: TimeInterval = 60

    /// 告警历史（Premium 查看）
    struct AlertRecord: Identifiable {
        let id = UUID()
        let key: String
        let title: String
        let body: String
        let time: Date
    }
    private(set) var history: [AlertRecord] = []

    func clearHistory() { history.removeAll() }

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 检查快照，触发需要的告警
    func check(_ snap: SystemSnapshot, model: AppModel) {
        guard model.alertsEnabled else { return }

        if let t = snap.cpuTempC, t >= model.cpuTempThreshold {
            fire(key: "cpuTemp", title: LZ.t("CPU 温度过高", "CPU Temperature High"),
                 body: String(format: LZ.t("当前 %.0f°C（阈值 %.0f°C）", "Now %.0f°C (threshold %.0f°C)"), t, model.cpuTempThreshold), sound: model.alertSound)
        }
        if let t = snap.gpuTempC, t >= model.gpuTempThreshold {
            fire(key: "gpuTemp", title: LZ.t("GPU 温度过高", "GPU Temperature High"),
                 body: String(format: LZ.t("当前 %.0f°C（阈值 %.0f°C）", "Now %.0f°C (threshold %.0f°C)"), t, model.gpuTempThreshold), sound: model.alertSound)
        }
        if snap.cpuPercentValue >= model.cpuUsageThreshold {
            fire(key: "cpuUsage", title: LZ.t("CPU 占用过高", "High CPU Usage"),
                 body: String(format: LZ.t("当前 %.0f%%（阈值 %.0f%%）", "Now %.0f%% (threshold %.0f%%)"), snap.cpuPercentValue, model.cpuUsageThreshold), sound: model.alertSound)
        }
        if snap.memPercentValue * 100 >= model.memUsageThreshold {
            fire(key: "memUsage", title: LZ.t("内存占用过高", "High Memory Usage"),
                 body: String(format: LZ.t("当前 %.0f%%（阈值 %.0f%%）", "Now %.0f%% (threshold %.0f%%)"), snap.memPercentValue * 100, model.memUsageThreshold), sound: model.alertSound)
        }
        if snap.diskTotal > 0 {
            let freeGB = Double(snap.diskFree) / 1e9
            if freeGB <= model.diskFreeThreshold {
                fire(key: "diskFree", title: LZ.t("磁盘空间不足", "Low Disk Space"),
                     body: String(format: LZ.t("剩余 %.1f GB（阈值 %.0f GB）", "%.1f GB left (threshold %.0f GB)"), freeGB, model.diskFreeThreshold), sound: model.alertSound)
            }
        }
        if let p = snap.batteryPercent, p <= Int(model.batteryPercentThreshold) {
            fire(key: "battery", title: LZ.t("电池电量低", "Low Battery"),
                 body: String(format: LZ.t("当前 %d%%（阈值 %.0f%%）", "Now %d%% (threshold %.0f%%)"), p, model.batteryPercentThreshold), sound: model.alertSound)
        }
    }

    private func fire(key: String, title: String, body: String, sound: Bool) {
        history.insert(AlertRecord(key: key, title: title, body: body, time: Date()), at: 0)
        if history.count > 100 { history.removeLast() }
        let now = Date()
        if let last = lastFired[key], now.timeIntervalSince(last) < cooldown { return }
        lastFired[key] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let request = UNNotificationRequest(identifier: "hwmon.\(key).\(now.timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

import Foundation
import UserNotifications
import AppKit

/// 告警引擎：阈值检查 + 系统通知 + 提示音，同类告警防抖
@MainActor
final class AlertEngine {
    private var lastFired: [String: Date] = [:]
    private let cooldown: TimeInterval = 60

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 检查快照，触发需要的告警
    func check(_ snap: SystemSnapshot, model: AppModel) {
        guard model.alertsEnabled else { return }

        if let t = snap.cpuTempC, t >= model.cpuTempThreshold {
            fire(key: "cpuTemp", title: "CPU 温度过高", body: String(format: "当前 %.0f°C（阈值 %.0f°C）", t, model.cpuTempThreshold), sound: model.alertSound)
        }
        if let t = snap.gpuTempC, t >= model.gpuTempThreshold {
            fire(key: "gpuTemp", title: "GPU 温度过高", body: String(format: "当前 %.0f°C（阈值 %.0f°C）", t, model.gpuTempThreshold), sound: model.alertSound)
        }
        if snap.cpuPercentValue >= model.cpuUsageThreshold {
            fire(key: "cpuUsage", title: "CPU 占用过高", body: String(format: "当前 %.0f%%（阈值 %.0f%%）", snap.cpuPercentValue, model.cpuUsageThreshold), sound: model.alertSound)
        }
        if snap.memPercentValue * 100 >= model.memUsageThreshold {
            fire(key: "memUsage", title: "内存占用过高", body: String(format: "当前 %.0f%%（阈值 %.0f%%）", snap.memPercentValue * 100, model.memUsageThreshold), sound: model.alertSound)
        }
        if snap.diskTotal > 0 {
            let freeGB = Double(snap.diskFree) / 1e9
            if freeGB <= model.diskFreeThreshold {
                fire(key: "diskFree", title: "磁盘空间不足", body: String(format: "剩余 %.1f GB（阈值 %.0f GB）", freeGB, model.diskFreeThreshold), sound: model.alertSound)
            }
        }
        if let p = snap.batteryPercent, p <= Int(model.batteryPercentThreshold) {
            fire(key: "battery", title: "电池电量低", body: String(format: "当前 %d%%（阈值 %.0f%%）", p, model.batteryPercentThreshold), sound: model.alertSound)
        }
    }

    private func fire(key: String, title: String, body: String, sound: Bool) {
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

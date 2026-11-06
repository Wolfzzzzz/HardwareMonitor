import Foundation
import AppKit
import UniformTypeIdentifiers

/// 监控数据导出（版本 26DF10Q1beta2.1.1 新增）
///
/// 把内存里的采样历史导成 CSV，可直接用 Excel / Numbers 打开做分析。
enum CSVExport {

    /// 生成 CSV 文本（含 UTF-8 BOM，Excel 打开不乱码）
    static func monitoringCSV(_ points: [HistoryPoint]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines = ["时间,CPU占用(%),内存占用(%),芯片温度(°C),GPU温度(°C),下行(MB/s),上行(MB/s),风扇(RPM)"]
        for p in points {
            let cpu = String(format: "%.1f", p.cpuPercent)
            let mem = String(format: "%.1f", p.memPercent)
            let cpuT = p.cpuTemp.map { String(format: "%.1f", $0) } ?? ""
            let gpuT = p.gpuTemp.map { String(format: "%.1f", $0) } ?? ""
            let down = String(format: "%.3f", p.netDownMBs)
            let up = String(format: "%.3f", p.netUpMBs)
            lines.append([formatter.string(from: p.time), cpu, mem, cpuT, gpuT, down, up, ""].joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// 弹出保存面板写入文件；返回是否成功
    @MainActor
    @discardableResult
    static func saveMonitoringCSV(_ points: [HistoryPoint]) -> Bool {
        guard !points.isEmpty else { return false }
        let panel = NSSavePanel()
        panel.title = "导出监控数据"
        panel.prompt = "导出"
        let stampFormatter = DateFormatter()
        stampFormatter.dateFormat = "yyyyMMdd-HHmm"
        panel.nameFieldStringValue = "HardwareMonitor-\(stampFormatter.string(from: Date())).csv"
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.commaSeparatedText]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        let csv = monitoringCSV(points)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }
}

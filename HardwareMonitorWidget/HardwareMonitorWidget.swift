import WidgetKit
import SwiftUI

/// 与 App 共享的快照结构（JSON 序列化到 App Group UserDefaults）
struct HWSharedSnapshot: Codable {
    var cpuTemp: Double?
    var cpuPercent: Double
    var memPercent: Double
    var batteryPercent: Int?
    var netDownMBs: Double
    var netUpMBs: Double
    var topProc: String?
    var timestamp: Date
}

struct HWEntry: TimelineEntry {
    let date: Date
    let snap: HWSharedSnapshot?
}

struct HWProvider: TimelineProvider {
    private let suite = "group.com.zzn.hardwaremonitor"

    func placeholder(in context: Context) -> HWEntry {
        HWEntry(date: Date(), snap: HWSharedSnapshot(cpuTemp: 42, cpuPercent: 0.15, memPercent: 0.5, batteryPercent: 80, netDownMBs: 1.2, netUpMBs: 0.3, topProc: "Safari", timestamp: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (HWEntry) -> Void) {
        completion(HWEntry(date: Date(), snap: read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HWEntry>) -> Void) {
        let entry = HWEntry(date: Date(), snap: read())
        // 每 60 秒刷新一次（配合 App 采样写入）
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
    }

    private func read() -> HWSharedSnapshot? {
        guard let d = UserDefaults(suiteName: suite)?.data(forKey: "hwmon_snapshot") else { return nil }
        return try? JSONDecoder().decode(HWSharedSnapshot.self, from: d)
    }
}

struct HWWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: HWEntry

    var body: some View {
        if let s = entry.snap {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "thermometer.medium")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("硬件监控")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(s.cpuTemp.map { String(format: "%.0f", $0) } ?? "--")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tempColor(s.cpuTemp))
                    Text("°C")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(s.cpuTemp.map { $0 > 85 ? "高温" : ($0 > 70 ? "偏高" : "正常") } ?? "无数据")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.orange.opacity(0.15)))
                }
                VStack(spacing: 4) {
                    meterRow("CPU", value: s.cpuPercent, color: .blue)
                    meterRow("内存", value: s.memPercent, color: .purple)
                }
                if let b = s.batteryPercent {
                    Text("🔋 \(b)%\(s.cpuTemp != nil ? "" : "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .containerBackground(for: .widget) { Color(.sRGB, red: 0.07, green: 0.05, blue: 0.15) }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("打开硬件监控\n以启用小组件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .containerBackground(for: .widget) { Color(.sRGB, red: 0.07, green: 0.05, blue: 0.15) }
        }
    }

    private func tempColor(_ t: Double?) -> Color {
        guard let t else { return .primary }
        return t > 85 ? .red : (t > 70 ? .orange : .primary)
    }

    private func meterRow(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(color).frame(width: geo.size.width * max(0, min(1, value)))
                }
            }
            .frame(height: 5)
            Text(String(format: "%.0f%%", value * 100))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

/// 通用 widget 工具：共享读取
enum HWShared {
    static let suite = "group.com.zzn.hardwaremonitor"
    static func read() -> HWSharedSnapshot? {
        guard let d = UserDefaults(suiteName: suite)?.data(forKey: "hwmon_snapshot") else { return nil }
        return try? JSONDecoder().decode(HWSharedSnapshot.self, from: d)
    }
}

/// 网络 widget
struct HWNetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HWNetWidget", provider: HWProvider()) { entry in
            HWNetWidgetView(entry: entry)
        }
        .configurationDisplayName("网络实时")
        .description("上下行网速")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HWNetWidgetView: View {
    let entry: HWEntry
    var body: some View {
        if let s = entry.snap {
            VStack(alignment: .leading, spacing: 6) {
                Label("网络", systemImage: "wifi").font(.caption.weight(.semibold)).foregroundStyle(.cyan)
                HStack {
                    Text("↓").font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%.1f MB/s", s.netDownMBs))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }
                HStack {
                    Text("↑").font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%.1f MB/s", s.netUpMBs))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .containerBackground(for: .widget) { Color(.sRGB, red: 0.04, green: 0.10, blue: 0.18) }
        } else {
            Text("打开硬件监控以启用")
                .font(.caption)
                .foregroundStyle(.secondary)
                .containerBackground(for: .widget) { Color(.sRGB, red: 0.04, green: 0.10, blue: 0.18) }
        }
    }
}

/// 电池 widget
struct HWBatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HWBatteryWidget", provider: HWProvider()) { entry in
            HWBatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("电池")
        .description("电量与温度")
        .supportedFamilies([.systemSmall])
    }
}

struct HWBatteryWidgetView: View {
    let entry: HWEntry
    var body: some View {
        if let s = entry.snap, let b = s.batteryPercent {
            VStack(alignment: .leading, spacing: 6) {
                Label("电池", systemImage: "battery.75percent").font(.caption.weight(.semibold)).foregroundStyle(.green)
                Text("\(b)%")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(s.topProc.map { "Top: \($0)" } ?? "—")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .containerBackground(for: .widget) { Color(.sRGB, red: 0.05, green: 0.13, blue: 0.07) }
        } else {
            Text("未检测到电池")
                .font(.caption)
                .foregroundStyle(.secondary)
                .containerBackground(for: .widget) { Color(.sRGB, red: 0.05, green: 0.13, blue: 0.07) }
        }
    }
}

/// 进程 widget
struct HWProcessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HWProcessWidget", provider: HWProvider()) { entry in
            HWProcessWidgetView(entry: entry)
        }
        .configurationDisplayName("进程 TOP")
        .description("占用最高进程")
        .supportedFamilies([.systemSmall])
    }
}

struct HWProcessWidgetView: View {
    let entry: HWEntry
    var body: some View {
        if let s = entry.snap, let p = s.topProc {
            VStack(alignment: .leading, spacing: 4) {
                Label("TOP 进程", systemImage: "list.number").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                Text(p).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Text(String(format: "CPU %.0f%% · 内存 %.0f%%", s.cpuPercent * 100, s.memPercent * 100))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .containerBackground(for: .widget) { Color(.sRGB, red: 0.18, green: 0.10, blue: 0.04) }
        } else {
            Text("暂无进程数据").font(.caption).foregroundStyle(.secondary)
                .containerBackground(for: .widget) { Color(.sRGB, red: 0.18, green: 0.10, blue: 0.04) }
        }
    }
}

@main
struct HWTWidgetBundle: WidgetBundle {
    var body: some Widget {
        HWWidget()
        HWNetWidget()
        HWBatteryWidget()
        HWProcessWidget()
    }
}

struct HWWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HWTemperatureWidget", provider: HWProvider()) { entry in
            HWWidgetView(entry: entry)
        }
        .configurationDisplayName("硬件监控")
        .description("实时显示 CPU 温度、占用与内存")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

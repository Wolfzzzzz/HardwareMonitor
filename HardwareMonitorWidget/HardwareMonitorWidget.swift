import WidgetKit
import SwiftUI

/// 与 App 共享的快照结构（JSON 序列化到 App Group UserDefaults）
struct HWSharedSnapshot: Codable {
    var cpuTemp: Double?
    var cpuPercent: Double
    var memPercent: Double
    var batteryPercent: Int?
    var timestamp: Date
}

struct HWEntry: TimelineEntry {
    let date: Date
    let snap: HWSharedSnapshot?
}

struct HWProvider: TimelineProvider {
    private let suite = "group.com.zzn.hardwaremonitor"

    func placeholder(in context: Context) -> HWEntry {
        HWEntry(date: Date(), snap: HWSharedSnapshot(cpuTemp: 42, cpuPercent: 0.15, memPercent: 0.5, batteryPercent: 80, timestamp: Date()))
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

@main
struct HWTWidgetBundle: WidgetBundle {
    var body: some Widget {
        HWWidget()
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

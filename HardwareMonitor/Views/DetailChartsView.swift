import SwiftUI
import Charts

/// 详情图区：内存组成饼图 + 磁盘饼图 + 进程 CPU 柱状图
struct DetailChartsView: View {
    let snapshot: SystemSnapshot

    var body: some View {
        VStack(spacing: 14) {
            if snapshot.memTotal > 0 {
                memoryPie
            }
            if snapshot.diskTotal > 0 {
                diskPie
            }
            if !snapshot.topProcesses.isEmpty {
                processBar
            }
        }
    }

    // MARK: - 内存组成饼图

    private struct MemSlice: Identifiable {
        let id = UUID()
        let name: String
        let bytes: UInt64
        let color: Color
    }

    private var memData: [MemSlice] {
        [
            MemSlice(name: "应用内存", bytes: snapshot.memActive, color: .blue),
            MemSlice(name: "联动", bytes: snapshot.memWired, color: .purple),
            MemSlice(name: "压缩", bytes: snapshot.memCompressed, color: .orange),
            MemSlice(name: "空闲", bytes: snapshot.memFree, color: .green)
        ].filter { $0.bytes > 0 }
    }

    private var memoryPie: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("内存组成（总 \(Fmt.bytes(snapshot.memTotal))）")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Chart(memData) { slice in
                    SectorMark(angle: .value("大小", slice.bytes), innerRadius: .ratio(0.62))
                        .foregroundStyle(slice.color)
                        .cornerRadius(2)
                }
                .frame(width: 90, height: 90)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(memData) { s in
                        HStack(spacing: 4) {
                            Circle().fill(s.color).frame(width: 7, height: 7)
                            Text(s.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Fmt.bytes(s.bytes))
                                .font(.caption2.monospacedDigit())
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }

    // MARK: - 磁盘饼图

    private var diskPie: some View {
        let used = snapshot.diskTotal > snapshot.diskFree ? snapshot.diskTotal - snapshot.diskFree : 0
        let data = [
            (name: "已用", bytes: used, color: Color.teal),
            (name: "剩余", bytes: snapshot.diskFree, color: Color.green.opacity(0.7))
        ].filter { $0.bytes > 0 }
        return VStack(alignment: .leading, spacing: 4) {
            Text("磁盘空间（总 \(Fmt.bytes(snapshot.diskTotal))）")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Chart(data, id: \.name) { item in
                    SectorMark(angle: .value("大小", item.bytes), innerRadius: .ratio(0.62))
                        .foregroundStyle(item.color)
                        .cornerRadius(2)
                }
                .frame(width: 90, height: 90)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(data, id: \.name) { item in
                        HStack(spacing: 4) {
                            Circle().fill(item.color).frame(width: 7, height: 7)
                            Text(item.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Fmt.bytes(item.bytes))
                                .font(.caption2.monospacedDigit())
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }

    // MARK: - 进程 CPU 柱状图（横向条形，名称完整可读）

    var processBar: some View {
        let top = Array(snapshot.topProcesses.prefix(8))
        return VStack(alignment: .leading, spacing: 4) {
            Text("进程 CPU 占用 TOP \(top.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ProcessBarChart(items: top)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }
}

/// 进程 CPU 横向条形图（独立视图，避免表达式过复杂）
struct ProcessBarChart: View {
    let items: [ProcessItem]

    var body: some View {
        Chart(items) { p in
            BarMark(x: .value("CPU%", p.cpuPercent), y: .value("进程", p.name))
                .foregroundStyle(.blue.opacity(0.8))
                .cornerRadius(3)
        }
        .chartXScale(domain: 0...(max(100, (items.map { $0.cpuPercent }.max() ?? 100)) * 1.15))
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.1))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        Text(name)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .frame(height: 150)
    }
}

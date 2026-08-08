import SwiftUI
import Charts

/// 趋势图：温度 / CPU / 内存 / 网络历史曲线
struct ChartsView: View {
    let history: [HistoryPoint]

    var body: some View {
        VStack(spacing: 12) {
            if history.contains(where: { $0.cpuTemp != nil }) {
                temperatureChart
            }
            cpuChart
            memoryChart
            networkChart
        }
    }

    // 温度曲线（SMC 可用时）
    private var temperatureChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("温度 (°C)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Chart(history) { p in
                if let t = p.cpuTemp {
                    LineMark(x: .value("时间", p.time), y: .value("CPU", t))
                        .foregroundStyle(.orange)
                }
                if let g = p.gpuTemp {
                    LineMark(x: .value("时间", p.time), y: .value("GPU", g))
                        .foregroundStyle(.red)
                }
            }
            .chartYScale(domain: 20...110)
            .frame(height: 90)
        }
    }

    private var cpuChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CPU 占用率 (%)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Chart(history) { p in
                LineMark(x: .value("时间", p.time), y: .value("CPU", p.cpuPercent))
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100)
            .frame(height: 80)
        }
    }

    private var memoryChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("内存占用率 (%)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Chart(history) { p in
                LineMark(x: .value("时间", p.time), y: .value("内存", p.memPercent))
                    .foregroundStyle(.purple)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100)
            .frame(height: 80)
        }
    }

    private var networkChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("网络速率 (MB/s)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Chart(history) { p in
                LineMark(x: .value("时间", p.time), y: .value("下行", p.netDownMBs))
                    .foregroundStyle(.cyan)
                LineMark(x: .value("时间", p.time), y: .value("上行", p.netUpMBs))
                    .foregroundStyle(.green)
            }
            .chartYScale(domain: 0...max(1, history.map { max($0.netDownMBs, $0.netUpMBs) }.max() ?? 1))
            .frame(height: 80)
        }
    }
}

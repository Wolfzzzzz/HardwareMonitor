import SwiftUI

/// 进程资源占用排行
struct ProcessListView: View {
    let processes: [ProcessItem]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            rows
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack {
            Text("进程")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("CPU")
                .frame(width: 52, alignment: .trailing)
            Text("内存")
                .frame(width: 72, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var rows: some View {
        ForEach(Array(processes.enumerated()), id: \.element.id) { index, p in
            HStack(spacing: 6) {
                Text("\(index + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Image(systemName: "gearshape.2")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(p.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: "%.0f%%", p.cpuPercent))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(p.cpuPercent > 50 ? .red : (p.cpuPercent > 20 ? .orange : .primary))
                    .frame(width: 52, alignment: .trailing)
                Text(String(format: "%.0f MB", p.memoryMB))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            if index < processes.count - 1 { Divider().padding(.leading, 34) }
        }
    }
}

import SwiftUI

/// 剪贴板历史页
struct ClipboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("剪贴板历史", systemImage: "doc.on.clipboard")
                    .font(.headline)
                Spacer()
                Toggle("记录", isOn: $model.clipboardEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Button("清空") { model.clearClipboardHistory() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text("自动记录复制过的文本（最近 \(model.clipboardLimit) 条，仅保存在本机内存）。点击条目复制回剪贴板，📌 固定防止被顶掉。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if model.clipboardItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("暂无记录，复制点什么试试")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.clipboardItems) { item in
                            row(item)
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    private func row(_ item: ClipboardItem) -> some View {
        let isLast = model.lastCopiedID == item.id
        return HStack(alignment: .top, spacing: 8) {
            Button {
                model.copyClipboardItem(item)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.text)
                        .font(.caption)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(shortDate(item.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Button {
                model.togglePin(item)
            } label: {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(item.pinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                model.deleteClipboardItem(item)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isLast ? Color.blue.opacity(0.15) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isLast ? Color.blue.opacity(0.4) : .clear, lineWidth: 1)
        )
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}

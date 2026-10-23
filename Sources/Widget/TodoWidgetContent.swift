import SwiftUI
import YIClassCore

struct TodoWidgetContent: View {
    enum Layout { case rectangular, circular, inline }
    let todos: [TodoItem]
    let date: Date
    var layout = Layout.rectangular
    var issue: String?
    private var pending: [TodoItem] { TodoItem.ranked(todos, on: date) }
    var body: some View {
        Group {
            if let issue { Text(issue).font(.caption).lineLimit(3) }
            else if pending.isEmpty {
                if layout == .inline { Text("待办已清空") }
                else {
                    VStack(spacing: 3) {
                        Image(systemName: "checkmark.circle").font(.title3)
                        Text("暂无待办").font(.caption)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if layout == .inline {
                Text("\(pending.count) 项待办 · \(pending[0].title)")
            } else if layout == .circular {
                VStack(spacing: 1) {
                    Text("\(pending.count)").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("待完成").font(.system(size: 10))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pending[0].title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 3) {
                            Text(pending[0].urgency(on: date))
                            if let deadline = pending[0].deadline, Calendar.current.isDate(deadline, inSameDayAs: date) {
                                Text(deadline, style: .time).monospacedDigit()
                            }
                        }.font(.system(size: 11)).lineLimit(1)
                        if geometry.size.height >= 64, pending.count > 1 {
                            Text(pending[1].title).font(.system(size: 11)).lineLimit(1).foregroundStyle(.secondary)
                        }
                        if geometry.size.height >= 60 {
                            Text("剩余 \(pending.count) 项").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                }
            }
        }.privacySensitive()
    }
}

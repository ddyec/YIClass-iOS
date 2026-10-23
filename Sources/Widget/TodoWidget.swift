import SwiftUI
import WidgetKit
import YIClassCore

struct TodoWidgetEntry: TimelineEntry {
    let date: Date
    let todos: [TodoItem]
    let issue: String?
}
struct TodoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoWidgetEntry {
        TodoWidgetEntry(date: Date(), todos: [TodoItem(title: "完成实验报告", deadline: Date().addingTimeInterval(3600))], issue: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (TodoWidgetEntry) -> Void) { completion(entry(at: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoWidgetEntry>) -> Void) {
        let now = Date()
        switch SharedLibrary.readResult() {
        case .success(let data):
            let dates = TodoWidgetSchedule.dates(todos: data.todos, now: now)
            completion(Timeline(entries: dates.map { TodoWidgetEntry(date: $0, todos: data.todos, issue: data.todoSyncIssue) }, policy: .after(dates.last ?? now.addingTimeInterval(3600))))
        case .failure(let error):
            completion(Timeline(entries: [TodoWidgetEntry(date: now, todos: [], issue: error.localizedDescription)], policy: .after(now.addingTimeInterval(900))))
        }
    }
    private func entry(at date: Date) -> TodoWidgetEntry {
        switch SharedLibrary.readResult() {
        case .success(let data): return TodoWidgetEntry(date: date, todos: data.todos, issue: data.todoSyncIssue)
        case .failure(let error): return TodoWidgetEntry(date: date, todos: [], issue: error.localizedDescription)
        }
    }
}
struct TodoLockWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodoWidgetEntry
    var body: some View {
        TodoWidgetContent(todos: entry.todos, date: entry.date,
            layout: family == .accessoryInline ? .inline : family == .accessoryCircular ? .circular : .rectangular,
            issue: entry.issue)
            .containerBackground(.clear, for: .widget)
            .widgetURL(URL(string: "yiclass://todos"))
    }
}
struct TodoLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YIClassTodoLockScreen", provider: TodoWidgetProvider()) { TodoLockWidgetView(entry: $0) }
            .configurationDisplayName("待办清单")
            .description("显示最紧急的待办及截止时间，圆形显示未完成数量。点按打开待办。")
            .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
            .contentMarginsDisabled()
    }
}

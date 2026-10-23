import SwiftUI
import YIClassCore

struct DayTimelineView: View {
    @Environment(AppStore.self) private var store
    let date: Date
    var bottomInset: CGFloat = 0
    var onCourse: (Course) -> Void
    @State private var editing: TodoItem?
    @State private var proposedStart: Date?
    var body: some View {
        TimelineView(.everyMinute) { context in
            let reference = Calendar.current.isDate(date, inSameDayAs: context.date) ? context.date : date
            let items = DayAgendaEngine.items(data: store.data, agenda: store.agenda, on: reference)
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let issue = store.agendaIssue { AgendaRecoveryPanel(issue: issue) }
                        HStack {
                            Label("日程", systemImage: "clock").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            if !items.isEmpty { Button("首项") { scroll(reader, items: items) }.font(.caption) }
                            Button("安排待办", systemImage: "plus") {
                                proposedStart = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date)
                                editing = TodoItem(title: "")
                            }.font(.subheadline)
                        }.id("agenda-top")
                        let deadlines = DayAgendaEngine.deadlines(store.data.todos, on: date)
                        if !deadlines.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("当天截止", systemImage: "flag").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(deadlines) { todo in
                                    Button { proposedStart = nil; editing = todo } label: {
                                        HStack {
                                            Circle().fill(Color(argb: TodoPalette.color(todo.urgencyLevel(on: context.date)))).frame(width: 5, height: 5)
                                            Text(todo.title).lineLimit(1)
                                            Spacer(minLength: 4)
                                            if let deadline = todo.deadline { Text(deadline, style: .time).monospacedDigit() }
                                        }.font(.caption).foregroundStyle(.primary).frame(minHeight: 32)
                                    }.buttonStyle(.plain)
                                }
                            }.padding(12).background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                        }
                        let inbox = TodoItem.ranked(store.data.todos, on: reference).filter { $0.deadline == nil && store.agenda.placement(for: $0.id) == nil }
                        if !inbox.isEmpty {
                            DisclosureGroup {
                                ForEach(inbox) { todo in
                                    TodoTaskCard(item: todo, reference: reference, complete: { toggle(todo) }, edit: { proposedStart = nil; editing = todo })
                                }
                            } label: {
                                Label("未安排时间 · \(inbox.count) 项", systemImage: "tray")
                                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            }
                        }
                        DayTimelineCanvas(items: items, date: date, now: context.date) { item in
                            if item.kind == .course, let course = store.table.courses.first(where: { $0.id == item.sourceID }) { onCourse(course) }
                            if item.kind == .todo, let todo = store.data.todos.first(where: { $0.id == item.sourceID }) { proposedStart = nil; editing = todo }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 4)
                    .padding(.bottom, bottomInset + 16)
                    .background { TabBarScrollConnection() }
                }
                .accessibilityIdentifier("day-agenda-scroll")

                .onChange(of: date) { _, _ in reader.scrollTo("agenda-top", anchor: .top) }
            }
        }
        .sheet(item: $editing) { todo in
            TodoEditor(item: todo, placement: store.agenda.placement(for: todo.id), proposedStart: proposedStart)
        }
    }
    private func toggle(_ todo: TodoItem) {
        var changed = todo; changed.completedAt = todo.completedAt == nil ? Date() : nil
        store.perform { try store.saveTodo(changed) }
    }
    private func scroll(_ reader: ScrollViewProxy, items: [AgendaTimelineItem]) {
        let first = (items.map(\.startMinute).min() ?? 480) / 60
        reader.scrollTo("agenda-hour-\(max(0, first - 1))", anchor: .top)
    }
}

struct AgendaRecoveryPanel: View {
    @Environment(AppStore.self) private var store
    let issue: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(issue).font(.subheadline)
            HStack {
                Button("恢复日程备份") { store.perform { try store.recoverAgendaBackup() } }
                ShareLink("导出原文件", item: store.agendaURL)
            }.font(.caption)
        }.padding(12).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

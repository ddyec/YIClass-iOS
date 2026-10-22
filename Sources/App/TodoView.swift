import SwiftUI
import YIClassCore

struct TodoView: View {
    @Environment(AppStore.self) private var store
    @State private var day = Date()
    @State private var editing: TodoItem?
    @State private var assistant = false
    @State private var showCompleted = false
    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let reference = Calendar.current.isDateInToday(day) ? context.date : day
                let items = TodoItem.ranked(store.data.todos, on: reference)
                List {
                    Section {
                        DatePicker("查看日期", selection: $day, displayedComponents: .date)
                        if !Calendar.current.isDateInToday(day) { Button("回到今天") { day = Date() } }
                        Text("按重要程度和距截止日期的天数排序；逾期、当日截止优先。无截止时间的事项持续保留。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("待处理 · \(items.count)") {
                        if items.isEmpty {
                            ContentUnavailableView("这天没有待办", systemImage: "checklist", description: Text("点右上角添加，或让 AI 帮你整理。"))
                        }
                        ForEach(items) { item in
                            row(item, reference: reference)
                                .swipeActions(edge: .trailing) {
                                    Button("删除", role: .destructive) { store.perform { try store.deleteTodo(item.id) } }
                                }
                        }
                    }
                    Section {
                        DisclosureGroup("已完成", isExpanded: $showCompleted) {
                            ForEach(store.data.todos.filter { $0.completedAt != nil }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }) { item in
                                row(item, reference: reference)
                                    .swipeActions { Button("删除", role: .destructive) { store.perform { try store.deleteTodo(item.id) } } }
                            }
                        }
                    }
                    if store.undoData != nil {
                        Section { Button("撤销最近一次更改", systemImage: "arrow.uturn.backward") { store.perform { try store.undo() } } }
                    }
                }
            }
            .navigationTitle("待办")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("AI 导入", systemImage: "sparkles") { assistant = true } }
                ToolbarItem(placement: .topBarTrailing) { Button("添加待办", systemImage: "plus") { editing = TodoItem(title: "") } }
            }
            .sheet(item: $editing) { TodoEditor(item: $0) }
            .sheet(isPresented: $assistant) { AssistantView(todoMode: true) }
        }
    }
    private func row(_ item: TodoItem, reference: Date) -> some View {
        HStack(spacing: 12) {
            Button {
                var changed = item; changed.completedAt = item.completedAt == nil ? Date() : nil
                store.perform { try store.saveTodo(changed) }
            } label: {
                Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title2).frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.plain).accessibilityLabel(item.completedAt == nil ? "完成：\(item.title)" : "重新打开：\(item.title)")
            Button { editing = item } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).foregroundStyle(.primary).strikethrough(item.completedAt != nil)
                    if let deadline = item.deadline {
                        Text(deadline.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("重要程度：\(item.importance.title)")
                        if item.completedAt == nil { Text(item.urgency(on: reference)) }
                        Text(item.source == .assistant ? "AI 导入" : "手动添加")
                    }.font(.caption2).foregroundStyle(.secondary)
                    if !item.notes.isEmpty { Text(item.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

struct TodoEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodoItem
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    init(item: TodoItem) {
        _draft = State(initialValue: item)
        _hasDeadline = State(initialValue: item.deadline != nil)
        _deadline = State(initialValue: item.deadline ?? Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date()) ?? Date())
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("事项") {
                    TextField("要做什么", text: $draft.title, axis: .vertical)
                    TextField("备注（可选）", text: $draft.notes, axis: .vertical)
                    Picker("重要程度", selection: $draft.importance) {
                        ForEach(TodoImportance.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Deadline") {
                    Toggle("设置截止时间", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("最晚完成时间", selection: $deadline, displayedComponents: [.date, .hourAndMinute]) }
                    Text("重要程度由你决定，紧急程度随日期自动更新。").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("编辑待办").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.deadline = hasDeadline ? deadline : nil
                        do { try store.saveTodo(draft); dismiss() } catch { store.error = error.localizedDescription }
                    }.disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

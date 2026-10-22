import SwiftUI
import YIClassCore

struct TodoView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var editing: TodoItem?
    @State private var day = Date()
    @State private var choosingDate = false
    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let reference = Calendar.current.isDateInToday(day) ? context.date : day
                let items = TodoItem.ranked(store.data.todos, on: reference)
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Text("待办").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Button { choosingDate = true } label: {
                            Text(day, format: .dateTime.month().day().weekday(.abbreviated))
                                .font(.subheadline).foregroundStyle(.primary)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看日期，\(day.formatted(date: .complete, time: .omitted))")
                        .accessibilityIdentifier("todo-calendar")
                    }.padding(.horizontal, 20).padding(.vertical, 8)
                    List {
                        Section {
                            if items.isEmpty {
                                Label("暂无待办", systemImage: "checklist")
                                    .foregroundStyle(.secondary).padding(.vertical, 12)
                                    .listRowBackground(Color.clear)
                            }
                            ForEach(items) { item in
                                taskRow(item, reference: reference)
                            }
                        }
                        Section {
                            Button("添加待办", systemImage: "plus") { editing = TodoItem(title: "") }
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        Section("已完成") {
                            if !store.data.todos.contains(where: { $0.completedAt != nil }) {
                                Text("暂无已完成事项").foregroundStyle(.secondary)
                            }
                            ForEach(store.data.todos.filter { $0.completedAt != nil }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }) { item in
                                taskRow(item, reference: reference)
                            }
                        }
                        if store.undoData != nil {
                            Section { Button("撤销最近一次更改", systemImage: "arrow.uturn.backward") { store.perform { try store.undo() } } }
                        }
                    }
                    .listRowSpacing(10)
                    .listSectionSpacing(16)
                    .contentMargins(.top, 8, for: .scrollContent)
                    .floatingNavigationScrollTracking()
                }
                .onChange(of: Calendar.current.startOfDay(for: context.date)) { old, new in
                    if Calendar.current.isDate(day, inSameDayAs: old) { day = new }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editing) { TodoEditor(item: $0) }
            .sheet(isPresented: $choosingDate) {
                NavigationStack {
                    DatePicker("查看日期", selection: $day, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .navigationTitle("查看日期").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) { Button("今天") { day = Date() } }
                            ToolbarItem(placement: .confirmationAction) { Button("完成") { choosingDate = false } }
                        }
                }.presentationDetents([.medium, .large])
            }
        }
    }
    private func taskRow(_ item: TodoItem, reference: Date) -> some View {
        row(item, reference: reference)
            .padding(.vertical, 6)
            .listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 20)
                    .fill(urgencyColor(item, reference: reference).opacity(colorScheme == .dark ? 0.24 : 0.12))
            )
            .swipeActions(edge: .trailing) {
                Button("删除", role: .destructive) { store.perform { try store.deleteTodo(item.id) } }
            }
    }
    private func urgencyColor(_ item: TodoItem, reference: Date) -> Color {
        switch item.urgencyLevel(on: reference) {
        case .overdue: .red
        case .today: .orange
        case .soon: .yellow
        case .upcoming: .blue
        case .unscheduled: .gray
        case .completed: .green
        }
    }
    private func row(_ item: TodoItem, reference: Date) -> some View {
        HStack(spacing: 10) {
            Button {
                var changed = item; changed.completedAt = item.completedAt == nil ? Date() : nil
                store.perform { try store.saveTodo(changed) }
            } label: {
                Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title2).frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(item.completedAt == nil ? Color.primary : Color.secondary)
            }.buttonStyle(.plain).accessibilityLabel(item.completedAt == nil ? "完成：\(item.title)" : "重新打开：\(item.title)")
            Button { editing = item } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title).font(.headline).foregroundStyle(.primary).strikethrough(item.completedAt != nil)
                    HStack(spacing: 8) {
                        Text(item.urgency(on: reference)).fontWeight(.medium)
                        if let deadline = item.deadline {
                            Text(deadline.formatted(date: .abbreviated, time: .shortened))
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                    if item.importance == .high { Text("重要").font(.caption.weight(.medium)).foregroundStyle(.primary) }
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

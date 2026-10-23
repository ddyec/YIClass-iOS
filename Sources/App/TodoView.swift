import SwiftUI
import YIClassCore

struct TodoView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: TodoItem?
    @State private var day = Date()
    @State private var choosingDate = false
    @State private var showCompleted = true
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()
                TimelineView(.everyMinute) { context in
                    let reference = Calendar.current.isDateInToday(day) ? context.date : Calendar.current.startOfDay(for: day)
                    let items = TodoItem.ranked(store.data.todos, on: reference)
                    VStack(spacing: 12) {
                        HStack {
                            Text("待办").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button("添加待办", systemImage: "plus") { editing = TodoItem(title: "") }
                                .labelStyle(.iconOnly).frame(width: 44, height: 44).buttonStyle(.glass)
                        }.padding(.horizontal, 16)
                        HStack(spacing: 10) {
                            Button("前一天", systemImage: "chevron.left") { move(-1) }.labelStyle(.iconOnly).frame(width: 40, height: 36)
                            Button { choosingDate = true } label: {
                                Text(day, format: .dateTime.month().day().weekday()).font(.headline).frame(maxWidth: .infinity)
                            }.accessibilityIdentifier("todo-calendar")
                            Button("本日") { day = Date() }.font(.subheadline)
                            Button("后一天", systemImage: "chevron.right") { move(1) }.labelStyle(.iconOnly).frame(width: 40, height: 36)
                        }.padding(.horizontal, 16)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if let issue = store.agendaIssue { AgendaRecoveryPanel(issue: issue) }
                                HStack {
                                    Text("待完成").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                    Spacer(); Text("\(items.count) 项").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                if items.isEmpty {
                                    Label("暂无待办", systemImage: "checklist").font(.subheadline).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
                                }
                                ForEach(items) { item in card(item, reference: reference) }
                                let completed = store.data.todos.filter { $0.completedAt != nil }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                                DisclosureGroup(isExpanded: $showCompleted) {
                                    ForEach(completed) { item in card(item, reference: reference) }
                                    if completed.isEmpty { Text("暂无已完成事项").font(.caption).foregroundStyle(.secondary).padding(.top, 8) }
                                } label: { Text("已完成 · \(completed.count)").font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }
                                .padding(.top, 8)
                                if store.undoData != nil {
                                    Button("撤销最近一次更改", systemImage: "arrow.uturn.backward") { store.perform { try store.undo() } }.font(.caption).padding(.top, 6)
                                }
                            }.padding(.horizontal, 16).padding(.bottom, 16)
                                .background { TabBarScrollConnection() }
                        }.floatingNavigationScrollTracking()
                    }.padding(.top, 8)
                    .onChange(of: Calendar.current.startOfDay(for: context.date)) { old, new in
                        if Calendar.current.isDate(day, inSameDayAs: old) { day = new }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editing) { TodoEditor(item: $0, placement: store.agenda.placement(for: $0.id)) }
            .sheet(isPresented: $choosingDate) {
                NavigationStack {
                    DatePicker("查看日期", selection: $day, displayedComponents: .date).datePickerStyle(.graphical).padding()
                        .navigationTitle("查看日期").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { choosingDate = false } } }
                }.presentationDetents([.medium, .large])
            }
        }
    }
    private func move(_ offset: Int) { day = Calendar.current.date(byAdding: .day, value: offset, to: day) ?? day }
    private func card(_ item: TodoItem, reference: Date) -> some View {
        TodoTaskCard(item: item, reference: reference, placement: store.agenda.placement(for: item.id), complete: {
            var changed = item; changed.completedAt = item.completedAt == nil ? Date() : nil
            store.perform { try store.saveTodo(changed) }
        }, edit: { editing = item })
        .contextMenu {
            Button("编辑", systemImage: "pencil") { editing = item }
            Button("删除", systemImage: "trash", role: .destructive) { store.perform { try store.deleteTodo(item.id) } }
        }
    }
}

struct TodoEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodoItem
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var hasSchedule: Bool
    @State private var scheduledStart: Date
    @State private var scheduledEnd: Date
    init(item: TodoItem, placement: TodoPlacement? = nil, proposedStart: Date? = nil) {
        let start = placement?.start ?? proposedStart ?? Date()
        _hasSchedule = State(initialValue: placement != nil || proposedStart != nil)
        _scheduledStart = State(initialValue: start)
        _scheduledEnd = State(initialValue: placement?.end ?? start.addingTimeInterval(3600))
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
                    Toggle("已完成", isOn: Binding(get: { draft.completedAt != nil }, set: { draft.completedAt = $0 ? Date() : nil }))
                    Picker("重要程度", selection: $draft.importance) {
                        ForEach(TodoImportance.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("安排到日视图") {
                    Toggle("安排工作时间", isOn: $hasSchedule)
                    if hasSchedule {
                        DatePicker("开始", selection: $scheduledStart, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("结束", selection: $scheduledEnd, displayedComponents: [.date, .hourAndMinute])
                        if scheduledEnd <= scheduledStart { Text("结束时间需要晚于开始时间").font(.caption).foregroundStyle(.red) }
                    }
                    Text("安排时间决定日视图中的位置，截止时间表示最晚完成时间。").font(.caption).foregroundStyle(.secondary)
                }
                Section("截止时间") {
                    Toggle("设置截止时间", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("最晚完成时间", selection: $deadline, displayedComponents: [.date, .hourAndMinute]) }
                    Text("重要程度由你决定，紧急程度随日期自动更新。").font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: scheduledStart) { old, new in
                scheduledEnd = new.addingTimeInterval(max(900, scheduledEnd.timeIntervalSince(old)))
            }
            .navigationTitle("编辑待办").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.deadline = hasDeadline ? deadline : nil
                        do { try store.saveTodo(draft, placement: hasSchedule ? TodoPlacement(todoID: draft.id, start: scheduledStart, end: scheduledEnd) : nil, updateSchedule: true); dismiss() } catch { store.error = error.localizedDescription }
                    }.disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (hasSchedule && scheduledEnd <= scheduledStart))
                }
            }
        }
    }
}

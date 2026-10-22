import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import YIClassCore

struct JSONDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw AppFailure("文件不可读。") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct ImportSelection: Identifiable { let id = UUID(); let preview: ImportPreview }

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @State private var reminders = LessonReminderManager.shared
    @State private var wideLesson = LastLessonActivityManager.shared
    @Environment(\.openURL) private var openURL
    @State private var importing = false
    @State private var reading = false
    @State private var aiImport = false
    @State private var exporting = false
    @State private var document = JSONDocument(data: Data())
    @State private var selection: ImportSelection?
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("显示模式", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    NavigationLink("自由配色") { ThemeSettingsView() }
                    NavigationLink("统一课节时间") { TimeSettingsView() }
                    NavigationLink("学期与课表设置") { SemesterSettingsView() }
                    NavigationLink("AI 模式与接口配置") { AISettingsView() }
                }
                Section("上课提醒") {
                    Toggle("提醒当前课表", isOn: Binding(get: { reminders.enabled }, set: { value in
                        Task { await reminders.setEnabled(value, data: store.data) }
                    })).disabled(reminders.requesting)
                    if reminders.enabled {
                        Picker("提醒时间", selection: Binding(get: { reminders.leadMinutes }, set: { reminders.setLeadMinutes($0, data: store.data) })) {
                            Text("上课时").tag(0)
                            ForEach([5, 10, 15, 30], id: \.self) { Text("提前 \($0) 分钟").tag($0) }
                        }
                        Text("已安排 \(reminders.pendingCount) 条提醒").font(.caption).foregroundStyle(.secondary)
                    }
                    if reminders.authorization == .denied {
                        Button("打开系统通知设置", systemImage: "bell.slash") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                    }
                    if let issue = reminders.issue { Text(issue).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("导入与备份") {
                    Button("AI 识别课表", systemImage: "sparkles") { aiImport = true }
                    Button("导入 JSON 课表", systemImage: "square.and.arrow.down") { importing = true }.disabled(reading)
                    Button("导出当前课表", systemImage: "square.and.arrow.up") {
                        do {
                            document = JSONDocument(data: try TimetableTransfer.encode(table: store.table, profile: store.profile))
                            exporting = true
                        } catch { store.error = error.localizedDescription }
                    }
                }
                if reading { ProgressView("正在读取课表…") }
                Section("小组件") {
                    Toggle("锁屏实时活动", isOn: Binding(get: { wideLesson.enabled }, set: {
                        wideLesson.setEnabled($0, data: store.data)
                    }))
                    if wideLesson.enabled {
                        Picker("展示范围", selection: Binding(get: { wideLesson.allLessons }, set: { wideLesson.setAllLessons($0, data: store.data) })) {
                            Text("仅末课宽幅").tag(false)
                            Text("当前与后续课程").tag(true)
                        }
                        Toggle("在灵动岛显示课程内容", isOn: Binding(get: { wideLesson.islandEnabled }, set: { wideLesson.setIslandEnabled($0, data: store.data) }))
                        if !wideLesson.islandEnabled {
                            Text("此开关只隐藏课程文字；实时活动仍可能占据灵动岛。iOS 不提供仅保留锁屏实时活动的独立开关。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if wideLesson.allLessons {
                            Text("回到应用时更新。后台到下课节点若未更新，可点卡片内“刷新课程”；普通组件继续自动按时间线切课。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if wideLesson.enabled {
                        Button("完全不占灵动岛（关闭实时活动）", systemImage: "rectangle.slash") {
                            wideLesson.setEnabled(false, data: store.data)
                        }
                        Text("关闭后结束课程实时活动，包括已预排的活动；普通锁屏课表组件继续可用，不显示实时活动的大幅卡片。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("课程实时活动已关闭，不会占用灵动岛。锁屏可添加普通“课程安排”和“后续课程”组件。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let issue = wideLesson.issue {
                        Text(issue).font(.footnote).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("锁屏并排显示两门课") {
                        Text("长按锁屏 → 自定 → 锁定屏幕 → 添加小组件。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("各添加一个长方形的“课程安排”和“后续课程”，两门课会分别使用完整空间。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("同步课表到小组件", systemImage: "arrow.triangle.2.circlepath") { store.syncWidgets() }
                    if let date = store.widgetLastSync { LabeledContent("最近同步") { Text(date, style: .time) } }
                    if let issue = store.widgetSyncIssue { Text(issue).font(.footnote).foregroundStyle(.secondary) }
                }
                if store.undoData != nil {
                    Section { Button("撤销最近一次方案、导入或删除", systemImage: "arrow.uturn.backward") { store.perform { try store.undo() } } }
                }
                Section {
                    Button("删除当前课表", role: .destructive) { deleting = true }.disabled(store.data.timetables.count == 1)
                }
                Section("关于") {
                    Text("基于 YIClass 的原生重写。原项目 Copyright 2025 wykwey，Apache License 2.0。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("原项目与开源协议", destination: URL(string: "https://github.com/ddyec/YIClass")!)
                }
            }.environment(\.defaultMinListRowHeight, 40).listSectionSpacing(.compact)
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .background {
                DocumentImportPicker(isPresented: $importing, contentTypes: [.json]) { url in
                    if let url { importChosenFile(url) }
                }.frame(width: 0, height: 0)
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "YIClass-课表") { result in
                if case .failure(let error) = result { store.error = error.localizedDescription }
            }
            .sheet(isPresented: $aiImport) { AssistantView(importMode: true) }
            .sheet(item: $selection) { ImportReviewView(preview: $0.preview) }
            .confirmationDialog("删除“\(store.table.name)”？", isPresented: $deleting, titleVisibility: .visible) {
                Button("删除课表", role: .destructive) { store.perform { try store.deleteTable(store.table.id) } }
            }
        }
    }
    private func importChosenFile(_ url: URL) {
        reading = true
        Task {
            do {
                let file = try await DocumentFileReader.read(url, maximumBytes: 10_000_000)
                selection = ImportSelection(preview: try TimetableTransfer.decode(file.data))
            } catch { store.error = error.localizedDescription }
            reading = false
        }
    }

}

struct ImportReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let preview: ImportPreview
    @State private var importName = ""
    @State private var startDate = Date()
    @State private var adoptTimes = false
    @State private var issue: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("课表预览") {
                    TextField("课表名称", text: $importName)
                    DatePicker("开学日期", selection: $startDate, displayedComponents: .date)
                    LabeledContent("课程", value: "\(Set(preview.table.courses.map(\.name)).count) 门 · \(preview.table.courses.flatMap(\.schedules).count) 条安排")
                    LabeledContent("学期", value: "\(preview.table.totalWeeks) 周")
                    if let warning = preview.warning { Text(warning).font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Text("默认沿用当前统一课节时间（\(store.profile.periods.count) 节）。")
                    if let profile = preview.suggestedProfile {
                        Toggle("采用文件内的时间，更新所有课表", isOn: $adoptTimes)
                        if adoptTimes { ForEach(profile.periods) { Text("第 \($0.period) 节  \($0.label)").font(.footnote.monospacedDigit()) } }
                    }
                } footer: { Text("导入会新建一份课表。现有课程不会被覆盖。") }
                Section("课程记录") {
                    ForEach(preview.table.courses) { course in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(course.name)
                            Text([course.location, course.teacher].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            ForEach(course.schedules.indices, id: \.self) { index in
                                let schedule = course.schedules[index]
                                Text("\(weekdayNames[schedule.weekday - 1]) · \(schedule.periods.map(String.init).joined(separator: ",")) 节 · 第 \(schedule.weekPattern.map(String.init).joined(separator: ",")) 周").font(.caption).foregroundStyle(.secondary)
                            }
                            if let weeks = course.unscheduledWeeks { Text("未排时间 · 第 \(weeks.map(String.init).joined(separator: ",")) 周").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .alert("无法导入", isPresented: Binding(get: { issue != nil }, set: { if !$0 { issue = nil } })) {
                Button("好", role: .cancel) { issue = nil }
            } message: { Text(issue ?? "") }
            .navigationTitle("确认导入").navigationBarTitleDisplayMode(.inline)
            .onAppear { importName = preview.table.name; startDate = preview.table.startDate }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        do {
                            var confirmed = preview
                            confirmed.table.name = importName; confirmed.table.startDate = startDate
                            try store.importTable(confirmed, adoptTimes: adoptTimes); dismiss()
                        }
                        catch { issue = error.localizedDescription }
                    }
                }
            }
        }
    }
}

struct TimeSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TimeProfile.standard
    @State private var duration = 45
    @State private var gap = 10
    @State private var issue: String?
    private let sessions = ["上午", "下午", "晚上"]
    var body: some View {
        Form {
            Section("每日课节 · 共 \(draft.periods.count) 节") {
                HStack {
                    ForEach(0..<3, id: \.self) { group in
                        Menu {
                            ForEach(0...12, id: \.self) { count in
                                Button("\(count) 节") { countBinding(group).wrappedValue = count }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(sessions[group]) \(draft.counts[group])")
                                Image(systemName: "chevron.up.chevron.down").font(.caption2)
                            }.frame(maxWidth: .infinity)
                        }.accessibilityLabel("\(sessions[group]) \(draft.counts[group]) 节")
                    }
                }
                HStack {
                    Picker("时长", selection: Binding(get: { duration }, set: { value in
                        change { try draft.setDuration(value) }; duration = draft.periods.first.map { $0.end - $0.start } ?? 45
                    })) { ForEach(Array(Set(Array(stride(from: 10, through: 120, by: 5)) + [duration])).sorted(), id: \.self) { Text("\($0) 分").tag($0) } }
                    Divider().frame(height: 24)
                    Picker("课间", selection: Binding(get: { gap }, set: { value in
                        change { try draft.setDuration(duration, gap: value) }; gap = typicalGap
                    })) { ForEach(Array(Set(Array(stride(from: 0, through: 60, by: 5)) + [gap])).sorted(), id: \.self) { Text("\($0) 分").tag($0) } }
                }.pickerStyle(.menu)
            }
            Section("课节时间") {
                ForEach(draft.periods.indices, id: \.self) { index in
                    HStack(spacing: 4) {
                        VStack(spacing: 1) {
                            Text("\(index + 1)").font(.subheadline.monospacedDigit())
                            if index == 0 || index == draft.counts[0] || index == draft.counts[0] + draft.counts[1] {
                                Text(sessionName(index)).font(.caption2)
                            }
                        }.foregroundStyle(.secondary).frame(width: 36)
                        DatePicker("第 \(index + 1) 节开始", selection: timeBinding(index, end: false), displayedComponents: .hourAndMinute).labelsHidden().frame(maxWidth: .infinity)
                        Text("–").foregroundStyle(.tertiary)
                        DatePicker("第 \(index + 1) 节结束", selection: timeBinding(index, end: true), displayedComponents: .hourAndMinute).labelsHidden().frame(maxWidth: .infinity)
                    }.frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                }
            }
            Section { Text("修改时间会联动后续课节；增减节数会重新编号。保存后对所有课表生效。")
                .font(.footnote).foregroundStyle(.secondary) }
        }
        .environment(\.defaultMinListRowHeight, 44).listSectionSpacing(.compact)
        .navigationTitle("统一课节时间").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    do { try store.updateProfile(draft); dismiss() } catch { issue = error.localizedDescription }
                }
            }
        }.onAppear { draft = store.profile; draft.sessionCounts = draft.counts; duration = draft.periods.first.map { $0.end - $0.start } ?? 45; gap = typicalGap }
        .alert("无法调整", isPresented: Binding(get: { issue != nil }, set: { if !$0 { issue = nil } })) {
            Button("好", role: .cancel) { issue = nil }
        } message: { Text(issue ?? "") }
    }
    private var typicalGap: Int {
        let boundaries = [draft.counts[0], draft.counts[0] + draft.counts[1]]
        guard let index = draft.periods.indices.dropFirst().first(where: { !boundaries.contains($0) }) else { return 10 }
        return max(0, draft.periods[index].start - draft.periods[index - 1].end)
    }
    private func sessionName(_ index: Int) -> String {
        index < draft.counts[0] ? "上午" : (index < draft.counts[0] + draft.counts[1] ? "下午" : "晚上")
    }
    private func change(_ operation: () throws -> Void) {
        do { try operation() } catch { issue = error.localizedDescription }
    }
    private func countBinding(_ group: Int) -> Binding<Int> {
        Binding(get: { draft.counts[group] }, set: { value in
            var counts = draft.counts; counts[group] = value
            change { try draft.resizeSessions(counts, duration: duration, gap: gap) }
        })
    }
    private func timeBinding(_ index: Int, end: Bool) -> Binding<Date> {
        Binding {
            let minutes = end ? draft.periods[index].end : draft.periods[index].start
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())!
        } set: { value in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            change { if end { try draft.moveEnd(index, to: minutes) } else { try draft.moveStart(index, to: minutes) } }
        }
    }
}

struct SemesterSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Timetable()
    @State private var holiday = Date()
    var body: some View {
        Form {
            Section("学期") {
                TextField("课表名称", text: $draft.name)
                DatePicker("开学日期", selection: $draft.startDate, displayedComponents: .date)
                Stepper("共 \(draft.totalWeeks) 周", value: $draft.totalWeeks, in: 1...60)
                Toggle("周视图显示周末", isOn: $draft.showWeekend)
            }
            Section("停课日期") {
                DatePicker("选择日期", selection: $holiday, displayedComponents: .date)
                Button("添加停课日") {
                    if !draft.holidays.contains(where: { Calendar.current.isDate($0, inSameDayAs: holiday) }) {
                        draft.holidays.append(holiday); draft.holidays.sort()
                    }
                }
                ForEach(draft.holidays, id: \.self) { date in Text(date, format: .dateTime.year().month().day()) }
                    .onDelete { draft.holidays.remove(atOffsets: $0) }
            }
        }.navigationTitle("学期与课表").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { do { try store.updateTable(draft); dismiss() } catch { store.error = error.localizedDescription } }
                }
            }.onAppear { draft = store.table }
    }
}

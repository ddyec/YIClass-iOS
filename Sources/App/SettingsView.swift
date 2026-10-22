import SwiftUI
import UniformTypeIdentifiers
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
    @State private var importing = false
    @State private var aiImport = false
    @State private var exporting = false
    @State private var document = JSONDocument(data: Data())
    @State private var selection: ImportSelection?
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("显示模式", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
                Section {
                    NavigationLink("统一课节时间") { TimeSettingsView() }
                    NavigationLink("学期与课表设置") { SemesterSettingsView() }
                } footer: {
                    Text("所有课表共用课节时间。")
                }
                Section("导入与备份") {
                    Button("AI 识别课表", systemImage: "sparkles") { aiImport = true }
                    Button("导入 JSON 课表", systemImage: "square.and.arrow.down") { importing = true }
                    Button("导出当前课表", systemImage: "square.and.arrow.up") {
                        do {
                            document = JSONDocument(data: try TimetableTransfer.encode(table: store.table, profile: store.profile))
                            exporting = true
                        } catch { store.error = error.localizedDescription }
                    }
                    Text("支持 YIClass JSON 课表。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("小组件") {
                    Text(store.widgetSyncIssue ?? "桌面与锁屏小组件显示当前课表，保存后自动同步。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("智能助手") { NavigationLink("AI 模式与接口配置") { AISettingsView() } }
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
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 10_000_000 else { throw AppFailure("课表文件不能超过 10 MB。") }
                    selection = ImportSelection(preview: try TimetableTransfer.decode(Data(contentsOf: url)))
                } catch { store.error = error.localizedDescription }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "YIClass-课表") { result in
                if case .failure(let error) = result { store.error = error.localizedDescription }
            }
            .sheet(isPresented: $aiImport) { NavigationStack { AssistantView(importMode: true).toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { aiImport = false } } } } }
            .sheet(item: $selection) { ImportReviewView(preview: $0.preview) }
            .confirmationDialog("删除“\(store.table.name)”？", isPresented: $deleting, titleVisibility: .visible) {
                Button("删除课表", role: .destructive) { store.perform { try store.deleteTable(store.table.id) } }
            }
        }
    }
}

struct ImportReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let preview: ImportPreview
    @State private var adoptTimes = false
    @State private var issue: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("课表预览") {
                    LabeledContent("名称", value: preview.table.name)
                    LabeledContent("课程", value: "\(preview.table.courses.count) 门")
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
                Section("课程") {
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        do { try store.importTable(preview, adoptTimes: adoptTimes); dismiss() }
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
                ForEach(0..<3, id: \.self) { group in
                    Stepper("\(sessions[group])  \(draft.counts[group]) 节", value: countBinding(group), in: 0...12)
                }
                Stepper("每节 \(duration) 分钟", value: Binding(get: { duration }, set: { value in
                    change { try draft.setDuration(value) }; duration = draft.periods.first.map { $0.end - $0.start } ?? 45
                }), in: 10...120, step: 5)
                Stepper("课间 \(gap) 分钟", value: Binding(get: { gap }, set: { value in
                    change { try draft.setDuration(duration, gap: value) }; gap = typicalGap
                }), in: 0...60, step: 5)
            }
            ForEach(0..<3, id: \.self) { group in
                if draft.counts[group] > 0 {
                    Section(sessions[group]) {
                        ForEach(indices(group), id: \.self) { index in
                            HStack(spacing: 4) {
                                Text("\(index + 1)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                                DatePicker("第 \(index + 1) 节开始", selection: timeBinding(index, end: false), displayedComponents: .hourAndMinute).labelsHidden()
                                Text("–").foregroundStyle(.tertiary)
                                DatePicker("第 \(index + 1) 节结束", selection: timeBinding(index, end: true), displayedComponents: .hourAndMinute).labelsHidden()
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            Section { Text("修改时间会联动后续课节；增减节数会重新编号。保存后对所有课表生效。")
                .font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("统一课节时间").navigationBarTitleDisplayMode(.inline)
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
    private var typicalGap: Int { draft.periods.count > 1 ? max(0, draft.periods[1].start - draft.periods[0].end) : 10 }
    private func indices(_ group: Int) -> Range<Int> {
        let start = draft.counts.prefix(group).reduce(0, +)
        return start..<(start + draft.counts[group])
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

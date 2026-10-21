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
    @State private var exporting = false
    @State private var document = JSONDocument(data: Data())
    @State private var selection: ImportSelection?
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        BrandMark()
                        VStack(alignment: .leading, spacing: 5) {
                            Text("YIClass").font(.title2.bold())
                            Text("为每一周，留一点从容").font(.subheadline).foregroundStyle(.secondary)
                            Text("Swift · iOS 26+").font(.caption).foregroundStyle(.tertiary)
                        }
                    }.padding(.vertical, 8)
                }
                Section("外观") {
                    Picker("显示模式", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Text("默认跟随系统，夜间自动使用深色背景与适配后的课程卡片。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink("统一课节时间") { TimeSettingsView() }
                    NavigationLink("学期与课表设置") { SemesterSettingsView() }
                } footer: {
                    Text("所有课表共用课节时间。新建、切换、导入和 AI 方案均不会重置你的时间设置。学期开始日所在周按周一计为第 1 周。")
                }
                Section("迁移与备份") {
                    Button("导入 JSON 课表", systemImage: "square.and.arrow.down") { importing = true }
                    Button("导出当前课表", systemImage: "square.and.arrow.up") {
                        do {
                            document = JSONDocument(data: try TimetableTransfer.encode(table: store.table, profile: store.profile))
                            exporting = true
                        } catch { store.error = error.localizedDescription }
                    }
                    Text("支持旧版 Flutter 导出的 JSON。原 Isar 数据库不能直接读取；旧版文件缺少的自定义时间需要在这里补设一次。")
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
            }.navigationTitle("设置")
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
                    ForEach(preview.table.courses) { course in Text(course.name) }
                }
            }
            .navigationTitle("确认导入").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        do { try store.importTable(preview, adoptTimes: adoptTimes); dismiss() }
                        catch { store.error = error.localizedDescription }
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
    var body: some View {
        Form {
            Section {
                Text("这份时间配置对全部课表生效，也用于新建和导入。")
                    .font(.footnote).foregroundStyle(.secondary)
                Stepper("统一时长：\(duration) 分钟", value: $duration, in: 10...120, step: 5)
                Button("保留各节开始时间，统一时长") {
                    for index in draft.periods.indices { draft.periods[index].end = draft.periods[index].start + duration }
                }
            }
            ForEach(draft.periods.indices, id: \.self) { index in
                Section("第 \(index + 1) 节") {
                    DatePicker("开始", selection: timeBinding(index, end: false), displayedComponents: .hourAndMinute)
                    DatePicker("结束", selection: timeBinding(index, end: true), displayedComponents: .hourAndMinute)
                }
            }
            Section {
                Button("增加一节") {
                    let start = (draft.periods.last?.end ?? 470) + 10
                    draft.periods.append(PeriodTime(period: draft.periods.count + 1, start: start, end: start + 45))
                }.disabled(draft.periods.count >= 20 || (draft.periods.last?.end ?? 0) + 55 >= 1440)
                Button("移除最后一节", role: .destructive) { draft.periods.removeLast() }.disabled(draft.periods.count <= 1)
            } footer: { Text("保存时会检查时间重叠，以及全部课表的节次引用。若有课程使用被移除的节次，请先调整课程。") }
        }
        .navigationTitle("统一课节时间").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    do { try store.updateProfile(draft); dismiss() } catch { store.error = error.localizedDescription }
                }
            }
        }.onAppear { draft = store.profile }
    }
    private func timeBinding(_ index: Int, end: Bool) -> Binding<Date> {
        Binding {
            let minutes = end ? draft.periods[index].end : draft.periods[index].start
            return Calendar.current.date(bySettingHour: min(23, minutes / 60), minute: minutes % 60, second: 0, of: Date())!
        } set: { value in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if end { draft.periods[index].end = minutes } else { draft.periods[index].start = minutes }
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

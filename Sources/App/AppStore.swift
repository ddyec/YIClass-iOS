import Foundation
import Observation
import WidgetKit
import YIClassCore

@MainActor @Observable final class AppStore {
    private(set) var data = AppData.fresh()
    var error: String?
    private(set) var loadFailed = false
    private(set) var undoData: AppData?
    private(set) var agenda = DayAgendaDocument()
    private var undoAgenda: DayAgendaDocument?
    private var agendaLoadFailed = false
    private(set) var agendaIssue: String?
    var agendaURL: URL { file.deletingLastPathComponent().appendingPathComponent("day-agenda.json") }
    private var agendaBackup: URL { agendaURL.appendingPathExtension("backup") }
    private let file: URL
    private var historyFile: URL { file.appendingPathExtension("history.json") }
    private var historyDamaged = false
    private(set) var archive = AssistantArchive()
    private(set) var historyIssue: String?
    var conversations: [ConversationRecord] { archive.conversations }
    var revisions: [LibraryRevision] { archive.revisions }
    private var backup: URL { file.appendingPathExtension("backup") }
    var table: Timetable { data.timetables.first { $0.id == data.selectedID }! }
    var profile: TimeProfile { data.timeProfile }

    init(storageURL: URL? = nil) {
        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing-demo") {
            // Isolate UI fixtures from real user data; this branch is absent from Release builds.
            file = FileManager.default.temporaryDirectory.appending(path: "yi-ui-\(UUID())", directoryHint: .isDirectory).appending(path: "library.json")
            let entries: [(String, String, Int, [Int], UInt32)] = [
                ("高等数学", "教学楼 A301", 1, [1, 2], 0xFF637EEA),
                ("大学英语", "外语楼 202", 2, [3, 4], 0xFF298F84),
                ("程序设计", "实验楼 B102", 3, [1, 2, 3], 0xFFB77938),
                ("线性代数", "教学楼 A206", 4, [5, 6], 0xFFAE65A3),
                ("体育", "田径场", 5, [7, 8], 0xFFD36D71),
                ("大学物理", "理学楼 108", 1, [5, 6], 0xFF658AAB),
                ("自习", "图书馆", 3, [7, 8], 0xFF298F84)
            ]
            let today = ScheduleEngine.monday(of: Date())
            let semesterStart = CommandLine.arguments.contains("--ui-testing-pdf") ? Calendar.current.date(byAdding: .day, value: -49, to: today)! : today
            let table = Timetable(name: "秋季学期", startDate: semesterStart, showWeekend: false,
                courses: entries.map { name, location, day, periods, color in
                    Course(name: name, location: location, color: color,
                        schedules: [CourseSchedule(weekday: day, periods: periods, weekPattern: Array(1...20))])
                })
            data = AppData(timetables: [table], selectedID: table.id)
            if CommandLine.arguments.contains("--ui-testing-todos") {
                let now = Date()
                agenda = DayAgendaDocument(todos: [
                    TodoItem(title: "完成实验报告", notes: "整理数据并提交课程平台", deadline: now.addingTimeInterval(3600), importance: .high, createdAt: now.addingTimeInterval(-86400)),
                    TodoItem(title: "准备英语展示", deadline: now.addingTimeInterval(86400), createdAt: now.addingTimeInterval(-86400)),
                    TodoItem(title: "已完成的测试事项", createdAt: now.addingTimeInterval(-86400), completedAt: now)
                ])
                data.todos = agenda.todos
            }
            return
        }
        #endif
        file = storageURL ?? URL.applicationSupportDirectory.appending(path: "YIClass", directoryHint: .isDirectory)
            .appending(path: "library.json")
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let loaded = try JSONCoding.decoder().decode(AppData.self, from: Data(contentsOf: file))
                try loaded.validate(); data = loaded
            }
            loadAgenda()
            syncWidgets()
        } catch {
            self.error = "本地数据读取失败，原文件已保留。\(error.localizedDescription)"; loadFailed = true
        }
        if FileManager.default.fileExists(atPath: historyFile.path) {
            do { archive = try JSONCoding.decoder().decode(AssistantArchive.self, from: Data(contentsOf: historyFile)) }
            catch { historyDamaged = true; historyIssue = "历史记录读取失败，原文件将保留备份。" }
        }
    }
    private func loadAgenda() {
        do {
            if FileManager.default.fileExists(atPath: agendaURL.path) {
                let loadedAgenda = try JSONCoding.decoder().decode(DayAgendaDocument.self, from: Data(contentsOf: agendaURL))
                try loadedAgenda.validate()
                agenda = loadedAgenda
            } else {
                let migrated = DayAgendaDocument(todos: data.todos)
                try migrated.validate()
                try FileManager.default.createDirectory(at: agendaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Write the independent document before clearing any legacy data.
                try JSONCoding.encoder().encode(migrated).write(to: agendaURL, options: [.atomic, .completeFileProtection])
                agenda = migrated
            }
            if !data.todos.isEmpty, FileManager.default.fileExists(atPath: file.path) {
                // The new document is durable; retain the original as a backup,
                // then remove the legacy task copy from the timetable file.
                try Data(contentsOf: file).write(to: backup, options: [.atomic, .completeFileProtection])
                var timetableOnly = data; timetableOnly.todos = []
                try JSONCoding.encoder().encode(timetableOnly).write(to: file, options: [.atomic, .completeFileProtection])
            }
            data.todos = agenda.todos
        } catch {
            agenda = DayAgendaDocument()
            agendaLoadFailed = true
            agendaIssue = "日程文件读取失败，原文件已保留。可恢复日程备份或导出文件。"
            data.todos = []
        }
    }
    func recoverAgendaBackup() throws {
        let restored = try JSONCoding.decoder().decode(DayAgendaDocument.self, from: Data(contentsOf: agendaBackup))
        try restored.validate()
        if FileManager.default.fileExists(atPath: agendaURL.path) {
            try FileManager.default.copyItem(at: agendaURL, to: agendaURL.appendingPathExtension("damaged-\(UUID())"))
        }
        try JSONCoding.encoder().encode(restored).write(to: agendaURL, options: [.atomic, .completeFileProtection])
        agenda = restored; data.todos = restored.todos; agendaLoadFailed = false; agendaIssue = nil
        undoData = nil; undoAgenda = nil; syncWidgets()
    }
    var damagedFile: URL { file }
    func recoverBackup() {
        do {
            let restored = try JSONCoding.decoder().decode(AppData.self, from: Data(contentsOf: backup))
            try restored.validate()
            let preserved = file.deletingLastPathComponent().appending(path: "library-damaged-\(UUID()).json")
            try FileManager.default.copyItem(at: file, to: preserved)
            try JSONCoding.encoder().encode(restored).write(to: file, options: [.atomic, .completeFileProtection])
            data = restored; loadFailed = false; error = nil; loadAgenda(); syncWidgets()
        } catch { self.error = "恢复失败：\(error.localizedDescription)" }
    }
    private func commit(_ next: AppData, undoable: Bool = false, reason: String = "修改课表", dayAgenda: DayAgendaDocument? = nil) throws {
        guard !loadFailed else { throw AppFailure("请先恢复本地数据。") }
        try next.validate()
        var nextAgenda = dayAgenda ?? agenda
        nextAgenda.todos = next.todos
        let ids = Set(next.todos.map(\.id))
        nextAgenda.placements.removeAll { !ids.contains($0.todoID) }
        try nextAgenda.validate()
        let agendaChanged = nextAgenda != agenda
        guard !agendaLoadFailed || !agendaChanged else { throw AppFailure("日程文件无法读取，请先恢复备份，避免覆盖原文件。") }
        var persisted = next; persisted.todos = []
        var previous = data; previous.todos = []
        let libraryChanged = persisted != previous
        // Every user action changes either timetable data or the independent task
        // document. Reject accidental multi-document writes rather than partially
        // applying a mixed AI operation.
        guard !libraryChanged || !agendaChanged else { throw AppFailure("请将课表修改与日程待办修改分开保存。") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if next.timetables != data.timetables || next.timeProfile != data.timeProfile {
            var history = archive
            history.revisions.insert(LibraryRevision(title: reason, data: data), at: 0)
            history.revisions = Array(history.revisions.prefix(30))
            try persistArchive(history)
        }
        if libraryChanged || !FileManager.default.fileExists(atPath: file.path) {
            if FileManager.default.fileExists(atPath: file.path) {
                try Data(contentsOf: file).write(to: backup, options: [.atomic, .completeFileProtection])
            }
            try JSONCoding.encoder().encode(persisted).write(to: file, options: [.atomic, .completeFileProtection])
        }
        if agendaChanged {
            nextAgenda.revision = agenda.revision + 1
            if FileManager.default.fileExists(atPath: agendaURL.path) {
                try Data(contentsOf: agendaURL).write(to: agendaBackup, options: [.atomic, .completeFileProtection])
            }
            try JSONCoding.encoder().encode(nextAgenda).write(to: agendaURL, options: [.atomic, .completeFileProtection])
        }
        undoData = undoable ? data : nil
        undoAgenda = undoable ? agenda : nil
        agenda = nextAgenda
        data = next
        syncWidgets()
    }
    private func persistArchive(_ history: AssistantArchive) throws {
        try FileManager.default.createDirectory(at: historyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if historyDamaged {
            let preserved = historyFile.appendingPathExtension("damaged-\(UUID())")
            try FileManager.default.copyItem(at: historyFile, to: preserved)
            historyDamaged = false
        }
        try JSONCoding.encoder().encode(history).write(to: historyFile, options: [.atomic, .completeFileProtection])
        archive = history; historyIssue = nil
    }
    func saveConversation(id: UUID, messages: [ChatMessage], modelHistory: [ChatMessage], importing: Bool, importTable: Timetable?) throws {
        func withoutImages(_ messages: [ChatMessage]) -> [ChatMessage] {
            messages.suffix(100).map { message in
                ChatMessage(role: message.role, content: message.content + (message.images.isEmpty ? "" : "\n[曾附原图，原图不存入历史，重新识图需再附图。]"))
            }
        }
        var history = archive
        history.conversations.removeAll { $0.id == id }
        let title = String((messages.first { $0.role == "user" }?.content ?? "对话").prefix(40))
        history.conversations.insert(ConversationRecord(id: id, title: title, date: Date(), messages: withoutImages(messages),
            modelHistory: withoutImages(modelHistory), importing: importing, importTable: importTable), at: 0)
        history.conversations = Array(history.conversations.prefix(20))
        try persistArchive(history)
    }
    func restoreRevision(_ id: UUID) throws {
        guard let revision = archive.revisions.first(where: { $0.id == id }) else { throw AppFailure("恢复记录不存在。") }
        var restored = revision.data
        restored.todos = data.todos
        try commit(restored, undoable: true, reason: "恢复历史记录")
    }
    func syncWidgets() {
        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing-demo") { return }
        #endif
        guard !loadFailed else { return }
        #if os(iOS)
        LessonReminderManager.shared.refresh(data: data)
        LastLessonActivityManager.shared.refresh(data: data, agenda: agenda)
        #endif
        do { var snapshot = data; snapshot.todoSyncIssue = agendaIssue; try SharedLibrary.write(snapshot); widgetSyncIssue = nil; widgetLastSync = Date(); WidgetCenter.shared.reloadAllTimelines() }
        catch { widgetSyncIssue = error.localizedDescription; widgetLastSync = nil }
    }
    private(set) var widgetLastSync: Date?
    private(set) var widgetSyncIssue: String?
    func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { self.error = error.localizedDescription }
    }
    func select(_ id: UUID) throws { var next = data; next.selectedID = id; try commit(next) }
    func create(name: String) throws {
        var next = data
        let created = table.emptyCopy(name: name)
        next.timetables.append(created); next.selectedID = created.id; try commit(next)
    }
    func deleteTable(_ id: UUID) throws {
        guard data.timetables.count > 1 else { throw AppFailure("请至少保留一份课表。") }
        var next = data; next.timetables.removeAll { $0.id == id }
        if next.selectedID == id { next.selectedID = next.timetables[0].id }
        try commit(next, undoable: true)
    }
    func updateTable(_ table: Timetable) throws {
        var next = data
        guard let index = next.timetables.firstIndex(where: { $0.id == table.id }) else { throw AppFailure("课表已删除。") }
        next.timetables[index] = table; try commit(next)
    }
    func updateProfile(_ profile: TimeProfile) throws {
        try commit(data.replacingTimeProfile(profile), undoable: true, reason: "调整课节时间")
    }
    func saveCourse(_ course: Course, tableID: UUID) throws {
        guard table.id == tableID else { throw AppFailure("当前课表已切换，请重新打开课程。") }
        var changed = table
        if let index = changed.courses.firstIndex(where: { $0.id == course.id }) { changed.courses[index] = course }
        else { changed.courses.append(course) }
        try updateTable(changed)
    }
    func deleteCourse(_ id: UUID) throws {
        var next = data
        let index = next.timetables.firstIndex { $0.id == table.id }!
        next.timetables[index].courses.removeAll { $0.id == id }; try commit(next, undoable: true)
    }
    func importTable(_ preview: ImportPreview, adoptTimes: Bool) throws {
        try commit(TimetableTransfer.applying(preview, to: data, adoptTimes: adoptTimes), undoable: true, reason: "导入课表")
    }
    func apply(_ plan: AssistantPlan, snapshot: PlanSnapshot) throws {
        try snapshot.check(current: table, profile: profile)
        let proposed = try plan.proposedTable(from: table, profile: profile)
        var next = data
        let index = next.timetables.firstIndex { $0.id == table.id }!
        next.timetables[index] = proposed
        try commit(next, undoable: true, reason: plan.title)
    }
    func saveTodo(_ todo: TodoItem, placement: TodoPlacement? = nil, updateSchedule: Bool = false) throws {
        var next = data
        if let index = next.todos.firstIndex(where: { $0.id == todo.id }) { next.todos[index] = todo }
        else { next.todos.append(todo) }
        var document = agenda
        if updateSchedule {
            document.placements.removeAll { $0.todoID == todo.id }
            if let placement {
                guard placement.todoID == todo.id else { throw AppFailure("待办安排标识不匹配。") }
                document.placements.append(placement)
            }
        }
        try commit(next, undoable: true, reason: "编辑待办", dayAgenda: document)
    }
    func deleteTodo(_ id: UUID) throws {
        var next = data; next.todos.removeAll { $0.id == id }
        try commit(next, undoable: true, reason: "删除待办")
    }
    func addTodos(_ proposals: [AssistantTodo]) throws -> String {
        let document = try AgendaOperations.applying(additions: proposals, todoChanges: [], agendaChanges: [], to: agenda, table: table, profile: profile)
        guard !proposals.isEmpty else { throw AppFailure("没有可导入的待办。") }
        var next = data; next.todos = document.todos
        try commit(next, undoable: true, reason: "AI 导入待办", dayAgenda: document)
        return "已保存 \(proposals.count) 条待办；其中 \(proposals.filter { $0.scheduledStart != nil }.count) 条已安排到日视图。"
    }
    func replaceAgenda(_ document: DayAgendaDocument, expected: DayAgendaDocument) throws {
        guard expected == agenda else { throw AppFailure("日程已变化，请重新选择导入文件。") }
        try document.validate()
        var next = data; next.todos = document.todos
        try commit(next, undoable: true, reason: "导入日程", dayAgenda: document)
    }
    func applyTaskReply(_ reply: AssistantReply, expected: DayAgendaDocument) throws -> String {
        guard expected == agenda else { throw AppFailure("待办或日程已变化，请重新查询后再应用。") }
        let document = try AgendaOperations.applying(additions: reply.todos, todoChanges: reply.todoChanges,
            agendaChanges: reply.agendaChanges, to: agenda, table: table, profile: profile)
        var next = data; next.todos = document.todos
        try commit(next, undoable: true, reason: "AI 更新待办与日程", dayAgenda: document)
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        var lines = ["已保存：新增 \(reply.todos.count) 条待办，更新 \(reply.todoChanges.count) 条待办，调整 \(reply.agendaChanges.count) 条时间安排。"]
        let oldIDs = Set(expected.todos.map(\.id))
        for item in document.todos where !oldIDs.contains(item.id) {
            lines.append("• 新增「\(item.title)」" + (item.deadline.map { "，截止 " + formatter.string(from: $0) } ?? "，未设截止时间"))
            if let placement = document.placement(for: item.id) {
                lines.append("  安排：" + formatter.string(from: placement.start) + "–" + formatter.string(from: placement.end))
            }
        }
        for change in reply.todoChanges {
            let title = document.todos.first { $0.id == change.todoID }?.title ?? expected.todos.first { $0.id == change.todoID }?.title ?? "待办"
            let action: String = switch change.action { case .update: "更新"; case .complete: "完成"; case .reopen: "重新打开"; case .delete: "删除" }
            lines.append("• \(action)「\(title)」")
        }
        for change in reply.agendaChanges {
            let title = document.todos.first { $0.id == change.todoID }?.title ?? "待办"
            if let placement = document.placement(for: change.todoID) {
                lines.append("• 安排「\(title)」：" + formatter.string(from: placement.start) + "–" + formatter.string(from: placement.end))
            } else { lines.append("• 取消「\(title)」的时间安排，保留待办") }
        }
        return lines.joined(separator: "\n")
    }
    func undo() throws {
        guard let previous = undoData else { return }
        try commit(previous, reason: "撤销更改", dayAgenda: undoAgenda)
    }
}

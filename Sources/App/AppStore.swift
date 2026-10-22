import Foundation
import Observation
import WidgetKit
import YIClassCore

@MainActor @Observable final class AppStore {
    private(set) var data = AppData.fresh()
    var error: String?
    private(set) var loadFailed = false
    private(set) var undoData: AppData?
    private let file: URL
    private var backup: URL { file.appendingPathExtension("backup") }
    var table: Timetable { data.timetables.first { $0.id == data.selectedID }! }
    var profile: TimeProfile { data.timeProfile }

    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing-demo") {
            // Isolate UI fixtures from real user data; this branch is absent from Release builds.
            file = FileManager.default.temporaryDirectory.appending(path: "yi-ui-\(UUID()).json")
            let entries: [(String, String, Int, [Int], UInt32)] = [
                ("高等数学", "教学楼 A301", 1, [1, 2], 0xFF637EEA),
                ("大学英语", "外语楼 202", 2, [3, 4], 0xFF298F84),
                ("程序设计", "实验楼 B102", 3, [1, 2, 3], 0xFFB77938),
                ("线性代数", "教学楼 A206", 4, [5, 6], 0xFFAE65A3),
                ("体育", "田径场", 5, [7, 8], 0xFFD36D71),
                ("大学物理", "理学楼 108", 1, [5, 6], 0xFF658AAB),
                ("自习", "图书馆", 3, [7, 8], 0xFF298F84)
            ]
            let table = Timetable(name: "秋季学期", startDate: ScheduleEngine.monday(of: Date()), showWeekend: false,
                courses: entries.map { name, location, day, periods, color in
                    Course(name: name, location: location, color: color,
                        schedules: [CourseSchedule(weekday: day, periods: periods, weekPattern: Array(1...20))])
                })
            data = AppData(timetables: [table], selectedID: table.id)
            return
        }
        #endif
        file = URL.applicationSupportDirectory.appending(path: "YIClass", directoryHint: .isDirectory)
            .appending(path: "library.json")
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let loaded = try JSONCoding.decoder().decode(AppData.self, from: Data(contentsOf: file))
                try loaded.validate(); data = loaded
            }
            syncWidgets()
        } catch {
            self.error = "本地数据读取失败，原文件已保留。\(error.localizedDescription)"; loadFailed = true
        }
    }
    var damagedFile: URL { file }
    func recoverBackup() {
        do {
            let restored = try JSONCoding.decoder().decode(AppData.self, from: Data(contentsOf: backup))
            try restored.validate()
            let preserved = file.deletingLastPathComponent().appending(path: "library-damaged-\(UUID()).json")
            try FileManager.default.copyItem(at: file, to: preserved)
            try JSONCoding.encoder().encode(restored).write(to: file, options: [.atomic, .completeFileProtection])
            data = restored; loadFailed = false; error = nil; syncWidgets()
        } catch { self.error = "恢复失败：\(error.localizedDescription)" }
    }
    private func commit(_ next: AppData, undoable: Bool = false) throws {
        guard !loadFailed else { throw AppFailure("请先恢复本地数据。") }
        try next.validate()
        let encoded = try JSONCoding.encoder().encode(next)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) {
            try Data(contentsOf: file).write(to: backup, options: [.atomic, .completeFileProtection])
        }
        try encoded.write(to: file, options: [.atomic, .completeFileProtection])
        undoData = undoable ? data : nil
        data = next
        syncWidgets()
    }
    private func syncWidgets() {
        do { try SharedLibrary.write(data); WidgetCenter.shared.reloadAllTimelines() }
        catch { widgetSyncIssue = error.localizedDescription }
    }
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
        var next = data; next.timeProfile = profile; try commit(next, undoable: true)
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
        try commit(TimetableTransfer.applying(preview, to: data, adoptTimes: adoptTimes), undoable: true)
    }
    func apply(_ plan: AssistantPlan, snapshot: PlanSnapshot) throws {
        try snapshot.check(current: table, profile: profile)
        let proposed = try plan.proposedTable(from: table, profile: profile)
        var next = data
        let index = next.timetables.firstIndex { $0.id == table.id }!
        next.timetables[index] = proposed
        try commit(next, undoable: true)
    }
    func undo() throws {
        guard let previous = undoData else { return }
        try commit(previous)
    }
}

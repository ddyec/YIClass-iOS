import Foundation
import YIClassCore
import UniformTypeIdentifiers

@main struct StoreCheck {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yi-store-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pdfBytes = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/timetable-grid.pdf"))
        let providerCopy = directory.appendingPathComponent("provider-document.bin")
        try pdfBytes.write(to: providerCopy)
        let imported = try await DocumentFileReader.read(providerCopy, maximumBytes: 20_000_000)
        precondition(imported.data == pdfBytes && imported.type == .pdf)
        do { _ = try await DocumentFileReader.read(providerCopy, maximumBytes: 10); fatalError("Oversize file accepted") }
        catch is AppFailure { }
        let empty = directory.appendingPathComponent("empty.pdf")
        try Data().write(to: empty)
        do { _ = try await DocumentFileReader.read(empty, maximumBytes: 20_000_000); fatalError("Empty file accepted") }
        catch is AppFailure { }
        print("PASS: coordinated document read preserves PDF bytes, detects PDF with generic extension, rejects empty and oversized files")
        let file = directory.appendingPathComponent("library.json")
        let store = AppStore(storageURL: file)
        let english = Course(name: "英语", location: "", teacher: "", schedules: [CourseSchedule(weekday: 4, periods: [1,2], weekPattern: [7,8,9])])
        try store.saveCourse(english, tableID: store.table.id)
        var profile = store.profile; try profile.moveStart(0, to: 510)
        try store.updateProfile(profile)
        let snapshot = PlanSnapshot(table: store.table, profile: store.profile)
        let response: [String: Any] = ["message": "已取消今天这次英语课", "applyDirectly": true, "questions": [],
            "plans": [["title": "取消今天", "explanation": "保留其他周", "courses": [["id": english.id.uuidString,
                "name": "英语", "location": "", "teacher": "", "schedules": [["weekday": 4, "periods": [1,2], "weekPattern": [7,9]]]]]]]]
        let json = try JSONSerialization.data(withJSONObject: response)
        let reply = try AssistantReply.parse(String(decoding: json, as: UTF8.self), table: store.table, profile: store.profile)
        precondition(reply.applyDirectly == true)
        try store.apply(reply.plans[0], snapshot: snapshot)
        let saved = try JSONCoding.decoder().decode(AppData.self, from: Data(contentsOf: file))
        let course = saved.timetables.first { $0.id == saved.selectedID }!.courses[0]
        precondition(course.id == english.id && course.location.isEmpty && course.schedules[0].weekPattern == [7,9])
        precondition(saved.timeProfile == profile)
        let reopened = AppStore(storageURL: file)
        precondition(!reopened.loadFailed && reopened.data == saved)
        try store.undo()
        let undone = try JSONCoding.decoder().decode(AppData.self, from: Data(contentsOf: file))
        precondition(undone.timetables[0].courses[0].schedules[0].weekPattern == [7,8,9])
        precondition(undone.timeProfile == profile)
        let currentBytes = try Data(contentsOf: file)
        do { try store.apply(reply.plans[0], snapshot: PlanSnapshot(table: Timetable(), profile: .standard)); fatalError("Stale plan was accepted") }
        catch is AppFailure { }
        let afterRejectedEdit = try Data(contentsOf: file)
        precondition(afterRejectedEdit == currentBytes)
        print("PASS: actual AppStore direct AI edit → atomic library.json save → reopen → undo → stale edit rejected without file mutation; empty location and global time preserved")
    }
}

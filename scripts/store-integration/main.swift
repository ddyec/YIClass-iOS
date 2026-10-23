import Foundation
import YIClassCore
import UniformTypeIdentifiers

@main struct StoreCheck {
    @MainActor static func main() async throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jP1sAAAAASUVORK5CYII=")!
        let attachment = try await ImageAttachment.read(png)
        precondition(attachment.data == png && attachment.mimeType == "image/png")
        precondition(ImageAttachment.plainText("[x=0.1 y=0.2 w=0.3 h=0.4] 关于调课的通知") == "关于调课的通知")
        print("PASS: original PNG is preserved byte-for-byte and OCR coordinates stay out of display text")
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
        let todo = TodoItem(title: "待办持久化", importance: .high, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try store.saveTodo(todo)
        precondition(AppStore(storageURL: file).data.todos == [todo])
        var completed = todo; completed.completedAt = Date(timeIntervalSince1970: 1_700_001_000)
        try store.saveTodo(completed)
        precondition(AppStore(storageURL: file).data.todos.first?.completedAt != nil)
        try store.deleteTodo(todo.id)
        precondition(store.data.todos.isEmpty)
        try store.undo()
        precondition(AppStore(storageURL: file).data.todos == [completed])
        let proposals = try JSONDecoder().decode([AssistantTodo].self, from: Data(#"[{"title":"AI 报告","deadline":"2026-10-23T23:59:00+08:00"}]"#.utf8))
        _ = try store.addTodos(proposals)
        precondition(AppStore(storageURL: file).data.todos.count == 2)
        try store.undo()
        precondition(store.data.todos == [completed])
        print("PASS: manual and AI todos persist across restart, completion, deletion and undo")
        let arranged = TodoPlacement(todoID: completed.id, start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_003_600))
        try store.saveTodo(completed, placement: arranged, updateSchedule: true)
        let reopenedAgenda = AppStore(storageURL: file)
        precondition(reopenedAgenda.agenda.placement(for: completed.id) == arranged)
        precondition(reopenedAgenda.data.todos == [completed])
        let independent = try JSONCoding.decoder().decode(DayAgendaDocument.self, from: Data(contentsOf: store.agendaURL))
        precondition(independent.todos == [completed] && independent.placements == [arranged])
        try store.deleteTodo(completed.id)
        precondition(store.agenda.placements.isEmpty)
        try store.undo()
        precondition(store.agenda.placement(for: completed.id) == arranged)
        let beforeStale = try Data(contentsOf: store.agendaURL)
        let staleReply = try AssistantReply.parse("{\"message\":\"更新\",\"todoChanges\":[{\"todoID\":\"\(completed.id)\",\"action\":\"complete\"}]}", table: store.table, profile: store.profile)
        do { _ = try store.applyTaskReply(staleReply, expected: DayAgendaDocument()); fatalError("Stale agenda accepted") }
        catch is AppFailure { }
        let afterStale = try Data(contentsOf: store.agendaURL)
        precondition(afterStale == beforeStale)
        print("PASS: independent agenda persists task placements; delete/undo keeps referential integrity; stale AI snapshot is rejected")

        let legacyDirectory = directory.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let legacyFile = legacyDirectory.appendingPathComponent("library.json")
        var legacyData = AppData.fresh(); legacyData.todos = [todo]
        try JSONCoding.encoder().encode(legacyData).write(to: legacyFile)
        let migratedStore = AppStore(storageURL: legacyFile)
        precondition(migratedStore.agenda.todos == [todo])
        let stripped = try JSONCoding.decoder().decode(AppData.self, from: Data(contentsOf: legacyFile))
        precondition(stripped.todos.isEmpty)
        try migratedStore.saveTodo(completed)
        let brokenAgenda = Data("broken agenda".utf8)
        try brokenAgenda.write(to: migratedStore.agendaURL)
        let brokenStore = AppStore(storageURL: legacyFile)
        precondition(brokenStore.agendaIssue != nil && !brokenStore.loadFailed)
        do { try brokenStore.saveTodo(todo); fatalError("Corrupt agenda overwritten") }
        catch is AppFailure { }
        let preservedAgenda = try Data(contentsOf: migratedStore.agendaURL)
        precondition(preservedAgenda == brokenAgenda)
        try brokenStore.recoverAgendaBackup()
        precondition(brokenStore.agenda.todos == [todo])
        let structurallyInvalid = DayAgendaDocument(todos: [todo, todo])
        try JSONCoding.encoder().encode(structurallyInvalid).write(to: brokenStore.agendaURL)
        let invalidStore = AppStore(storageURL: legacyFile)
        precondition(invalidStore.agendaIssue != nil && invalidStore.agenda.todos.isEmpty)
        precondition(DayAgendaEngine.items(data: invalidStore.data, agenda: invalidStore.agenda, on: Date()).isEmpty)
        try invalidStore.recoverAgendaBackup()
        print("PASS: legacy todos migrate without ID loss, timetable copy is cleared, corrupt agenda remains untouched, backup restores independently")
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
        var saved = try JSONCoding.decoder().decode(AppData.self, from: Data(contentsOf: file))
        precondition(saved.todos.isEmpty) // Tasks are canonical in day-agenda.json.
        saved.todos = store.data.todos
        let course = saved.timetables.first { $0.id == saved.selectedID }!.courses[0]
        precondition(course.id == english.id && course.location.isEmpty && course.schedules[0].weekPattern == [7,9])
        precondition(saved.timeProfile == profile)
        let reopened = AppStore(storageURL: file)
        precondition(!reopened.loadFailed && reopened.data == saved)
        try store.undo()
        var undone = try JSONCoding.decoder().decode(AppData.self, from: Data(contentsOf: file))
        undone.todos = store.data.todos
        precondition(undone.timetables[0].courses[0].schedules[0].weekPattern == [7,8,9])
        precondition(undone.timeProfile == profile)
        let currentBytes = try Data(contentsOf: file)
        do { try store.apply(reply.plans[0], snapshot: PlanSnapshot(table: Timetable(), profile: .standard)); fatalError("Stale plan was accepted") }
        catch is AppFailure { }
        let afterRejectedEdit = try Data(contentsOf: file)
        precondition(afterRejectedEdit == currentBytes)
        let profileXML = try PropertyListSerialization.data(fromPropertyList: ["Entitlements": ["com.apple.security.application-groups": ["group.signer.shared", "group.signer.extra", "group.*", "group.signer.shared"]]], format: .xml, options: 0)
        let signedProfile = Data([0x30, 0x82, 0x00, 0x00]) + profileXML + Data([0x00, 0xFF])
        let discovered = SharedGroup.candidates(configured: "group.com.ddyec.YIClassNative", profile: signedProfile)
        precondition(discovered == ["group.com.ddyec.YIClassNative", "group.signer.extra", "group.signer.shared"])
        precondition(SharedGroup.candidates(configured: "$(UNEXPANDED)", profile: Data("bad profile".utf8)) == [SharedGroup.defaultIdentifier])
        precondition(SharedGroup.candidates(configured: nil, profile: nil) == [SharedGroup.defaultIdentifier])
        print("PASS: legacy provisioned App Group discovery extracts signer-replaced groups, deduplicates candidates, rejects wildcards, tolerates missing/malformed profiles")
        let sharedFile = directory.appendingPathComponent("widget-library.json")
        if case .success = SharedLibrary.readResult(from: nil) { fatalError("Missing group was accepted") }
        if case .success = SharedLibrary.readResult(from: sharedFile) { fatalError("Missing snapshot was accepted") }
        try Data("broken".utf8).write(to: sharedFile)
        if case .success = SharedLibrary.readResult(from: sharedFile) { fatalError("Corrupt snapshot was accepted") }
        try SharedLibrary.write(store.data, to: sharedFile)
        let widgetData = try SharedLibrary.readResult(from: sharedFile).get()
        precondition(widgetData == undone) // Compare persisted data; JSON date precision is lower than in-memory Date.
        precondition(widgetData.selectedID == store.table.id && widgetData.timeProfile == profile)
        print("PASS: production widget snapshot write/read preserves selected timetable and global times; missing permission, missing file and corrupt snapshot report failure")
        let conversationID = UUID()
        try store.saveConversation(id: conversationID,
            messages: [ChatMessage(role: "user", content: "按通知调课", images: [attachment])],
            modelHistory: [ChatMessage(role: "user", content: "原排9月28日调整至10月18日", images: [attachment])], importing: false, importTable: nil)
        let reopenedHistory = AppStore(storageURL: file)
        precondition(reopenedHistory.conversations.first?.id == conversationID)
        precondition(reopenedHistory.conversations.first?.messages.first?.images.isEmpty == true)
        precondition(reopenedHistory.conversations.first?.modelHistory.first?.content.contains("10月18日") == true)
        let beforeFirstEdit = reopenedHistory.revisions.last!
        try reopenedHistory.restoreRevision(beforeFirstEdit.id)
        let restoredHistory = AppStore(storageURL: file)
        precondition(restoredHistory.table.courses.isEmpty)
        precondition(restoredHistory.revisions.first?.title == "恢复历史记录")
        try restoredHistory.restoreRevision(restoredHistory.revisions.first!.id)
        let recoveredHistory = AppStore(storageURL: file)
        precondition(recoveredHistory.table.courses.first?.name == "英语" && recoveredHistory.profile == profile)
        precondition(recoveredHistory.conversations.first?.id == conversationID)
        print("PASS: conversations persist across reopen without original image storage; historical restore preserves current state and can be reversed after restart")
        print("PASS: actual AppStore direct AI edit → atomic library.json save → reopen → undo → stale edit rejected without file mutation; empty location and global time preserved")
    }
}

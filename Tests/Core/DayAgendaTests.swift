import Foundation
import Testing
@testable import YIClassCore

private func agendaDate(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private var agendaCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; return calendar
}
private func task(_ title: String = "实验报告") -> TodoItem {
    TodoItem(title: title, deadline: agendaDate("2026-10-23T23:59:00Z"), createdAt: agendaDate("2026-10-20T08:00:00Z"))
}

@Test func dayAgendaRoundTripPreservesIDsAndRejectsBrokenReferences() throws {
    let todo = task()
    var document = DayAgendaDocument(todos: [todo], placements: [TodoPlacement(todoID: todo.id, start: agendaDate("2026-10-23T14:00:00Z"), end: agendaDate("2026-10-23T15:00:00Z"))])
    try document.validate()
    #expect(try JSONCoding.decoder().decode(DayAgendaDocument.self, from: JSONCoding.encoder().encode(document)) == document)
    document.placements[0].todoID = UUID()
    #expect(throws: AppFailure.self) { try document.validate() }
    document.placements = [TodoPlacement(todoID: todo.id, start: Date(), end: .distantPast)]
    #expect(throws: AppFailure.self) { try document.validate() }
}

@Test func deadlineDoesNotInventWorkTimeAndCrossMidnightClipsToBothDays() throws {
    let todo = task()
    let data = AppData.fresh()
    var document = DayAgendaDocument(todos: [todo])
    let day = agendaDate("2026-10-23T00:00:00Z")
    #expect(DayAgendaEngine.items(data: data, agenda: document, on: day, calendar: agendaCalendar).isEmpty)
    #expect(DayAgendaEngine.deadlines(document.todos, on: day, calendar: agendaCalendar).map(\.id) == [todo.id])
    document.placements = [TodoPlacement(todoID: todo.id, start: agendaDate("2026-10-23T23:30:00Z"), end: agendaDate("2026-10-24T00:30:00Z"))]
    let first = try #require(DayAgendaEngine.items(data: data, agenda: document, on: day, calendar: agendaCalendar).first)
    let second = try #require(DayAgendaEngine.items(data: data, agenda: document, on: agendaDate("2026-10-24T00:00:00Z"), calendar: agendaCalendar).first)
    #expect(first.startMinute == 1410 && first.endMinute == 1440)
    #expect(second.startMinute == 0 && second.endMinute == 30)
}

@Test func timelineLanesKeepConflictsVisibleAndReleaseWidthAfterCluster() throws {
    let a = task("A"), b = task("B"), c = task("C")
    let day = agendaDate("2026-10-23T00:00:00Z")
    let document = DayAgendaDocument(todos: [a,b,c], placements: [
        TodoPlacement(todoID: a.id, start: day.addingTimeInterval(9*3600), end: day.addingTimeInterval(10*3600)),
        TodoPlacement(todoID: b.id, start: day.addingTimeInterval(9*3600+1800), end: day.addingTimeInterval(11*3600)),
        TodoPlacement(todoID: c.id, start: day.addingTimeInterval(12*3600), end: day.addingTimeInterval(13*3600))])
    let lanes = DayAgendaEngine.lanes(DayAgendaEngine.items(data: .fresh(), agenda: document, on: day, calendar: agendaCalendar))
    #expect(lanes.filter { $0.item.sourceID == a.id || $0.item.sourceID == b.id }.allSatisfy { $0.columns == 2 })
    #expect(lanes.first { $0.item.sourceID == c.id }?.columns == 1)
}

@Test func agendaAIChangesAreValidatedAsOneBatchAndRemovalKeepsTask() throws {
    let todo = task()
    let original = DayAgendaDocument(todos: [todo])
    let changes = try JSONDecoder().decode([AssistantAgendaChange].self, from: Data("[{\"todoID\":\"\(todo.id)\",\"action\":\"schedule\",\"start\":\"2026-10-23T14:00:00Z\",\"end\":\"2026-10-23T15:00:00Z\"}]".utf8))
    let scheduled = try AgendaOperations.applying(additions: [], todoChanges: [], agendaChanges: changes, to: original, table: Timetable(), profile: .standard)
    #expect(scheduled.todos == [todo] && scheduled.placements.count == 1)
    let removal = try JSONDecoder().decode([AssistantAgendaChange].self, from: Data("[{\"todoID\":\"\(todo.id)\",\"action\":\"remove\"}]".utf8))
    let removed = try AgendaOperations.applying(additions: [], todoChanges: [], agendaChanges: removal, to: scheduled, table: Timetable(), profile: .standard)
    #expect(removed.todos == [todo] && removed.placements.isEmpty)
    let invalid = try JSONDecoder().decode([AssistantTodo].self, from: Data(#"[{"title":"有效新增"},{"title":""}]"#.utf8))
    #expect(throws: AppFailure.self) { try AgendaOperations.applying(additions: invalid, todoChanges: [], agendaChanges: [], to: original, table: Timetable(), profile: .standard) }
    #expect(original.todos == [todo])
}

@Test func todoAndAgendaToolsReturnStableIDsAndRealPlacements() throws {
    let todo = task()
    let table = Timetable()
    let document = DayAgendaDocument(todos: [todo])
    let call = ChatToolCall(id: "tasks", type: "function", function: .init(name: "get_todos", arguments: #"{"todoIDs":[]}"#))
    let result = try AssistantTools.execute(call, table: table, profile: .standard, agenda: document)
    #expect(result.contains(todo.id.uuidString) && result.contains(todo.title))
    let dates = TodoWidgetSchedule.dates(todos: [todo], now: agendaDate("2026-10-23T10:00:00Z"), calendar: agendaCalendar)
    #expect(dates.contains(agendaDate("2026-10-23T23:59:01Z")))
    #expect(dates.last == agendaDate("2026-10-24T00:00:00Z"))
}

@Test func newAIWorkTimeDoesNotOverwriteDeadline() throws {
    let additions = try JSONDecoder().decode([AssistantTodo].self, from: Data(#"[{"title":"写报告","deadline":"2026-10-24T23:59:00Z","scheduledStart":"2026-10-23T14:00:00Z","scheduledEnd":"2026-10-23T15:00:00Z"}]"#.utf8))
    let document = try AgendaOperations.applying(additions: additions, todoChanges: [], agendaChanges: [], to: DayAgendaDocument(), table: Timetable(), profile: .standard)
    #expect(document.todos.first?.deadline == agendaDate("2026-10-24T23:59:00Z"))
    #expect(document.placements.first?.start == agendaDate("2026-10-23T14:00:00Z"))
}

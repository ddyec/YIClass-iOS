import Foundation
import Testing
@testable import YIClassCore

private func todoDate(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
private var todoCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

@Test func oldLibraryLoadsWithoutTodosAndNewLibraryRoundTrips() throws {
    var library = AppData.fresh()
    library.timetables[0].startDate = todoDate("2026-08-31T00:00:00Z")
    let old = try JSONCoding.encoder().encode(library)
    var object = try #require(JSONSerialization.jsonObject(with: old) as? [String: Any])
    object.removeValue(forKey: "todos")
    let migrated = try JSONCoding.decoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(migrated.todos.isEmpty)
    #expect(migrated.timetables == library.timetables)
    library.todos = [TodoItem(title: "报告", deadline: todoDate("2026-10-23T23:59:00+08:00"), importance: .high, createdAt: todoDate("2026-10-22T09:00:00Z"))]
    let restored = try JSONCoding.decoder().decode(AppData.self, from: JSONCoding.encoder().encode(library))
    #expect(restored == library)
    try restored.validate()
}

@Test func dailyRankingChangesWithDateAndExcludesCompletedAndFutureItems() {
    let now = todoDate("2026-10-22T09:00:00Z")
    let created = todoDate("2026-10-20T09:00:00Z")
    let due = TodoItem(title: "今天截止", deadline: todoDate("2026-10-22T23:59:00Z"), importance: .low, createdAt: created)
    let later = TodoItem(title: "重要报告", deadline: todoDate("2026-10-25T23:59:00Z"), importance: .high, createdAt: created)
    let undated = TodoItem(title: "无期限", importance: .high, createdAt: created)
    let done = TodoItem(title: "完成", createdAt: created, completedAt: now)
    let future = TodoItem(title: "未来创建", createdAt: now.addingTimeInterval(86400))
    #expect(TodoItem.ranked([later, undated, done, due, future], on: now, calendar: todoCalendar).map(\.id) == [due.id, later.id, undated.id])
    #expect(later.score(on: now.addingTimeInterval(2 * 86400), calendar: todoCalendar) > later.score(on: now, calendar: todoCalendar))
    #expect(due.urgency(on: now.addingTimeInterval(86400), calendar: todoCalendar) == "已逾期")
    #expect(due.importance == .low)
}

@Test func rankingUsesCalendarDaysAcrossDaylightSavingTransition() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let start = todoDate("2026-03-08T00:30:00-08:00")
    let item = TodoItem(title: "明天交", deadline: todoDate("2026-03-09T00:15:00-07:00"), createdAt: start)
    #expect(item.score(on: start, calendar: calendar) == 80)
}

@Test func assistantAcceptsNaturalLanguageExtractionPayloadAndOptionalFields() throws {
    let library = AppData.fresh()
    let text = #"{"message":"已整理","applyDirectly":true,"todos":[{"title":"交实验报告","deadline":"2026-10-23T23:59:00+08:00","importance":"high"},{"title":"整理资料","deadline":null}]}"#
    let reply = try AssistantReply.parse(text, table: library.timetables[0], profile: library.timeProfile)
    let item = try reply.todos[0].materialize()
    #expect(item.deadline == todoDate("2026-10-23T15:59:00Z"))
    #expect(item.source == .assistant)
    #expect(item.importance == .high)
    #expect(try reply.todos[1].materialize().deadline == nil)
    #expect(try reply.todos[1].materialize().importance == .normal)
}

@Test func malformedAITodosAreRejectedBeforeAnyWrite() throws {
    let library = AppData.fresh()
    for fields in [#"{"title":"","deadline":null}"#, #"{"title":"报告","deadline":"下周五"}"#, #"{"title":"报告","importance":"urgent"}"#] {
        let payload = "{\"message\":\"添加\",\"applyDirectly\":true,\"todos\":[" + fields + "]}"
        #expect(throws: (any Error).self) { try AssistantReply.parse(payload, table: library.timetables[0], profile: library.timeProfile) }
    }
    let ambiguous = #"{"message":"哪一天？","applyDirectly":true,"questions":[{"title":"日期","options":["周五","周六"]}],"todos":[{"title":"报告"}]}"#
    #expect(throws: (any Error).self) { try AssistantReply.parse(ambiguous, table: library.timetables[0], profile: library.timeProfile) }
}

@Test func duplicateAndBlankStoredTodosFailValidation() {
    var library = AppData.fresh()
    let item = TodoItem(title: "报告")
    library.todos = [item, item]
    #expect(throws: (any Error).self) { try library.validate() }
    library.todos = [TodoItem(title: " \n ")]
    #expect(throws: (any Error).self) { try library.validate() }
}

@Test func taskCardUrgencyTracksExactDeadlineCompletionAndCalendarDays() {
    let now = todoDate("2026-10-22T09:00:00Z")
    var item = TodoItem(title: "报告", deadline: todoDate("2026-10-22T08:59:00Z"))
    #expect(item.urgencyLevel(on: now, calendar: todoCalendar) == .overdue)
    item.deadline = todoDate("2026-10-22T23:59:00Z")
    #expect(item.urgencyLevel(on: now, calendar: todoCalendar) == .today)
    item.deadline = todoDate("2026-10-25T23:59:00Z")
    #expect(item.urgencyLevel(on: now, calendar: todoCalendar) == .soon)
    item.deadline = todoDate("2026-10-26T00:00:00Z")
    #expect(item.urgencyLevel(on: now, calendar: todoCalendar) == .upcoming)
    item.deadline = nil
    #expect(item.urgencyLevel(on: now, calendar: todoCalendar) == .unscheduled)
    item.completedAt = now
    #expect(item.urgencyLevel(on: now, calendar: todoCalendar) == .completed)
}

import Foundation
import Testing
@testable import YIClassCore

private func upcomingDate(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
private var upcomingCalendar: Calendar {
    var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
}

@Test func nextClassSearchesWholeSemesterSkipsHolidaysAndAlreadyStartedClasses() throws {
    let now = upcomingDate("2026-10-22T08:15:00Z")
    let lab = Course(name: "物理实验", schedules: [CourseSchedule(weekday: 4, periods: [1,2], weekPattern: [8,10,12])])
    var table = Timetable(startDate: upcomingDate("2026-08-31T00:00:00Z"), courses: [lab])
    table.holidays = [upcomingDate("2026-11-05T00:00:00Z")]
    let lessons = AssistantUpcomingCourses.nextLessons(table: table, profile: .standard, now: now, calendar: upcomingCalendar)
    #expect(lessons.count == 1)
    #expect(lessons.first?.start == upcomingDate("2026-11-19T08:00:00Z"))
    #expect(lessons.first?.end == upcomingDate("2026-11-19T09:40:00Z"))
    // The first session has begun, and the next scheduled week is a holiday.
    #expect(AssistantTools.needsLookup("下次实验课要交报告"))
    #expect(AssistantTools.needsLookup("下节课前要完成"))
}

@Test func courseRelativeDeadlineUsesLocalNextClassInsteadOfModelDate() throws {
    let now = upcomingDate("2026-10-22T06:00:00Z")
    let lab = Course(name: "化学实验", schedules: [CourseSchedule(weekday: 4, periods: [1,2], weekPattern: [8,9])])
    let table = Timetable(startDate: upcomingDate("2026-08-31T00:00:00Z"), courses: [lab])
    let payload = "{\"title\":\"交实验报告\",\"deadline\":\"2026-12-31T00:00:00Z\",\"nextCourseID\":\"\(lab.id)\"}"
    let proposal = try JSONDecoder().decode(AssistantTodo.self, from: Data(payload.utf8))
    let item = try proposal.materialize(now: now, table: table, profile: .standard, calendar: upcomingCalendar)
    #expect(item.deadline == upcomingDate("2026-10-22T08:00:00Z"))
    #expect(item.notes.contains("化学实验"))
    var changed = TimeProfile.standard; try changed.moveStart(0, to: 510)
    #expect(try proposal.materialize(now: now, table: table, profile: changed, calendar: upcomingCalendar).deadline == upcomingDate("2026-10-22T08:30:00Z"))
}

@Test func upcomingToolReturnsEveryCandidateAndUnscheduledHasNoInventedDate() throws {
    let now = upcomingDate("2026-10-22T06:00:00Z")
    let physics = Course(name: "物理实验", schedules: [CourseSchedule(weekday: 5, periods: [3,4], weekPattern: [8])])
    let chemistry = Course(name: "化学实验", schedules: [])
    let table = Timetable(startDate: upcomingDate("2026-08-31T00:00:00Z"), courses: [physics, chemistry])
    let args = try JSONEncoder().encode(["courseIDs": [physics.id.uuidString, chemistry.id.uuidString]])
    let data = try JSONSerialization.data(withJSONObject: ["id": "next", "type": "function", "function": ["name": "get_next_course_lessons", "arguments": String(decoding: args, as: UTF8.self)]])
    let call = try JSONDecoder().decode(ChatToolCall.self, from: data)
    let response = try AssistantTools.execute(call, table: table, profile: .standard, calendar: upcomingCalendar, now: now)
    struct Record: Decodable { var courseID: UUID; var next: UpcomingCourseLesson? }
    let decoder = JSONCoding.decoder()
    let records = try decoder.decode([Record].self, from: Data(response.utf8))
    #expect(records.count == 2)
    #expect(records.first(where: { $0.courseID == physics.id })?.next?.start == upcomingDate("2026-10-23T10:00:00Z"))
    #expect(records.first(where: { $0.courseID == chemistry.id })?.next == nil)
    let proposal = try JSONDecoder().decode(AssistantTodo.self, from: Data("{\"title\":\"报告\",\"nextCourseID\":\"\(chemistry.id)\"}".utf8))
    #expect(throws: (any Error).self) { try proposal.materialize(now: now, table: table, profile: .standard, calendar: upcomingCalendar) }
    #expect(AssistantUpcomingCourses.nextLessons(table: table, profile: .standard, now: upcomingDate("2027-01-30T00:00:00Z"), calendar: upcomingCalendar).isEmpty)
}

@Test func nextClassFollowsDateMovesInsteadOfOriginalWeekday() throws {
    let lab = Course(name: "实验课", schedules: [CourseSchedule(weekday: 4, periods: [5,6], weekPattern: [8,9])])
    let table = Timetable(startDate: upcomingDate("2026-08-31T00:00:00Z"), courses: [lab])
    let moves = try JSONDecoder().decode([AssistantDateMove].self, from: Data(#"[{"from":"2026-10-22","to":"2026-10-24","targetOriginal":"keep"}]"#.utf8))
    let moved = try AssistantDateEdits.applying(moves, to: table, calendar: upcomingCalendar)
    let now = upcomingDate("2026-10-22T06:00:00Z")
    let lessons = AssistantUpcomingCourses.nextLessons(table: moved, profile: .standard, now: now, calendar: upcomingCalendar)
    #expect(lessons.first?.start == upcomingDate("2026-10-24T14:00:00Z"))
    let ledger = AssistantUpcomingCourses.ledger(table: moved, profile: .standard, now: now, calendar: upcomingCalendar)
    #expect(ledger.contains("2026-10-24T14:00:00Z"))
}

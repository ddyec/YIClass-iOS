import Foundation
import Testing
@testable import YIClassCore

private let activityNow = Date(timeIntervalSince1970: 1_792_980_000)

@Test func activityPhaseUsesExactBoundaries() {
    let item = AgendaActivityItem(id: "course", kind: .course, title: "课程",
        start: activityNow, end: activityNow.addingTimeInterval(3600))
    #expect(item.phase(at: activityNow.addingTimeInterval(-1)) == .upcoming)
    #expect(item.phase(at: activityNow) == .ongoing)
    #expect(item.phase(at: item.end.addingTimeInterval(-301)) == .ongoing)
    #expect(item.phase(at: item.end.addingTimeInterval(-300)) == .ending)
    #expect(item.phase(at: item.end) == .ended)
}

@Test func activityTasksRequirePlacementAndExcludeFinishedAndExpired() {
    let deadlineOnly = TodoItem(title: "仅有截止时间", deadline: activityNow.addingTimeInterval(600))
    let done = TodoItem(title: "已完成", completedAt: activityNow)
    let expired = TodoItem(title: "已结束")
    let active = TodoItem(title: "跨午夜安排")
    let agenda = DayAgendaDocument(todos: [deadlineOnly, done, expired, active], placements: [
        .init(todoID: done.id, start: activityNow.addingTimeInterval(-600), end: activityNow.addingTimeInterval(600)),
        .init(todoID: expired.id, start: activityNow.addingTimeInterval(-600), end: activityNow),
        .init(todoID: active.id, start: activityNow.addingTimeInterval(-3600), end: activityNow.addingTimeInterval(3600))
    ])
    let items = AgendaActivityPlanner.tasks(agenda: agenda, at: activityNow)
    #expect(items.count == 1)
    #expect(items.first?.title == active.title)
    #expect(items.first?.kind == .task)
}

@Test func activityPlannerBoundsRequestsAndUsesWorkTimeRatherThanDeadline() throws {
    let todos = (0..<5).map { TodoItem(title: "任务 \($0)", deadline: activityNow.addingTimeInterval(-3600)) }
    let agenda = DayAgendaDocument(todos: todos, placements: todos.enumerated().map { index, todo in
        TodoPlacement(todoID: todo.id, start: activityNow.addingTimeInterval(Double(index - 1) * 3600),
                      end: activityNow.addingTimeInterval(Double(index + 1) * 3600))
    })
    let items = AgendaActivityPlanner.tasks(agenda: agenda, at: activityNow)
    #expect(items.count == 2)
    #expect(items[0].title == todos[0].title)
    #expect(items[1].title == todos[1].title)
    #expect(try JSONDecoder().decode([AgendaActivityItem].self, from: JSONEncoder().encode(items)) == items)
    var changed = agenda
    changed.placements[0].start = activityNow.addingTimeInterval(10_000)
    changed.placements[0].end = activityNow.addingTimeInterval(11_000)
    #expect(!AgendaActivityPlanner.tasks(agenda: changed, at: activityNow).contains { $0.id == items[0].id })
}

@Test func longActivityFitsSystemLifetimeAndFarFutureTasksWait() {
    let todo = TodoItem(title: "长安排")
    let end = activityNow.addingTimeInterval(10 * 3600)
    let agenda = DayAgendaDocument(todos: [todo], placements: [
        .init(todoID: todo.id, start: activityNow, end: end)
    ])
    let item = AgendaActivityPlanner.tasks(agenda: agenda, at: activityNow).first!
    #expect(item.visibleFrom > activityNow)
    #expect(item.end.timeIntervalSince(item.visibleFrom) < 8 * 3600)
    #expect(AgendaActivityPlanner.tasks(agenda: agenda, at: activityNow.addingTimeInterval(-86400)).isEmpty)
}

@Test func courseActivityUsesCustomSmallPeriodsAndPreservesTheBreak() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let day = try AssistantDateEdits.date("2026-10-27", calendar: calendar)
    let profile = TimeProfile(periods: [
        PeriodTime(period: 1, start: 480, end: 515),
        PeriodTime(period: 2, start: 522, end: 562),
        PeriodTime(period: 3, start: 600, end: 645)
    ])
    let begins = day.addingTimeInterval(480 * 60)
    let ends = day.addingTimeInterval(562 * 60)
    let periods = AgendaActivityPlanner.coursePeriods(start: begins, end: ends, profile: profile, calendar: calendar)
    #expect(periods.map(\.number) == [1, 2])
    #expect(periods[0].end.timeIntervalSince(periods[0].start) == 35 * 60)
    #expect(periods[1].end.timeIntervalSince(periods[1].start) == 40 * 60)
    #expect(periods[1].start.timeIntervalSince(periods[0].end) == 7 * 60)
    let course = Course(name: "英语", schedules: [CourseSchedule(weekday: 2, periods: [1,2], weekPattern: [1])])
    let table = Timetable(startDate: ScheduleEngine.monday(of: day, calendar: calendar), courses: [course])
    let data = AppData(timeProfile: profile, timetables: [table], selectedID: table.id)
    let window = try #require(WideLessonPlanner.windows(data: data, at: begins, calendar: calendar).first)
    let item = AgendaActivityItem(lesson: window)
    #expect(item.progressPeriods == periods)
    #expect(WideLessonPlanner.remaining(data: data, at: begins, calendar: calendar).first?.periods == periods)
    #expect(try JSONDecoder().decode(AgendaActivityItem.self, from: JSONEncoder().encode(item)) == item)
}

@Test func activityProgressRejectsInvalidPeriodsWithoutInventingBreaks() {
    let end = activityNow.addingTimeInterval(3600)
    let valid = AgendaActivityPeriod(number: 1, start: activityNow, end: activityNow.addingTimeInterval(1200))
    let periods = [valid, valid,
        .init(number: 2, start: activityNow.addingTimeInterval(600), end: end),
        .init(number: 3, start: activityNow.addingTimeInterval(-60), end: activityNow),
        .init(number: 4, start: end, end: end)]
    let item = AgendaActivityItem(id: "bad", kind: .course, title: "课程", start: activityNow, end: end, periods: periods)
    #expect(item.progressPeriods == [valid])
    let task = AgendaActivityItem(id: "task", kind: .task, title: "待办", start: activityNow, end: end, periods: periods)
    #expect(task.progressPeriods == [.init(number: 0, start: activityNow, end: end)])
    let expired = AgendaActivityItem(id: "empty", kind: .course, title: "课程", start: end, end: activityNow)
    #expect(expired.progressPeriods.isEmpty)
}

@Test func oldActivityPayloadCanStillDecodeWithoutPeriodMetadata() throws {
    let item = AgendaActivityItem(id: "legacy", kind: .course, title: "旧活动", start: activityNow, end: activityNow.addingTimeInterval(600))
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
    json.removeValue(forKey: "periods")
    let decoded = try JSONDecoder().decode(AgendaActivityItem.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.periods == nil)
    #expect(decoded.progressPeriods == [.init(number: 0, start: item.start, end: item.end)])
}

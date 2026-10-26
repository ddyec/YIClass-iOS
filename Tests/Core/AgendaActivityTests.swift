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

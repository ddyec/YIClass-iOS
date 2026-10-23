import Foundation

public enum AgendaDates {
    public static func parse(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        guard let date = formatter.date(from: value) else { throw AppFailure("日程时间必须是含时区的 ISO 8601 时间。") }
        return date
    }
}

public struct AssistantTodoChange: Codable, Sendable {
    public enum Action: String, Codable, Sendable { case update, complete, reopen, delete }
    public var todoID: UUID
    public var action: Action
    public var title: String?
    public var notes: String?
    public var deadline: String?
    public var clearDeadline: Bool?
    public var importance: TodoImportance?
}

public struct AssistantAgendaChange: Codable, Sendable {
    public enum Action: String, Codable, Sendable { case schedule, remove }
    public var todoID: UUID
    public var action: Action
    public var start: String?
    public var end: String?
}

public enum AgendaOperations {
    public static func applying(additions: [AssistantTodo], todoChanges: [AssistantTodoChange], agendaChanges: [AssistantAgendaChange],
                                to document: DayAgendaDocument, table: Timetable, profile: TimeProfile, now: Date = Date()) throws -> DayAgendaDocument {
        guard additions.count + todoChanges.count + agendaChanges.count <= 100 else { throw AppFailure("每次最多修改 100 条日程或待办。") }
        guard Set(todoChanges.map(\.todoID)).count == todoChanges.count,
              Set(agendaChanges.map(\.todoID)).count == agendaChanges.count else { throw AppFailure("同一批操作不能重复修改同一待办或安排。") }
        var next = document
        for proposal in additions {
            let todo = try proposal.materialize(now: now, table: table, profile: profile)
            next.todos.append(todo)
            if proposal.scheduledStart != nil || proposal.scheduledEnd != nil {
                guard let start = proposal.scheduledStart, let end = proposal.scheduledEnd else { throw AppFailure("安排新待办时必须同时提供开始和结束时间。") }
                next.placements.append(TodoPlacement(todoID: todo.id, start: try AgendaDates.parse(start), end: try AgendaDates.parse(end)))
            }
        }
        for change in todoChanges {
            guard let index = next.todos.firstIndex(where: { $0.id == change.todoID }) else { throw AppFailure("待办已不存在，请重新查询。") }
            switch change.action {
            case .delete:
                next.todos.remove(at: index); next.placements.removeAll { $0.todoID == change.todoID }
            case .complete: next.todos[index].completedAt = now
            case .reopen: next.todos[index].completedAt = nil
            case .update:
                guard change.title != nil || change.notes != nil || change.importance != nil || change.deadline != nil || change.clearDeadline == true else { throw AppFailure("更新待办时需要提供要修改的字段。") }
                if let title = change.title { next.todos[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let notes = change.notes { next.todos[index].notes = notes }
                if let importance = change.importance { next.todos[index].importance = importance }
                guard change.clearDeadline != true || change.deadline == nil else { throw AppFailure("不能同时清除并设置截止时间。") }
                if change.clearDeadline == true { next.todos[index].deadline = nil }
                if let deadline = change.deadline { next.todos[index].deadline = try AgendaDates.parse(deadline) }
            }
        }
        for change in agendaChanges {
            guard next.todos.contains(where: { $0.id == change.todoID }) else { throw AppFailure("安排引用的待办不存在。") }
            next.placements.removeAll { $0.todoID == change.todoID }
            if change.action == .schedule {
                guard let start = change.start, let end = change.end else { throw AppFailure("请提供日程的开始与结束时间。") }
                next.placements.append(TodoPlacement(todoID: change.todoID, start: try AgendaDates.parse(start), end: try AgendaDates.parse(end)))
            }
        }
        try next.validate()
        return next
    }
}

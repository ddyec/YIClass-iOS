import Foundation

/// Small, self-contained ActivityKit payload. Deadlines never imply work time.
public struct AgendaActivityItem: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Hashable, Sendable { case course, task }
    public let id: String
    public let kind: Kind
    public let title: String
    public let location: String
    public let start: Date
    public let end: Date
    public init(id: String, kind: Kind, title: String, location: String = "", start: Date, end: Date) {
        self.id = id; self.kind = kind; self.title = title; self.location = location
        self.start = start; self.end = end
    }
    public init(lesson: WideLessonWindow) {
        self.init(id: lesson.id, kind: .course, title: lesson.name, location: lesson.location,
                  start: lesson.start, end: lesson.end)
    }
    public enum Phase: Equatable, Sendable { case upcoming, ongoing, ending, ended }
    public func phase(at date: Date) -> Phase {
        if date >= end { return .ended }
        if date < start { return .upcoming }
        return end.timeIntervalSince(date) <= 300 ? .ending : .ongoing
    }
    // A scheduled ActivityKit activity can live for at most eight hours.
    public var visibleFrom: Date { max(start, end.addingTimeInterval(-8 * 3600 + 60)) }
}

public enum AgendaActivityPlanner {
    /// Keep the system activity budget bounded; include overnight placements,
    /// exclude completed/expired tasks, and never invent time from a deadline.
    public static func tasks(agenda: DayAgendaDocument, at now: Date) -> [AgendaActivityItem] {
        let todos = Dictionary(agenda.todos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Array(agenda.placements.compactMap { placement -> AgendaActivityItem? in
            guard let todo = todos[placement.todoID], todo.completedAt == nil,
                  placement.end > placement.start, placement.end > now,
                  placement.start < now.addingTimeInterval(24 * 3600) else { return nil }
            let item = AgendaActivityItem(id: "task-\(todo.id)-\(placement.start.timeIntervalSince1970)-\(placement.end.timeIntervalSince1970)",
                kind: .task, title: todo.title, start: placement.start, end: placement.end)
            return item.visibleFrom < now.addingTimeInterval(24 * 3600) ? item : nil
        }.sorted {
            let left = $0.visibleFrom <= now, right = $1.visibleFrom <= now
            if left != right { return left }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }.prefix(2))
    }
}

import Foundation

/// A real teaching period, excluding the break before the next period.
public struct AgendaActivityPeriod: Codable, Hashable, Sendable, Identifiable {
    public let number: Int
    public let start: Date
    public let end: Date
    public var id: String { "\(number)-\(start.timeIntervalSince1970)" }
    public init(number: Int, start: Date, end: Date) {
        self.number = number; self.start = start; self.end = end
    }
}

/// Small, self-contained ActivityKit payload. Deadlines never imply work time.
public struct AgendaActivityItem: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Hashable, Sendable { case course, task }
    public let id: String
    public let kind: Kind
    public let title: String
    public let location: String
    public let start: Date
    public let end: Date
    public let periods: [AgendaActivityPeriod]?
    public init(id: String, kind: Kind, title: String, location: String = "", start: Date, end: Date, periods: [AgendaActivityPeriod]? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.location = location
        self.start = start; self.end = end; self.periods = periods
    }
    public init(lesson: WideLessonWindow) {
        self.init(id: lesson.id, kind: .course, title: lesson.name, location: lesson.location,
                  start: lesson.start, end: lesson.end, periods: lesson.periods)
    }
    /// Keep all periods in the payload: each native timer can advance without
    /// requiring an ActivityKit update at a class/break boundary.
    public var progressPeriods: [AgendaActivityPeriod] {
        guard end > start else { return [] }
        let candidates = (periods ?? []).filter {
            kind == .course && $0.number > 0 && $0.start >= start && $0.end <= end && $0.end > $0.start
        }.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        var result: [AgendaActivityPeriod] = []
        for period in candidates where result.last.map({ period.start >= $0.end }) ?? true {
            result.append(period)
        }
        return result.isEmpty ? [.init(number: 0, start: start, end: end)] : result
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
    public static func coursePeriods(start: Date, end: Date, profile: TimeProfile,
                                     calendar: Calendar = .current) -> [AgendaActivityPeriod] {
        profile.periods.compactMap { period in
            guard let begins = calendar.date(bySettingHour: period.start / 60, minute: period.start % 60, second: 0, of: start),
                  let ends = calendar.date(bySettingHour: period.end / 60, minute: period.end % 60, second: 0, of: start),
                  begins >= start, ends <= end, ends > begins else { return nil }
            return AgendaActivityPeriod(number: period.period, start: begins, end: ends)
        }.sorted { $0.start < $1.start }
    }

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

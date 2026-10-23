import Foundation

public struct TodoPlacement: Codable, Equatable, Identifiable, Sendable {
    public var todoID: UUID
    public var start: Date
    public var end: Date
    public var id: UUID { todoID }
    public init(todoID: UUID, start: Date, end: Date) { self.todoID = todoID; self.start = start; self.end = end }
    public func validate() throws {
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              end > start, end.timeIntervalSince(start) <= 7 * 86400 else {
            throw AppFailure("待办安排的结束时间必须晚于开始时间，且一次安排不超过七天。")
        }
    }
}

/// Canonical task data lives here. library.json remains the timetable document.
/// Placements refer to stable todo IDs, never copies of task titles or courses.
public struct DayAgendaDocument: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var revision = 0
    public var todos: [TodoItem]
    public var placements: [TodoPlacement]
    public init(todos: [TodoItem] = [], placements: [TodoPlacement] = []) { self.todos = todos; self.placements = placements }
    public func placement(for id: UUID) -> TodoPlacement? { placements.first { $0.todoID == id } }
    public func validate() throws {
        guard schemaVersion == 1, revision >= 0, revision < 1_000_000_000 else { throw AppFailure("日程文件版本不受支持。") }
        guard Set(todos.map(\.id)).count == todos.count, Set(placements.map(\.todoID)).count == placements.count else { throw AppFailure("日程中存在重复的待办标识或时间安排。") }
        for todo in todos { try todo.validate() }
        let ids = Set(todos.map(\.id))
        for placement in placements {
            guard ids.contains(placement.todoID) else { throw AppFailure("时间安排引用的待办不存在。") }
            try placement.validate()
        }
    }
}

public struct AgendaTimelineItem: Identifiable, Equatable, Sendable, Encodable {
    public enum Kind: String, Encodable, Sendable { case course, todo }
    public var id: String
    public var kind: Kind
    public var sourceID: UUID
    public var title: String
    public var subtitle: String
    public var start: Date
    public var end: Date
    public var startMinute: Int
    public var endMinute: Int
    public var color: UInt32
    public var completed: Bool
}

public struct AgendaLane: Identifiable, Sendable {
    public var item: AgendaTimelineItem
    public var column: Int
    public var columns: Int
    public var id: String { item.id }
}

public enum TodoPalette {
    public static func color(_ urgency: TodoUrgency) -> UInt32 {
        switch urgency {
        case .overdue: 0xFFD36D71
        case .today: 0xFFBD813B
        case .soon: 0xFFA78A32
        case .upcoming: 0xFF658AAB
        case .unscheduled: 0xFF7A8292
        case .completed: 0xFF298F84
        }
    }
}

public enum DayAgendaEngine {
    public static func items(data: AppData, agenda: DayAgendaDocument, on date: Date, calendar: Calendar = .current) -> [AgendaTimelineItem] {
        let day = calendar.startOfDay(for: date)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        func minute(_ value: Date) -> Int {
            if value <= day { return 0 }
            if value >= tomorrow { return 1440 }
            return calendar.component(.hour, from: value) * 60 + calendar.component(.minute, from: value)
        }
        var result = WidgetSchedule.lessons(data: data, from: day, days: 1, calendar: calendar).map { lesson in
            AgendaTimelineItem(id: lesson.id, kind: .course, sourceID: lesson.course.id, title: lesson.course.name,
                subtitle: [lesson.course.location, lesson.course.teacher].filter { !$0.isEmpty }.joined(separator: " · "),
                start: lesson.start, end: lesson.end, startMinute: minute(lesson.start), endMinute: minute(lesson.end),
                color: lesson.course.color, completed: false)
        }
        let todos = Dictionary(uniqueKeysWithValues: agenda.todos.map { ($0.id, $0) })
        for placement in agenda.placements where placement.start < tomorrow && placement.end > day {
            guard let todo = todos[placement.todoID] else { continue }
            result.append(AgendaTimelineItem(id: "todo-\(todo.id)", kind: .todo, sourceID: todo.id, title: todo.title,
                subtitle: todo.completedAt == nil ? (todo.importance == .high ? "重要待办" : "待办") : "已完成",
                start: placement.start, end: placement.end, startMinute: minute(placement.start), endMinute: minute(placement.end),
                color: TodoPalette.color(todo.urgencyLevel(on: date)), completed: todo.completedAt != nil))
        }
        return result.sorted { $0.startMinute == $1.startMinute ? $0.id < $1.id : $0.startMinute < $1.startMinute }
    }
    public static func deadlines(_ todos: [TodoItem], on date: Date, calendar: Calendar = .current) -> [TodoItem] {
        TodoItem.ranked(todos, on: date, calendar: calendar).filter { $0.deadline.map { calendar.isDate($0, inSameDayAs: date) } ?? false }
    }
    /// Allocate lanes per overlap cluster. Minimum visible card height is included
    /// so a short task cannot cover the card that follows it.
    public static func lanes(_ items: [AgendaTimelineItem], minimumMinutes: Int = 35) -> [AgendaLane] {
        var result: [AgendaLane] = [], cluster: [AgendaTimelineItem] = []
        var clusterEnd = -1
        func flush() {
            var ends: [Int] = [], allocated: [(AgendaTimelineItem, Int)] = []
            for item in cluster {
                let index = ends.firstIndex { $0 <= item.startMinute } ?? ends.count
                let end = max(item.endMinute, item.startMinute + minimumMinutes)
                if index == ends.count { ends.append(end) } else { ends[index] = end }
                allocated.append((item, index))
            }
            result += allocated.map { AgendaLane(item: $0.0, column: $0.1, columns: ends.count) }
            cluster.removeAll()
        }
        for item in items.sorted(by: { $0.startMinute == $1.startMinute ? $0.id < $1.id : $0.startMinute < $1.startMinute }) {
            if !cluster.isEmpty && item.startMinute >= clusterEnd { flush(); clusterEnd = -1 }
            cluster.append(item); clusterEnd = max(clusterEnd, max(item.endMinute, item.startMinute + minimumMinutes))
        }
        if !cluster.isEmpty { flush() }
        return result
    }
}

public enum TodoWidgetSchedule {
    public static func dates(todos: [TodoItem], now: Date, calendar: Calendar = .current) -> [Date] {
        let horizon = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        var dates: Set<Date> = [now, horizon]
        for todo in todos where todo.completedAt == nil {
            if let deadline = todo.deadline, deadline >= now && deadline < horizon { dates.insert(deadline.addingTimeInterval(1)) }
        }
        return dates.sorted()
    }
}

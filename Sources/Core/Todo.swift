import Foundation

public enum TodoImportance: String, Codable, CaseIterable, Sendable, Identifiable {
    case low, normal, high
    public var id: String { rawValue }
    public var title: String { switch self { case .low: "低"; case .normal: "普通"; case .high: "高" } }
    public var weight: Int { switch self { case .low: 0; case .normal: 20; case .high: 40 } }
}

public enum TodoSource: String, Codable, Sendable { case manual, assistant }

public struct TodoItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var deadline: Date?
    public var importance: TodoImportance
    public var source: TodoSource
    public var createdAt: Date
    public var completedAt: Date?
    public init(id: UUID = UUID(), title: String, notes: String = "", deadline: Date? = nil,
                importance: TodoImportance = .normal, source: TodoSource = .manual, createdAt: Date = Date(), completedAt: Date? = nil) {
        self.id = id; self.title = title; self.notes = notes; self.deadline = deadline
        self.importance = importance; self.source = source; self.createdAt = createdAt; self.completedAt = completedAt
    }
    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 200, notes.count <= 10_000 else { throw AppFailure("待办标题不能为空或超过 200 字，备注最多 10,000 字。") }
    }
    /// Date-aware urgency supplements, but never overwrites, the user's importance choice.
    public func score(on day: Date, calendar: Calendar = .current) -> Int {
        guard let deadline else { return importance.weight }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: deadline)).day ?? 0
        let urgency = days < 0 ? 100 : days == 0 ? 80 : days == 1 ? 60 : days <= 3 ? 35 : days <= 7 ? 15 : 0
        return importance.weight + urgency
    }
    public func urgency(on day: Date, calendar: Calendar = .current) -> String {
        guard let deadline else { return "未设截止时间" }
        if calendar.isDate(deadline, inSameDayAs: day) { return deadline < day ? "已逾期" : "当日截止" }
        return deadline < calendar.startOfDay(for: day) ? "已逾期" : "即将到期"
    }
    public static func ranked(_ items: [Self], on day: Date, calendar: Calendar = .current) -> [Self] {
        items.filter { $0.completedAt == nil && calendar.startOfDay(for: $0.createdAt) <= calendar.startOfDay(for: day) }.sorted {
            let left = $0.score(on: day, calendar: calendar), right = $1.score(on: day, calendar: calendar)
            if left != right { return left > right }
            if $0.deadline != $1.deadline { return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

/// AI supplies local dates with explicit UTC offset. Unknown deadlines stay nil.
public struct AssistantTodo: Codable, Sendable {
    public var title: String
    public var notes: String?
    public var deadline: String?
    public var importance: TodoImportance?
    public var nextCourseID: UUID?
    public func materialize(now: Date = Date(), table: Timetable? = nil, profile: TimeProfile? = nil,
                            calendar: Calendar = .current) throws -> TodoItem {
        var date: Date?
        if let deadline {
            let formatter = ISO8601DateFormatter()
            date = formatter.date(from: deadline)
            if date == nil {
                formatter.formatOptions.insert(.withFractionalSeconds)
                date = formatter.date(from: deadline)
            }
            guard date != nil else { throw AppFailure("待办截止时间无效，请使用含时区的 ISO 8601 时间。") }
        }
        var resolvedNotes = notes ?? ""
        if let nextCourseID {
            guard let table, let profile,
                  let lesson = AssistantUpcomingCourses.nextLessons(table: table, profile: profile, now: now, calendar: calendar)
                    .first(where: { $0.courseID == nextCourseID }) else {
                throw AppFailure("该课程没有可确定的下一次上课时间，请核对当前课表或补充截止日期。")
            }
            // The locally resolved class start is authoritative, even if AI supplied a different date.
            date = lesson.start
            resolvedNotes += (resolvedNotes.isEmpty ? "" : "\n") + "截止依据：添加时课表中“\(lesson.name)”的下一次开课时间。"
        }
        let item = TodoItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: resolvedNotes,
                            deadline: date, importance: importance ?? .normal, source: .assistant, createdAt: now)
        try item.validate()
        return item
    }
}

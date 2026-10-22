import Foundation

public struct UpcomingCourseLesson: Codable, Equatable, Sendable {
    public var courseID: UUID
    public var name: String
    public var start: Date
    public var end: Date
    public var location: String
}

public enum AssistantUpcomingCourses {
    /// Search the whole semester, including alternate weeks and changes already saved to the timetable.
    /// A class that has already started is not the next class.
    public static func nextLessons(table: Timetable, profile: TimeProfile, now: Date = Date(),
                                   calendar: Calendar = .current) -> [UpcomingCourseLesson] {
        var next: [UUID: UpcomingCourseLesson] = [:]
        let firstWeek = max(1, ScheduleEngine.week(on: now, table: table, calendar: calendar))
        guard firstWeek <= table.totalWeeks else { return [] }
        for week in firstWeek...table.totalWeeks {
            for block in ScheduleEngine.blocks(table: table, week: week, calendar: calendar) {
                let day = ScheduleEngine.date(week: week, weekday: block.weekday, table: table, calendar: calendar)
                guard day >= calendar.startOfDay(for: table.startDate),
                      let first = profile.periods.first(where: { $0.period == block.first }),
                      let last = profile.periods.first(where: { $0.period == block.last }),
                      let start = calendar.date(bySettingHour: first.start / 60, minute: first.start % 60, second: 0, of: day),
                      let end = calendar.date(bySettingHour: last.end / 60, minute: last.end % 60, second: 0, of: day),
                      start > now else { continue }
                if let existing = next[block.course.id], existing.start <= start { continue }
                next[block.course.id] = UpcomingCourseLesson(courseID: block.course.id, name: block.course.name,
                                                             start: start, end: end, location: block.course.location)
            }
        }
        return next.values.sorted { $0.start == $1.start ? $0.courseID.uuidString < $1.courseID.uuidString : $0.start < $1.start }
    }
    public static func ledger(table: Timetable, profile: TimeProfile, now: Date, calendar: Calendar) -> String {
        let lessons = nextLessons(table: table, profile: profile, now: now, calendar: calendar)
        let formatter = ISO8601DateFormatter(); formatter.timeZone = calendar.timeZone
        let lines = table.courses.map { course in
            if let next = lessons.first(where: { $0.courseID == course.id }) {
                return "\(course.name){id:\(course.id)} 下一次：\(formatter.string(from: next.start))–\(formatter.string(from: next.end)) \(next.location)"
            }
            return "\(course.name){id:\(course.id)}：本学期无后续已排课程（可能未排时间或已结束），不能推测下次日期。"
        }
        return "各课程下一次实际开课（本地计算；排除停课、已开始及已结束课程，覆盖本学期全部后续周次）：\n" + lines.joined(separator: "\n")
    }
}

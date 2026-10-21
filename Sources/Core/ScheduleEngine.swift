import Foundation

public struct CourseBlock: Identifiable, Equatable, Sendable {
    public var course: Course
    public var weekday: Int
    public var first: Int
    public var last: Int
    public var key: String
    public var id: String { key }
}

public enum ScheduleEngine {
    public static func monday(of date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }
    public static func week(on date: Date, table: Timetable, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: monday(of: table.startDate, calendar: calendar),
                                          to: calendar.startOfDay(for: date)).day ?? 0
        return Int(floor(Double(days) / 7)) + 1
    }
    public static func date(week: Int, weekday: Int, table: Timetable, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: (week - 1) * 7 + weekday - 1,
                      to: monday(of: table.startDate, calendar: calendar))!
    }
    public static func blocks(table: Timetable, week: Int, calendar: Calendar = .current) -> [CourseBlock] {
        var blocks: [CourseBlock] = []
        for course in table.courses {
            for day in 1...7 {
                let date = date(week: week, weekday: day, table: table, calendar: calendar)
                if table.holidays.contains(where: { calendar.isDate($0, inSameDayAs: date) }) { continue }
                let periods = Set(course.schedules.filter { $0.weekday == day && $0.weekPattern.contains(week) }
                    .flatMap(\.periods)).sorted()
                var runs: [[Int]] = []
                for period in periods {
                    if let last = runs.last?.last, last + 1 == period { runs[runs.count - 1].append(period) }
                    else { runs.append([period]) }
                }
                for run in runs {
                    blocks.append(CourseBlock(course: course, weekday: day, first: run[0], last: run.last!,
                        key: "\(course.id)-\(day)-\(run[0])"))
                }
            }
        }
        return blocks.sorted { ($0.weekday, $0.first, $0.course.name) < ($1.weekday, $1.first, $1.course.name) }
    }
    /// Transitive overlap groups stay together; no conflicting course is hidden.
    public static func overlapGroups(_ blocks: [CourseBlock]) -> [[CourseBlock]] {
        var groups: [[CourseBlock]] = []
        for block in blocks.sorted(by: { $0.first < $1.first }) {
            if let group = groups.last, let end = group.map(\.last).max(), block.first <= end {
                groups[groups.count - 1].append(block)
            } else { groups.append([block]) }
        }
        return groups
    }
    public static func conflictCount(courses: [Course]) -> Int {
        var count = 0
        for left in courses.indices {
            for right in courses.indices where right > left {
                if courses[left].schedules.contains(where: { a in
                    courses[right].schedules.contains { b in
                        a.weekday == b.weekday && !Set(a.periods).isDisjoint(with: b.periods)
                            && !Set(a.weekPattern).isDisjoint(with: b.weekPattern)
                    }
                }) { count += 1 }
            }
        }
        return count
    }
}

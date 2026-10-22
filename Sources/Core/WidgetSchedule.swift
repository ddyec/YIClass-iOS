import Foundation

public struct ScheduledLesson: Identifiable, Equatable, Sendable {
    public let course: Course
    public let start: Date
    public let end: Date
    public var id: String { "\(course.id)-\(start.timeIntervalSince1970)" }
}

public enum WidgetSchedule {
    public static func lessons(data: AppData, from now: Date, days: Int = 14, calendar: Calendar = .current) -> [ScheduledLesson] {
        guard let table = data.timetables.first(where: { $0.id == data.selectedID }) else { return [] }
        var result: [ScheduledLesson] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            let week = ScheduleEngine.week(on: day, table: table, calendar: calendar)
            guard (1...table.totalWeeks).contains(week) else { continue }
            let weekday = (calendar.component(.weekday, from: day) + 5) % 7 + 1
            for block in ScheduleEngine.blocks(table: table, week: week, calendar: calendar) where block.weekday == weekday {
                guard let first = data.timeProfile.periods.first(where: { $0.period == block.first }),
                      let last = data.timeProfile.periods.first(where: { $0.period == block.last }),
                      let start = calendar.date(bySettingHour: first.start / 60, minute: first.start % 60, second: 0, of: day),
                      let end = calendar.date(bySettingHour: last.end / 60, minute: last.end % 60, second: 0, of: day), end > now else { continue }
                result.append(ScheduledLesson(course: block.course, start: start, end: end))
            }
        }
        return result.sorted { $0.start == $1.start ? $0.course.name < $1.course.name : $0.start < $1.start }
    }
}

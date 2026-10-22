import Foundation

public struct ScheduledLesson: Identifiable, Equatable, Sendable {
    public let course: Course
    public let start: Date
    public let end: Date
    public var id: String { "\(course.id)-\(start.timeIntervalSince1970)" }
}

public enum WidgetSchedule {
    /// Ongoing lessons first; rectangular layouts may briefly retain a finished lesson.
    public static func lockScreenLessons(_ lessons: [ScheduledLesson], at date: Date, completionGrace: TimeInterval = 0) -> [ScheduledLesson] {
        let grace = max(0, min(300, completionGrace))
        func rank(_ lesson: ScheduledLesson) -> Int {
            if lesson.start <= date && lesson.end > date { return 0 }
            return lesson.end <= date ? 1 : 2
        }
        return Array(lessons.filter { $0.end.addingTimeInterval(grace) > date }.sorted {
            let left = rank($0), right = rank($1)
            if left != right { return left < right }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }.prefix(2))
    }
    public static func remainingFraction(_ lesson: ScheduledLesson, at date: Date) -> Double {
        guard lesson.end > lesson.start else { return 0 }
        return min(1, max(0, lesson.end.timeIntervalSince(date) / lesson.end.timeIntervalSince(lesson.start)))
    }
    public static func lockScreenTimelineDates(lessons: [ScheduledLesson], from now: Date, until horizon: Date) -> [Date] {
        var dates: Set<Date> = [now]
        let midnight = Calendar.current.startOfDay(for: horizon)
        if midnight > now && midnight < horizon { dates.insert(midnight) }
        for lesson in lessons {
            for date in [lesson.start.addingTimeInterval(-3600), lesson.start, lesson.end.addingTimeInterval(-3600), lesson.end, lesson.end.addingTimeInterval(180)] where date > now && date < horizon { dates.insert(date) }
            // Pre-render progress states; no background timer or reload polling.
            var tick = lesson.start.addingTimeInterval(5 * 60)
            while tick < min(lesson.end, horizon) {
                if tick > now { dates.insert(tick) }
                tick = tick.addingTimeInterval(5 * 60)
            }
        }
        return dates.sorted()
    }
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

import Foundation

public struct ScheduledLesson: Identifiable, Equatable, Sendable {
    public let course: Course
    public let start: Date
    public let end: Date
    public var id: String { "\(course.id)-\(start.timeIntervalSince1970)" }
}

public struct WidgetDaySchedule: Sendable {
    public let day: Date
    public let lessons: [ScheduledLesson]
    public let isTomorrow: Bool
    public var emptyMessage: String { isTomorrow ? "明天没有课程" : "今天没有更多课程" }
}

public enum WidgetSchedule {
    /// Every widget removes a lesson at its actual end; no completion grace.
    public static func lockScreenLessons(_ lessons: [ScheduledLesson], at date: Date) -> [ScheduledLesson] {
        Array(lessons.filter { $0.end > date }.sorted {
            let left = $0.start <= date, right = $1.start <= date
            if left != right { return left }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }.prefix(2))
    }
    public static func displayDay(profile: TimeProfile, at date: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        let minutes = profile.periods.last?.end ?? 1439
        let cutoff = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: today) ?? today
        return date >= cutoff ? (calendar.date(byAdding: .day, value: 1, to: today) ?? today) : today
    }
    public static func daySchedule(data: AppData, at date: Date, calendar: Calendar = .current) -> WidgetDaySchedule {
        let day = displayDay(profile: data.timeProfile, at: date, calendar: calendar)
        let selected = lessons(data: data, from: day, days: 1, calendar: calendar).filter { $0.end > date }
        return WidgetDaySchedule(day: day, lessons: selected, isTomorrow: !calendar.isDate(day, inSameDayAs: date))
    }
    public static func displayTimelineDates(data: AppData, from now: Date, until horizon: Date,
                                             calendar: Calendar = .current) -> [Date] {
        let all = lessons(data: data, from: now, days: 3, calendar: calendar)
        var dates = Set(lockScreenTimelineDates(lessons: all, from: now, until: horizon, calendar: calendar))
        // Add the configured day's end even when there are no evening courses.
        let minutes = data.timeProfile.periods.last?.end ?? 1439
        for offset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let cutoff = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  cutoff > now, cutoff < horizon else { continue }
            dates.insert(cutoff)
        }
        return dates.sorted()
    }
    public static func remainingFraction(_ lesson: ScheduledLesson, at date: Date) -> Double {
        guard lesson.end > lesson.start else { return 0 }
        return min(1, max(0, lesson.end.timeIntervalSince(date) / lesson.end.timeIntervalSince(lesson.start)))
    }
    public static func lockScreenTimelineDates(lessons: [ScheduledLesson], from now: Date, until horizon: Date, calendar: Calendar = .current) -> [Date] {
        var dates: Set<Date> = [now]
        let midnight = calendar.startOfDay(for: horizon)
        if midnight > now && midnight < horizon { dates.insert(midnight) }
        for lesson in lessons {
            for date in [lesson.start.addingTimeInterval(-3600), lesson.start, lesson.end.addingTimeInterval(-3600), lesson.end] where date > now && date < horizon { dates.insert(date) }
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

import Foundation

public struct WideLessonWindow: Codable, Hashable, Sendable, Identifiable {
    public let tableID: UUID
    public let courseID: UUID
    public let name: String
    public let location: String
    public let visibleFrom: Date
    public let start: Date
    public let end: Date
    public var periods: [AgendaActivityPeriod]? = nil
    public func isVisible(at date: Date) -> Bool { visibleFrom <= date && date < end }
    public var id: String { "\(tableID)-\(courseID)-\(start.timeIntervalSince1970)" }
}

public enum WideLessonPlanner {
    public static func remaining(data: AppData, at now: Date, calendar: Calendar = .current) -> [WideLessonWindow] {
        let schedule = WidgetSchedule.daySchedule(data: data, at: now, calendar: calendar)
        let ordered = WidgetSchedule.lockScreenLessons(schedule.lessons, at: now)
        return ordered.map {
            WideLessonWindow(tableID: data.selectedID, courseID: $0.course.id, name: $0.course.name,
                location: $0.course.location, visibleFrom: now, start: $0.start, end: $0.end,
                periods: AgendaActivityPlanner.coursePeriods(start: $0.start, end: $0.end, profile: data.timeProfile, calendar: calendar))
        }
    }
    /// Queue at most the current and next course; future requests stay pending
    /// until the reminder window instead of occupying the island all day.
    public static func windows(data: AppData, at now: Date, leadMinutes: Int = 10,
                               calendar: Calendar = .current) -> [WideLessonWindow] {
        let lead = Double(min(30, max(0, leadMinutes))) * 60
        let horizon = now.addingTimeInterval(24 * 3600)
        let lessons = WidgetSchedule.lessons(data: data, from: now, days: 2, calendar: calendar)
            .filter { $0.end > now && $0.start < horizon }
            .sorted {
                let leftActive = $0.start <= now, rightActive = $1.start <= now
                if leftActive != rightActive { return leftActive }
                return $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
            }
        return Array(lessons.prefix(2)).map { lesson in
            let begin = max(lesson.start.addingTimeInterval(-lead), lesson.end.addingTimeInterval(-8 * 3600 + 60))
            return WideLessonWindow(tableID: data.selectedID, courseID: lesson.course.id,
                name: lesson.course.name, location: lesson.course.location, visibleFrom: begin,
                start: lesson.start, end: lesson.end,
                periods: AgendaActivityPlanner.coursePeriods(start: lesson.start, end: lesson.end,
                    profile: data.timeProfile, calendar: calendar))
        }
    }
}

import Foundation

public struct LessonReminder: Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let title: String
    public let body: String
    public let tableID: UUID
    public let courseID: UUID
}

public enum LessonReminderPlanner {
    public static let identifierPrefix = "yiclass.lesson."
    public static func reminders(data: AppData, now: Date = Date(), leadMinutes: Int = 10,
                                 limit: Int = 60, calendar: Calendar = .current) -> [LessonReminder] {
        guard (0...60).contains(leadMinutes), limit > 0,
              let table = data.timetables.first(where: { $0.id == data.selectedID }) else { return [] }
        let end = calendar.date(byAdding: .day, value: table.totalWeeks * 7,
                                to: ScheduleEngine.monday(of: table.startDate, calendar: calendar)) ?? now
        let days = max(1, min(800, (calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0) + 1))
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "HH:mm"
        var seen = Set<String>()
        return Array(WidgetSchedule.lessons(data: data, from: now, days: days, calendar: calendar).compactMap { lesson -> LessonReminder? in
            let fire = lesson.start.addingTimeInterval(-Double(leadMinutes) * 60)
            guard fire > now else { return nil }
            let id = identifierPrefix + "\(table.id).\(lesson.course.id).\(Int(lesson.start.timeIntervalSince1970))"
            guard seen.insert(id).inserted else { return nil }
            let clock = formatter.string(from: lesson.start) + "–" + formatter.string(from: lesson.end)
            let body = clock + (lesson.course.location.isEmpty ? "" : " · " + lesson.course.location)
            return LessonReminder(id: id, date: fire, title: lesson.course.name + (leadMinutes == 0 ? "开始上课" : "快上课了"),
                                  body: body, tableID: table.id, courseID: lesson.course.id)
        }.prefix(min(60, limit)))
    }
}

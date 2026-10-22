import Foundation

public struct WideLessonWindow: Codable, Hashable, Sendable, Identifiable {
    public let tableID: UUID
    public let courseID: UUID
    public let name: String
    public let location: String
    public let visibleFrom: Date
    public let start: Date
    public let end: Date
    public var id: String { "\(tableID)-\(courseID)-\(start.timeIntervalSince1970)" }
}

public enum WideLessonPlanner {
    /// Plan local starts while the app is open. ActivityKit limits each activity
    /// to eight hours, so very early next-day previews retain the regular widget.
    public static func windows(data: AppData, at now: Date, calendar: Calendar = .current) -> [WideLessonWindow] {
        (0...1).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
            let lessons = WidgetSchedule.lessons(data: data, from: day, days: 1, calendar: calendar)
                .sorted { $0.end == $1.end ? $0.id < $1.id : $0.end < $1.end }
            guard let last = lessons.last, last.end > now else { return nil }
            let minutes = data.timeProfile.periods.last?.end ?? 1439
            guard let available = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: previous) else { return nil }
            let otherEnd = lessons.dropLast().last?.end ?? available
            let begin = max(available, otherEnd, last.end.addingTimeInterval(-8 * 3600 + 60))
            guard begin < last.end else { return nil } // Simultaneously ending classes never become a single class.
            return WideLessonWindow(tableID: data.selectedID, courseID: last.course.id,
                name: last.course.name, location: last.course.location, visibleFrom: begin, start: last.start, end: last.end)
        }
    }
}

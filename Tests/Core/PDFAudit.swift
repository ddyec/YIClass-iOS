import Foundation
import YIClassCore

struct PDFExpectedRow: Codable, Equatable {
    let name: String
    let location: String
    let teacher: String
    let weekday: Int
    let periods: [Int]
    let weeks: [Int]
    var key: String { "\(weekday)-\(periods.first ?? 0)-\(name)-\(weeks.first ?? 0)-\(location)" }
    static func rows(_ table: Timetable) -> [Self] {
        table.courses.flatMap { course -> [Self] in
            if let weeks = course.unscheduledWeeks {
                return [Self(name: course.name, location: course.location, teacher: course.teacher, weekday: 0, periods: [], weeks: weeks)]
            }
            return course.schedules.map { Self(name: course.name, location: course.location, teacher: course.teacher,
                weekday: $0.weekday, periods: $0.periods, weeks: $0.weekPattern) }
        }.sorted { $0.key < $1.key }
    }
}

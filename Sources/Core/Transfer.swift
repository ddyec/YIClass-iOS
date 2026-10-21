import Foundation

/// Wire format also accepts Flutter 2.x exports; their numeric IDs are never reused.
public struct CourseTransfer: Codable, Sendable {
    public var id: UUID?
    public var name: String
    public var location: String?
    public var teacher: String?
    public var color: UInt32?
    public var schedules: [CourseSchedule]
    public init(course: Course) {
        id = course.id; name = course.name; location = course.location; teacher = course.teacher
        color = course.color; schedules = course.schedules
    }
    public func materialize() -> Course {
        Course(id: id ?? UUID(), name: name, location: location ?? "", teacher: teacher ?? "",
               color: color ?? 0xFF637EEA, schedules: schedules)
    }
}

public struct ImportPreview: Sendable {
    public var table: Timetable
    public var suggestedProfile: TimeProfile?
    public var warning: String?
}

public enum TimetableTransfer {
    private struct Settings: Codable {
        var startDate: String?
        var totalWeeks: Int?
        var showWeekend: Bool?
        var holidays: [String]?
    }
    private struct Envelope: Codable {
        var version: String?
        var name: String
        var settings: Settings?
        var timeProfile: TimeProfile?
        var courses: [CourseTransfer]
    }
    public static func decode(_ data: Data) throws -> ImportPreview {
        guard data.count <= 10_000_000 else { throw AppFailure("文件过大，请选择 10 MB 以下的课表。") }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        if let profile = envelope.timeProfile { try profile.validate() }
        let settings = envelope.settings
        if let value = settings?.startDate, parseDate(value) == nil { throw AppFailure("课表开学日期格式无效。") }
        if let values = settings?.holidays, values.contains(where: { parseDate($0) == nil }) { throw AppFailure("停课日期格式无效。") }
        let table = Timetable(name: envelope.name,
            startDate: settings?.startDate.flatMap(parseDate) ?? Date(),
            totalWeeks: settings?.totalWeeks ?? 20, showWeekend: settings?.showWeekend ?? true,
            holidays: settings?.holidays?.compactMap(parseDate) ?? [],
            courses: envelope.courses.map { $0.materialize() })
        let structuralProfile = TimeProfile(periods: (1...20).map {
            PeriodTime(period: $0, start: ($0 - 1) * 60, end: ($0 - 1) * 60 + 45)
        })
        try table.validate(profile: envelope.timeProfile ?? structuralProfile)
        return ImportPreview(table: table, suggestedProfile: envelope.timeProfile,
            warning: envelope.timeProfile == nil
                ? "此文件未包含课节时间，将使用你在设置中保存的统一时间。旧版导出不包含自定义时间，无法从文件恢复。" : nil)
    }
    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        // Flutter DateTime.toIso8601String() can omit the time-zone suffix.
        let local = DateFormatter(); local.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            local.dateFormat = format
            if let date = local.date(from: value) { return date }
        }
        return nil
    }
    public static func encode(table: Timetable, profile: TimeProfile) throws -> Data {
        try table.validate(profile: profile)
        let formatter = ISO8601DateFormatter()
        let envelope = Envelope(version: "3.0", name: table.name,
            settings: Settings(startDate: formatter.string(from: table.startDate), totalWeeks: table.totalWeeks,
                showWeekend: table.showWeekend, holidays: table.holidays.map { formatter.string(from: $0) }),
            timeProfile: profile, courses: table.courses.map(CourseTransfer.init))
        return try JSONCoding.encoder().encode(envelope)
    }
    /// Normal import always keeps the user's shared time profile.
    public static func applying(_ preview: ImportPreview, to data: AppData, adoptTimes: Bool = false) throws -> AppData {
        var next = data
        if adoptTimes {
            guard let profile = preview.suggestedProfile else { throw AppFailure("文件没有可采用的时间配置。") }
            next.timeProfile = profile
        }
        var table = preview.table
        table.id = UUID()
        next.timetables.append(table); next.selectedID = table.id
        try next.validate() // Also checks existing tables if an imported profile is adopted.
        return next
    }
}

import Foundation

public struct AppFailure: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct PeriodTime: Codable, Equatable, Identifiable, Sendable {
    public var period: Int
    public var start: Int // Minutes after midnight, in the device's local time zone.
    public var end: Int
    public var id: Int { period }
    public init(period: Int, start: Int, end: Int) {
        self.period = period; self.start = start; self.end = end
    }
    public static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
    public var label: String { "\(Self.clock(start))–\(Self.clock(end))" }
}

/// The only period-time configuration. Timetables deliberately have no copy.
public struct TimeProfile: Codable, Equatable, Sendable {
    public var periods: [PeriodTime]
    public init(periods: [PeriodTime]) { self.periods = periods }
    public static let standard = TimeProfile(periods: [480, 535, 600, 655, 840, 895, 960, 1015, 1140, 1195, 1250, 1305]
        .enumerated().map { PeriodTime(period: $0.offset + 1, start: $0.element, end: $0.element + 45) })
    public func validate() throws {
        guard (1...20).contains(periods.count) else { throw AppFailure("每天应有 1–20 节课。") }
        for (index, time) in periods.enumerated() {
            guard time.period == index + 1, time.start >= 0, time.end < 1440, time.start < time.end else {
                throw AppFailure("第 \(index + 1) 节的时间无效。")
            }
            if index > 0, periods[index - 1].end > time.start {
                throw AppFailure("第 \(index + 1) 节与上一节时间重叠。")
            }
        }
    }
}

public struct CourseSchedule: Codable, Equatable, Sendable {
    public var weekday: Int
    public var periods: [Int]
    public var weekPattern: [Int]
    public init(weekday: Int, periods: [Int], weekPattern: [Int]) {
        self.weekday = weekday; self.periods = periods; self.weekPattern = weekPattern
    }
    private enum CodingKeys: String, CodingKey { case weekday, day, periods, weekPattern }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        weekday = try values.decodeIfPresent(Int.self, forKey: .weekday) ?? values.decode(Int.self, forKey: .day)
        periods = try values.decode([Int].self, forKey: .periods)
        weekPattern = try values.decode([Int].self, forKey: .weekPattern)
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(weekday, forKey: .weekday)
        try values.encode(periods, forKey: .periods)
        try values.encode(weekPattern, forKey: .weekPattern)
    }
}

public struct Course: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var location: String
    public var teacher: String
    public var color: UInt32
    public var schedules: [CourseSchedule]
    public init(id: UUID = UUID(), name: String, location: String = "", teacher: String = "",
                color: UInt32 = 0xFF637EEA, schedules: [CourseSchedule]) {
        self.id = id; self.name = name; self.location = location; self.teacher = teacher
        self.color = color; self.schedules = schedules
    }
    public func validate(profile: TimeProfile, totalWeeks: Int) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120,
              !schedules.isEmpty, schedules.count <= 100 else { throw AppFailure("课程名称或排课信息无效。") }
        for schedule in schedules {
            guard (1...7).contains(schedule.weekday), !schedule.periods.isEmpty, !schedule.weekPattern.isEmpty,
                  Set(schedule.periods).count == schedule.periods.count,
                  Set(schedule.weekPattern).count == schedule.weekPattern.count,
                  schedule.periods.allSatisfy({ (1...profile.periods.count).contains($0) }),
                  schedule.weekPattern.allSatisfy({ (1...totalWeeks).contains($0) }) else {
                throw AppFailure("“\(name)” 的星期、节次或周次超出设置范围，请先核对时间设置。")
            }
        }
    }
}

public struct Timetable: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var startDate: Date
    public var totalWeeks: Int
    public var showWeekend: Bool
    public var holidays: [Date]
    public var courses: [Course]
    public init(id: UUID = UUID(), name: String = "我的课表", startDate: Date = Date(),
                totalWeeks: Int = 20, showWeekend: Bool = true, holidays: [Date] = [], courses: [Course] = []) {
        self.id = id; self.name = name; self.startDate = startDate; self.totalWeeks = totalWeeks
        self.showWeekend = showWeekend; self.holidays = holidays; self.courses = courses
    }
    public func validate(profile: TimeProfile) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...60).contains(totalWeeks), courses.count <= 500,
              Set(courses.map(\.id)).count == courses.count else { throw AppFailure("课表名称、周数或课程数量无效。") }
        try profile.validate()
        for course in courses { try course.validate(profile: profile, totalWeeks: totalWeeks) }
    }
    public func emptyCopy(name: String) -> Timetable {
        Timetable(name: name, startDate: startDate, totalWeeks: totalWeeks,
                  showWeekend: showWeekend, holidays: holidays)
    }
}

public struct AppData: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var timeProfile: TimeProfile
    public var timetables: [Timetable]
    public var selectedID: UUID
    public init(timeProfile: TimeProfile = .standard, timetables: [Timetable], selectedID: UUID) {
        self.timeProfile = timeProfile; self.timetables = timetables; self.selectedID = selectedID
    }
    public static func fresh() -> AppData {
        let table = Timetable()
        return AppData(timetables: [table], selectedID: table.id)
    }
    public func validate() throws {
        guard schemaVersion == 1 else { throw AppFailure("数据版本不受支持，请更新应用。") }
        guard !timetables.isEmpty, timetables.contains(where: { $0.id == selectedID }),
              Set(timetables.map(\.id)).count == timetables.count else { throw AppFailure("课表索引无效。") }
        try timeProfile.validate()
        for table in timetables { try table.validate(profile: timeProfile) }
    }
}

public enum JSONCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
}

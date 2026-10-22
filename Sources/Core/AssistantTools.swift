import Foundation

public struct AssistantToolDefinition: Encodable, Sendable {
    public struct Property: Encodable, Sendable {
        public var type = "array"
        public var items: [String: String] = ["type": "string"]
        public var description: String
    }
    public struct Parameters: Encodable, Sendable {
        public var type = "object"
        public var properties: [String: Property]
        public var required: [String]
        public var additionalProperties = false
    }
    public struct Function: Encodable, Sendable {
        public var name: String
        public var description: String
        public var parameters: Parameters
    }
    public var type = "function"
    public var function: Function
}

public enum AssistantTools {
    public static func needsLookup(_ text: String) -> Bool {
        text.range(of: #"今天|明天|后天|昨天|前天|本周|下周|上周|周[一二三四五六日天]|星期[一二三四五六日天]|\d{1,2}[月日号]|\d{4}-\d{2}-\d{2}|下次|下节|下一次|下一节|课前|调课|搬课|移课"#, options: .regularExpression) != nil
    }
    public static let definitions: [AssistantToolDefinition] = [
        AssistantToolDefinition(function: .init(name: "get_schedule_dates", description: "查询当前课表指定日期的完整课程 JSON（全天、原排课、有效课和停课状态）。查课或调课前先查源日及目标日。只读，不保存。", parameters: .init(properties: ["dates": .init(description: "1–30 个 yyyy-MM-dd 日期，含源日与目标日")], required: ["dates"]))),
        AssistantToolDefinition(function: .init(name: "get_next_course_lessons", description: "按课程 UUID 查询本学期下一次尚未开始的实际课程，包含开始结束时间，排除停课及未排时间。下次课交报告等待办截止日期必须先查此工具。只读。", parameters: .init(properties: ["courseIDs": .init(description: "1–30 个候选课程 UUID；无法确定是哪门实验课时查询所有候选")], required: ["courseIDs"]))),
        AssistantToolDefinition(function: .init(name: "get_course_records", description: "按 UUID 获取课程完整 JSON，包括所有周次、固定安排和未排时间。只读，不保存。", parameters: .init(properties: ["courseIDs": .init(description: "1–30 个当前课表课程 UUID")], required: ["courseIDs"])))
    ]
    public static func execute(_ call: ChatToolCall, table: Timetable, profile: TimeProfile,
                               calendar: Calendar = .current, now: Date = Date()) throws -> String {
        guard call.type == "function", let bytes = call.function.arguments.data(using: .utf8), bytes.count <= 50_000 else { throw AppFailure("工具参数无效。") }
        let object = try JSONDecoder().decode([String: [String]].self, from: bytes)
        let output: Data
        switch call.function.name {
        case "get_schedule_dates":
            guard Set(object.keys) == ["dates"], let dates = object["dates"], (1...30).contains(dates.count) else { throw AppFailure("请提供 1–30 个查询日期。") }
            struct Day: Encodable {
                var date: String; var week: Int; var weekday: Int; var inSemester: Bool; var holiday: Bool
                var scheduled: [CourseTransfer]; var effective: [CourseTransfer]
            }
            let days = try dates.map { value -> Day in
                let date = try AssistantDateEdits.date(value, calendar: calendar)
                let week = ScheduleEngine.week(on: date, table: table, calendar: calendar)
                let weekday = (calendar.component(.weekday, from: date) + 5) % 7 + 1
                let holiday = table.holidays.contains { calendar.isDate($0, inSameDayAs: date) }
                let inside = (1...table.totalWeeks).contains(week) && date >= calendar.startOfDay(for: table.startDate)
                let courses = inside ? table.courses.compactMap { course -> CourseTransfer? in
                    let selected = course.schedules.filter { $0.weekday == weekday && $0.weekPattern.contains(week) }
                    guard !selected.isEmpty else { return nil }
                    var copy = course
                    copy.schedules = selected.map { CourseSchedule(weekday: weekday, periods: $0.periods, weekPattern: [week]) }
                    copy.unscheduledWeeks = nil
                    return CourseTransfer(course: copy)
                } : []
                return Day(date: value, week: week, weekday: weekday, inSemester: inside, holiday: holiday,
                           scheduled: courses, effective: holiday ? [] : courses)
            }
            struct Result: Encodable { var tableID: UUID; var dates: [Day]; var timeProfile: TimeProfile; var note: String }
            output = try JSONEncoder().encode(Result(tableID: table.id, dates: days, timeProfile: profile, note: "这是执行前快照的真实记录。scheduled 是原排课，effective 排除停课日。未排时间不在固定日期内，查完整记录用 get_course_records。"))
        case "get_next_course_lessons":
            guard Set(object.keys) == ["courseIDs"], let values = object["courseIDs"], (1...30).contains(values.count) else { throw AppFailure("请提供 1–30 个课程 UUID。") }
            let ids = try values.map { value -> UUID in
                guard let id = UUID(uuidString: value), table.courses.contains(where: { $0.id == id }) else { throw AppFailure("课程 UUID 不属于当前课表。") }
                return id
            }
            struct Record: Encodable { var courseID: UUID; var name: String; var next: UpcomingCourseLesson? }
            let lessons = AssistantUpcomingCourses.nextLessons(table: table, profile: profile, now: now, calendar: calendar)
            let records = table.courses.filter { ids.contains($0.id) }.map { course in
                Record(courseID: course.id, name: course.name, next: lessons.first { $0.courseID == course.id })
            }
            output = try JSONCoding.encoder().encode(records)
        case "get_course_records":
            guard Set(object.keys) == ["courseIDs"], let values = object["courseIDs"], (1...30).contains(values.count) else { throw AppFailure("请提供 1–30 个课程 UUID。") }
            let ids = try values.map { value -> UUID in
                guard let id = UUID(uuidString: value), table.courses.contains(where: { $0.id == id }) else { throw AppFailure("课程 UUID 不属于当前课表。") }
                return id
            }
            output = try JSONEncoder().encode(table.courses.filter { ids.contains($0.id) }.map(CourseTransfer.init))
        default: throw AppFailure("未知工具。仅支持查询日期课程、下次开课和课程记录，不能读取其他文件。")
        }
        return String(decoding: output, as: UTF8.self)
    }
}

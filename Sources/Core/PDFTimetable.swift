import Foundation

public struct PDFGridDocument: Codable, Sendable {
    public let columns: [String]
    public let otherCourses: String
    public init(columns: [String], otherCourses: String) { self.columns = columns; self.otherCourses = otherCourses }
    public var source: String {
        columns.enumerated().map { "星期\($0.offset + 1)：\n\($0.element)" }.joined(separator: "\n\n") + "\n其他课程：\n" + otherCourses
    }
}

public enum PDFTimetableImporter {
    private static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]))?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    }
    private static func capture(_ match: NSTextCheckingResult, _ group: Int, _ text: String) -> String {
        guard let range = Range(match.range(at: group), in: text) else { return "" }; return String(text[range])
    }
    private static func field(_ label: String, in text: String) -> String {
        guard let match = matches("(?:^|/)" + label + ":([^/]+)", text).first else { return "" }
        return capture(match, 1, text)
    }
    public static func parse(_ document: PDFGridDocument, template: Timetable, profile: TimeProfile) throws -> Timetable {
        guard document.columns.count == 7 else { throw AppFailure("无法确定 PDF 的星期列，请使用 AI 识别。") }
        var courses: [Course] = []
        let pattern = #"\((\d+)(?:[-~—](\d+))?节\)(第?\d+(?:[-~—]\d+)?周(?:\([单双]\))?)"#
        for (day, raw) in document.columns.enumerated() {
            let text = raw.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace }
            let anchors = matches(pattern, text)
            let allPeriodMarkers = matches(#"\(\d+(?:[-~—]\d+)?节\)"#, text)
            guard anchors.count == allPeriodMarkers.count else { throw AppFailure("PDF 中有无法识别的周次，请使用 AI 补充核对。") }
            for (index, match) in anchors.enumerated() {
                let first = Int(capture(match, 1, text)) ?? 0
                let last = Int(capture(match, 2, text)) ?? first
                guard first >= 1, last >= first, last <= profile.periods.count else { throw AppFailure("PDF 节次超出当前设置，请先增加每日课节数。") }
                let weekText = capture(match, 3, text)
                let weeks = try parseWeeks(weekText, totalWeeks: template.totalWeeks)
                let start = match.range.location
                let end = index + 1 < anchors.count ? anchors[index + 1].range.location : (text as NSString).length
                let content = (text as NSString).substring(with: NSRange(location: start, length: end - start))
                let teaching = field("教学班", in: content)
                guard let suffix = teaching.range(of: #"-\d+.*$"#, options: .regularExpression) else {
                    throw AppFailure("PDF 课程名称不完整，请使用 AI 识别。")
                }
                let name = String(teaching[..<suffix.lowerBound])
                let location = field("场地", in: content)
                let teacher = field("教师", in: content).split(separator: ",").map(String.init).sorted().joined(separator: ",")
                let schedule = CourseSchedule(weekday: day + 1, periods: Array(first...last), weekPattern: weeks)
                if let i = courses.firstIndex(where: { $0.name == name && $0.location == location && $0.teacher == teacher }) {
                    courses[i].schedules.append(schedule)
                } else { courses.append(Course(name: name, location: location, teacher: teacher, color: Course.suggestedColor(for: name), schedules: [schedule])) }
            }
        }
        guard !courses.isEmpty else { throw AppFailure("未找到可识别的 PDF 课程。") }
        let other = document.otherCourses.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: #"\s*([-/])\s*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\n", with: " ")
        let entries = other.split(separator: ";").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for entry in entries {
            guard let match = matches(#"^(.+?)\s+([^\s()]+)\(共\d+周\)/([\d\-]+)周/(.*)$"#, entry).first else {
                throw AppFailure("PDF 的未排课课程无法完整读取，请使用 AI 核对，避免漏课。")
            }
            courses.append(Course(name: capture(match, 1, entry).trimmingCharacters(in: .whitespaces), location: capture(match, 4, entry).trimmingCharacters(in: .whitespaces),
                teacher: capture(match, 2, entry), schedules: [], unscheduledWeeks: try parseWeeks(capture(match, 3, entry), totalWeeks: template.totalWeeks)))
        }
        var result = template.emptyCopy(name: "导入课表")
        result.courses = courses
        if courses.flatMap(\.schedules).contains(where: { $0.weekday >= 6 }) { result.showWeekend = true }
        try result.validate(profile: profile)
        return result
    }
    public static func parseWeeks(_ text: String, totalWeeks: Int) throws -> [Int] {
        let numbers = matches(#"\d+"#, text).compactMap { Int(capture($0, 0, text)) }
        guard let first = numbers.first, let last = numbers.last, first >= 1, last >= first, last <= totalWeeks else {
            throw AppFailure("课表周次超出当前学期，请核对学期总周数。")
        }
        let result = Array(first...last).filter { text.contains("单") ? $0 % 2 == 1 : (text.contains("双") ? $0 % 2 == 0 : true) }
        guard !result.isEmpty else { throw AppFailure("课表周次为空。") }; return result
    }
}

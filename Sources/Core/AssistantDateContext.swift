import Foundation

public enum AssistantDateContext {
    public static func ledger(table: Timetable, profile: TimeProfile, text: String, now: Date,
                               calendar: Calendar = .current) -> String {
        let formatter = DateFormatter(); formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var dates = Set<Date>()
        for offset in -1...7 { if let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) { dates.insert(date) } }
        // Explicit dates may be earlier than today. Do not search only the next
        // two weeks when interpreting a historical make-up class notice.
        for pattern in [#"(?:(20\d{2})年)?(\d{1,2})月(\d{1,2})(?:日|号)?"#, #"(20\d{2})-(\d{2})-(\d{2})"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                func number(_ index: Int) -> Int? {
                    guard let range = Range(match.range(at: index), in: text) else { return nil }
                    return Int(text[range])
                }
                guard let month = number(2), let day = number(3) else { continue }
                let year: Int
                if let explicit = number(1) { year = explicit }
                else {
                    // Prefer the year in which this month/day lies inside the
                    // current semester, including semesters spanning New Year.
                    let startYear = calendar.component(.year, from: table.startDate)
                    year = [startYear, startYear + 1].first { value in
                        guard let date = calendar.date(from: DateComponents(year: value, month: month, day: day)) else { return false }
                        return (1...table.totalWeeks).contains(ScheduleEngine.week(on: date, table: table, calendar: calendar))
                    } ?? calendar.component(.year, from: now)
                }
                let value = String(format: "%04d-%02d-%02d", year, month, day)
                if let date = try? AssistantDateEdits.date(value, calendar: calendar) { dates.insert(date) }
            }
        }
        let weeks = (1...table.totalWeeks).map { week in
            "第\(week)周=\(formatter.string(from: ScheduleEngine.date(week: week, weekday: 1, table: table, calendar: calendar)))起"
        }.joined(separator: "；")
        let lines = dates.sorted().prefix(90).map { date -> String in
            let week = ScheduleEngine.week(on: date, table: table, calendar: calendar)
            let day = (calendar.component(.weekday, from: date) + 5) % 7 + 1
            var rows: [String] = []
            for course in table.courses {
                let periods = Set(course.schedules.filter { $0.weekday == day && $0.weekPattern.contains(week) }.flatMap(\.periods)).sorted()
                if !periods.isEmpty {
                    let clocks = periods.compactMap { period -> String? in
                        guard let value = profile.periods.first(where: { $0.period == period }) else { return nil }
                        return "\(PeriodTime.clock(value.start))–\(PeriodTime.clock(value.end))"
                    }.joined(separator: ",")
                    rows.append("\(course.name){id:\(course.id)}第\(periods.map(String.init).joined(separator: ","))节[\(clocks)] \(course.location)")
                }
            }
            let holiday = table.holidays.contains { calendar.isDate($0, inSameDayAs: date) }
            return "\(formatter.string(from: date)) 第\(week)周/星期\(day)" + (holiday ? "【停课日，以下为原排课，当前不显示】" : "") + "：" + (rows.isEmpty ? "无固定排课" : rows.joined(separator: "；"))
        }
        return "学期周历（本地计算，周一为周起点）：\n\(weeks)\n相关日期全天原排课（包含下午和夜间；不含未排时间课程）：\n" + lines.joined(separator: "\n")
    }
}

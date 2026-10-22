import Foundation
import Testing
@testable import YIClassCore

private var utcCalendar: Calendar {
    var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
}
private func dateMoves(_ text: String) throws -> [AssistantDateMove] {
    try JSONDecoder().decode([AssistantDateMove].self, from: Data(text.utf8))
}
private func request(_ name: String, _ arguments: String) throws -> ChatToolCall {
    try JSONDecoder().decode(ChatToolCall.self, from: JSONSerialization.data(withJSONObject: ["id": "call_1", "type": "function", "function": ["name": name, "arguments": arguments]]))
}
private func gridTable() throws -> Timetable {
    let url = Bundle.module.url(forResource: "timetable-grid-columns", withExtension: "json", subdirectory: "Fixtures")!
    let grid = try JSONDecoder().decode(PDFGridDocument.self, from: Data(contentsOf: url))
    let start = try AssistantDateEdits.date("2026-08-31", calendar: utcCalendar)
    return try PDFTimetableImporter.parse(grid, template: Timetable(startDate: start), profile: .standard)
}

@Test func dateToolReturnsWholeDayIncludingAfternoonAndSeparateHolidayState() throws {
    var table = try gridTable()
    let date = try AssistantDateEdits.date("2026-09-29", calendar: utcCalendar)
    table.holidays = [date]
    let call = try request("get_schedule_dates", #"{"dates":["2026-09-29","2026-10-25"]}"#)
    let text = try AssistantTools.execute(call, table: table, profile: .standard, calendar: utcCalendar)
    let payload = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    let day = (payload["dates"] as! [[String: Any]])[0]
    #expect(day["holiday"] as? Bool == true)
    #expect((day["effective"] as! [Any]).isEmpty)
    let actual = try JSONDecoder().decode([CourseTransfer].self, from: JSONSerialization.data(withJSONObject: day["scheduled"]!))
    let expected = table.courses.filter { $0.schedules.contains { $0.weekday == 2 && $0.weekPattern.contains(5) } }
    #expect(Set(actual.compactMap(\.id)) == Set(expected.map(\.id)))
    #expect(actual.flatMap(\.schedules).flatMap(\.periods).contains(5))
    #expect(actual.contains { $0.name.contains("数学") })
    #expect(throws: (any Error).self) { _ = try AssistantTools.execute(request("get_schedule_dates", #"{"dates":["2026-02-30"]}"#), table: table, profile: .standard) }
    #expect(throws: (any Error).self) { _ = try AssistantTools.execute(request("read_file", #"{"paths":["library.json"]}"#), table: table, profile: .standard) }
}

@Test func noticeMovesAllPDFDaysAndPreservesOtherWeeksAndPendingCourses() throws {
    let before = try gridTable()
    let moves = try dateMoves(#"[{"from":"2026-09-28","to":"2026-10-18","targetOriginal":"unschedule"},{"from":"2026-09-29","to":"2026-10-25","targetOriginal":"unschedule"},{"from":"2026-09-30","to":"2026-11-01","targetOriginal":"unschedule"}]"#)
    let after = try AssistantDateEdits.applying(moves, to: before, calendar: utcCalendar)
    try after.validate(profile: .standard)
    #expect(after.courses.map(\.id) == before.courses.map(\.id))
    #expect(after.showWeekend)
    for move in moves {
        let from = try AssistantDateEdits.date(move.from, calendar: utcCalendar), to = try AssistantDateEdits.date(move.to, calendar: utcCalendar)
        let sourceWeek = ScheduleEngine.week(on: from, table: before, calendar: utcCalendar)
        let sourceDay = (utcCalendar.component(.weekday, from: from) + 5) % 7 + 1
        let targetWeek = ScheduleEngine.week(on: to, table: before, calendar: utcCalendar)
        let expected = before.courses.flatMap { course in course.schedules.filter { $0.weekday == sourceDay && $0.weekPattern.contains(sourceWeek) }.map { "\(course.id):\($0.periods.sorted())" } }
        let actual = after.courses.flatMap { course in course.schedules.filter { $0.weekday == 7 && $0.weekPattern.contains(targetWeek) }.map { "\(course.id):\($0.periods.sorted())" } }
        #expect(Set(actual) == Set(expected))
        #expect(!after.courses.contains { $0.schedules.contains { $0.weekday == sourceDay && $0.weekPattern.contains(sourceWeek) } })
    }
    for old in before.courses {
        let new = after.courses.first { $0.id == old.id }!
        #expect(old.name == new.name && old.location == new.location && old.teacher == new.teacher && old.color == new.color)
        for schedule in old.schedules {
            for week in schedule.weekPattern where !((week == 5 && schedule.weekday <= 3) || ([7,8,9].contains(week) && schedule.weekday == 7)) {
                #expect(new.schedules.contains { $0.weekday == schedule.weekday && $0.periods == schedule.periods && $0.weekPattern.contains(week) })
            }
        }
        if let weeks = old.unscheduledWeeks { #expect(Set(weeks).isSubset(of: Set(new.unscheduledWeeks ?? []))) }
    }
    let restored = try TimetableTransfer.decode(TimetableTransfer.encode(table: after, profile: .standard)).table
    #expect(restored.courses == after.courses)
    #expect(throws: AppFailure.self) { _ = try AssistantDateEdits.applying(moves, to: after, calendar: utcCalendar) }
}

@Test func simultaneousDateSwapUsesOriginalSnapshotAndPartlyUnscheduledCoursesRemainValid() throws {
    let start = try AssistantDateEdits.date("2026-10-19", calendar: utcCalendar)
    let first = Course(name: "上午", schedules: [CourseSchedule(weekday: 1, periods: [1,2], weekPattern: [1,2])])
    let second = Course(name: "晚课", schedules: [CourseSchedule(weekday: 2, periods: [9,10], weekPattern: [1,2])])
    let table = Timetable(startDate: start, courses: [first,second])
    let swapped = try AssistantDateEdits.applying(dateMoves(#"[{"from":"2026-10-19","to":"2026-10-20"},{"from":"2026-10-20","to":"2026-10-19"}]"#), to: table, calendar: utcCalendar)
    #expect(swapped.courses[0].schedules.contains { $0.weekday == 2 && $0.weekPattern == [1] })
    #expect(swapped.courses[1].schedules.contains { $0.weekday == 1 && $0.weekPattern == [1] })
    let pending = try AssistantDateEdits.applying(dateMoves(#"[{"from":"2026-10-19","to":"2026-10-20","targetOriginal":"unschedule"}]"#), to: table, calendar: utcCalendar)
    try pending.validate(profile: .standard)
    #expect(pending.courses[1].unscheduledWeeks == [1])
    #expect(pending.courses[1].schedules[0].weekPattern == [2])
}

@Test func fullPlanCannotSilentlyDropCoursesAndExplicitDeleteIsValidated() throws {
    let first = Course(name: "英语", schedules: [CourseSchedule(weekday: 1, periods: [1], weekPattern: [1])])
    let second = Course(name: "网课", schedules: [], unscheduledWeeks: [1])
    let table = Timetable(courses: [first, second])
    let partial: [String: Any] = ["message": "完成", "applyDirectly": true, "plans": [["title": "修改", "explanation": "", "courses": []]]]
    #expect(throws: AppFailure.self) { _ = try AssistantReply.parse(String(decoding: JSONSerialization.data(withJSONObject: partial), as: UTF8.self), table: table, profile: .standard) }
    let explicit: [String: Any] = ["message": "删除", "applyDirectly": true, "plans": [["title": "删除", "explanation": "", "courses": [], "deletedCourseIDs": [first.id.uuidString, second.id.uuidString]]]]
    let valid = try AssistantReply.parse(String(decoding: JSONSerialization.data(withJSONObject: explicit), as: UTF8.self), table: table, profile: .standard)
    #expect(try valid.plans[0].proposedTable(from: table, profile: .standard).courses.isEmpty)
}

@Test func chatToolTurnRoundTripsCallIDsAndOriginalImages() throws {
    let response = #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"date_call","type":"function","function":{"name":"get_schedule_dates","arguments":"{\"dates\":[\"2026-09-29\"]}"}}]},"finish_reason":"tool_calls"}]}"#
    let turn = try AIChatResponse.turn(from: Data(response.utf8))
    #expect(turn.tool_calls?.first?.id == "date_call")
    let result = ChatMessage(role: "tool", content: #"{"dates":[]}"#, toolCallID: "date_call")
    let body = AIChatRequest(model: "deepseek-flash", messages: [turn, result], maxTokens: 4096, endpoint: URL(string: "https://api.deepseek.com/chat/completions")!, tools: AssistantTools.definitions, requireTool: true)
    let bytes = try JSONEncoder().encode(body)
    let decoded = try JSONDecoder().decode([String: [ChatMessage]].self, from: JSONSerialization.data(withJSONObject: ["messages": (JSONSerialization.jsonObject(with: bytes) as! [String: Any])["messages"]!]))
    #expect(decoded["messages"]?[0].tool_calls?.first?.id == "date_call")
    #expect(decoded["messages"]?[1].tool_call_id == "date_call")
    let object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
    #expect((object["tools"] as? [Any])?.count == 2)
    #expect(object["tool_choice"] as? String == "required")
    #expect(AssistantTools.needsLookup("29号下午不是还有课吗"))
    #expect(!AssistantTools.needsLookup("你好"))
}

@Test func lockScreenSlotsProgressAndEndTransitionUseOneTimeline() throws {
    let start = try AssistantDateEdits.date("2026-10-22", calendar: utcCalendar).addingTimeInterval(14 * 3600)
    let lessons = (0..<3).map { index in ScheduledLesson(course: Course(name: "课\(index)", schedules: []), start: start.addingTimeInterval(Double(index) * 7200), end: start.addingTimeInterval(Double(index) * 7200 + 6000)) }
    let halfway = start.addingTimeInterval(3000)
    #expect(WidgetSchedule.lockScreenLessons(lessons, at: halfway).map(\.course.name) == ["课0", "课1"])
    #expect(WidgetSchedule.remainingFraction(lessons[0], at: halfway) == 0.5)
    #expect(WidgetSchedule.remainingFraction(lessons[0], at: lessons[0].end) == 0)
    #expect(WidgetSchedule.lockScreenLessons(lessons, at: lessons[0].end).map(\.course.name) == ["课1", "课2"])
    let dates = WidgetSchedule.lockScreenTimelineDates(lessons: lessons, from: start, until: start.addingTimeInterval(86400))
    #expect(dates.contains(start.addingTimeInterval(300)))
    #expect(dates.contains(lessons[0].end) && dates.contains(lessons[1].start))
    #expect(Set(dates).count == dates.count && dates == dates.sorted())
}

@Test func finishedLessonsDisappearImmediatelyAndOngoingLessonsStayFirst() throws {
    let start = try AssistantDateEdits.date("2026-10-22", calendar: utcCalendar).addingTimeInterval(14 * 3600)
    let first = ScheduledLesson(course: Course(name: "刚下课", schedules: []), start: start, end: start.addingTimeInterval(6000))
    let next = ScheduledLesson(course: Course(name: "下一节", schedules: []), start: start.addingTimeInterval(7200), end: start.addingTimeInterval(13200))
    #expect(WidgetSchedule.lockScreenLessons([first, next], at: first.end).map(\.course.name) == ["下一节"])
    #expect(WidgetSchedule.lockScreenLessons([first, next], at: next.end).isEmpty)
    let overlapping = ScheduledLesson(course: Course(name: "仍在上课", schedules: []), start: start.addingTimeInterval(3000), end: start.addingTimeInterval(6600))
    #expect(WidgetSchedule.lockScreenLessons([first, overlapping, next], at: first.end).first?.course.name == "仍在上课")
}

@Test func widgetsWaitForConfiguredNightEndEvenWithoutEveningCourses() throws {
    let start = try AssistantDateEdits.date("2026-10-22", calendar: utcCalendar)
    let today = Course(name: "今日下午", schedules: [CourseSchedule(weekday: 4, periods: [5,6], weekPattern: [1])])
    let tomorrow = Course(name: "明日早课", schedules: [CourseSchedule(weekday: 5, periods: [1,2], weekPattern: [1])])
    let table = Timetable(startDate: ScheduleEngine.monday(of: start, calendar: utcCalendar), courses: [today, tomorrow])
    let data = AppData(timetables: [table], selectedID: table.id)
    let afternoon = start.addingTimeInterval(16 * 3600)
    let cutoff = start.addingTimeInterval(Double(data.timeProfile.periods.last!.end * 60))
    let gap = WidgetSchedule.daySchedule(data: data, at: afternoon, calendar: utcCalendar)
    #expect(gap.lessons.isEmpty && !gap.isTomorrow && gap.emptyMessage == "今天没有更多课程")
    #expect(WidgetSchedule.daySchedule(data: data, at: cutoff.addingTimeInterval(-1), calendar: utcCalendar).lessons.isEmpty)
    let evening = WidgetSchedule.daySchedule(data: data, at: cutoff, calendar: utcCalendar)
    #expect(evening.isTomorrow && evening.lessons.map(\.course.name) == ["明日早课"])
    let dates = WidgetSchedule.displayTimelineDates(data: data, from: afternoon, until: afternoon.addingTimeInterval(86400), calendar: utcCalendar)
    #expect(dates.contains(cutoff))
    let midnight = start.addingTimeInterval(86400)
    #expect(dates.contains(midnight))
    #expect(!WidgetSchedule.daySchedule(data: data, at: midnight, calendar: utcCalendar).isTomorrow)
}

@Test func widgetDaySelectionKeepsNightCoursesAndFollowsCustomTimeAndHolidays() throws {
    let start = try AssistantDateEdits.date("2026-10-22", calendar: utcCalendar)
    let night = Course(name: "晚课", schedules: [CourseSchedule(weekday: 4, periods: [10], weekPattern: [1])])
    let tomorrow = Course(name: "明日课", schedules: [CourseSchedule(weekday: 5, periods: [1], weekPattern: [1])])
    let table = Timetable(startDate: ScheduleEngine.monday(of: start, calendar: utcCalendar), holidays: [start.addingTimeInterval(86400)], courses: [night, tomorrow])
    var profile = TimeProfile.standard; try profile.moveEnd(profile.periods.count - 1, to: 21 * 60)
    let data = AppData(timeProfile: profile, timetables: [table], selectedID: table.id)
    let cutoff = start.addingTimeInterval(21 * 3600)
    #expect(WidgetSchedule.daySchedule(data: data, at: cutoff.addingTimeInterval(-1), calendar: utcCalendar).lessons.map(\.course.name) == ["晚课"])
    let after = WidgetSchedule.daySchedule(data: data, at: cutoff, calendar: utcCalendar)
    #expect(after.isTomorrow && after.lessons.isEmpty && after.emptyMessage == "明天没有课程")
    let dates = WidgetSchedule.displayTimelineDates(data: data, from: start.addingTimeInterval(16 * 3600), until: start.addingTimeInterval(30 * 3600), calendar: utcCalendar)
    #expect(dates.contains(cutoff))
    #expect(!dates.contains(start.addingTimeInterval(Double(TimeProfile.standard.periods.last!.end * 60))))
}

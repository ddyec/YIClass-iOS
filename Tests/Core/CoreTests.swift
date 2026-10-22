import Foundation
import Testing
@testable import YIClassCore

private func course(_ name: String = "数学", day: Int = 1, periods: [Int] = [1, 2], weeks: [Int] = [1, 2]) -> Course {
    Course(name: name, schedules: [CourseSchedule(weekday: day, periods: periods, weekPattern: weeks)])
}

@Test func timeProfileRejectsOverlapAndMidnightOverflow() {
    #expect(throws: AppFailure.self) {
        try TimeProfile(periods: [PeriodTime(period: 1, start: 480, end: 540), PeriodTime(period: 2, start: 530, end: 580)]).validate()
    }
    #expect(throws: AppFailure.self) {
        try TimeProfile(periods: [PeriodTime(period: 1, start: 1400, end: 1450)]).validate()
    }
}

@Test func timeProfileRequiresContiguousPeriodNumbers() {
    #expect(throws: AppFailure.self) {
        try TimeProfile(periods: [PeriodTime(period: 2, start: 480, end: 525)]).validate()
    }
}

@Test func importingLegacyFileKeepsCustomTimes() throws {
    let json = #"{"name":"旧课表","settings":{"startDate":"2026-09-01T00:00:00.000","totalWeeks":20,"maxPeriods":12},"courses":[{"name":"数学","color":4284718826,"schedules":[{"weekday":1,"periods":[1,2],"weekPattern":[1,2]}]}]}"#
    let custom = TimeProfile(periods: [PeriodTime(period: 1, start: 550, end: 590), PeriodTime(period: 2, start: 610, end: 650)])
    let table = Timetable()
    let data = AppData(timeProfile: custom, timetables: [table], selectedID: table.id)
    let preview = try TimetableTransfer.decode(Data(json.utf8))
    let imported = try TimetableTransfer.applying(preview, to: data)
    #expect(imported.timeProfile == custom)
    #expect(imported.timetables.count == 2)
    #expect(imported.timetables.last?.courses.first?.name == "数学")
    #expect(preview.warning != nil)
    #expect(Calendar.current.component(.year, from: preview.table.startDate) == 2026)
}

@Test func exportRoundTripIncludesCustomTimeProfileAndCourseIDs() throws {
    let custom = TimeProfile(periods: [PeriodTime(period: 1, start: 550, end: 590)])
    let table = Timetable(courses: [course(periods: [1])])
    let exported = try TimetableTransfer.encode(table: table, profile: custom)
    let preview = try TimetableTransfer.decode(exported)
    #expect(preview.suggestedProfile == custom)
    #expect(preview.table.courses == table.courses)
    #expect(preview.table.totalWeeks == table.totalWeeks)
}

@Test func nativeImportNeverAdoptsTimesImplicitly() throws {
    let existing = Timetable(courses: [course()])
    let original = AppData(timetables: [existing], selectedID: existing.id)
    let custom = TimeProfile(periods: [PeriodTime(period: 1, start: 600, end: 645)])
    let preview = ImportPreview(table: Timetable(courses: [course(periods: [1])]), suggestedProfile: custom)
    let next = try TimetableTransfer.applying(preview, to: original)
    #expect(next.timeProfile == .standard)
    #expect(throws: AppFailure.self) {
        // The shorter profile would hide period 2 in an existing timetable.
        _ = try TimetableTransfer.applying(preview, to: original, adoptTimes: true)
    }
    #expect(original.timeProfile == .standard)
}

@Test func newTableAndSelectionDoNotHaveTimeOverrides() throws {
    let table = Timetable(startDate: Date(timeIntervalSince1970: 1_788_220_800), totalWeeks: 16, showWeekend: false)
    var data = AppData(timeProfile: TimeProfile(periods: [PeriodTime(period: 1, start: 600, end: 645)]),
                       timetables: [table], selectedID: table.id)
    let custom = data.timeProfile
    let another = table.emptyCopy(name: "新课表")
    data.timetables.append(another); data.selectedID = another.id
    let reloaded = try JSONCoding.decoder().decode(AppData.self, from: JSONCoding.encoder().encode(data))
    try reloaded.validate()
    #expect(reloaded.timeProfile == custom)
    #expect(reloaded.selectedID == another.id)
    #expect(another.startDate == table.startDate)
    #expect(another.totalWeeks == 16)
    #expect(another.showWeekend == false)
    #expect(another.courses.isEmpty)
    #expect(another.id != table.id)
}

@Test func disjointPeriodsRenderAsSeparateBlocksAndOverlapsAreVisible() {
    let a = course("数学", periods: [1, 2, 4])
    let b = course("物理", periods: [2, 3])
    let table = Timetable(courses: [a, b])
    let blocks = ScheduleEngine.blocks(table: table, week: 1)
    #expect(blocks.count == 3)
    let groups = ScheduleEngine.overlapGroups(blocks)
    #expect(groups.count == 2)
    #expect(groups[0].count == 2)
    #expect(groups.flatMap { $0 }.count == blocks.count)
    #expect(ScheduleEngine.conflictCount(courses: [a, b]) == 1)
}

@Test func oddAndEvenWeeksDoNotConflict() {
    let a = course(weeks: [1, 3, 5])
    let b = course("物理", weeks: [2, 4, 6])
    #expect(ScheduleEngine.conflictCount(courses: [a, b]) == 0)
    #expect(ScheduleEngine.blocks(table: Timetable(courses: [a, b]), week: 2).first?.course.name == "物理")
}

@Test func holidaySuppressesOnlyThatDate() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
    var table = Timetable(startDate: start, courses: [course()])
    let monday = ScheduleEngine.date(week: 1, weekday: 1, table: table, calendar: calendar)
    table.holidays = [monday]
    #expect(ScheduleEngine.blocks(table: table, week: 1, calendar: calendar).isEmpty)
    #expect(ScheduleEngine.blocks(table: table, week: 2, calendar: calendar).count == 1)
}

@Test func weekCalculationsSurviveDSTAndPreSemesterDates() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
    let table = Timetable(startDate: start)
    let nextMonday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!
    #expect(ScheduleEngine.week(on: nextMonday, table: table, calendar: calendar) == 2)
    #expect(ScheduleEngine.week(on: calendar.date(byAdding: .day, value: -1, to: start)!, table: table, calendar: calendar) == 0)
}

@Test func badAISchedulesAndDuplicateUUIDsAreRejected() {
    let table = Timetable()
    let json = #"{"message":"方案","questions":[],"plans":[{"title":"错误","explanation":"错误节次","courses":[{"name":"数学","schedules":[{"weekday":8,"periods":[1],"weekPattern":[1]}]}]}]}"#
    #expect(throws: AppFailure.self) { _ = try AssistantReply.parse(json, table: table, profile: .standard) }
    let duplicate = course()
    #expect(throws: AppFailure.self) { try Timetable(courses: [duplicate, duplicate]).validate(profile: .standard) }
}

@Test func assistantClarificationHasSelectableOptions() throws {
    let json = #"{"message":"想选哪些天？","questions":[{"title":"星期偏好","options":["工作日","周末"]}],"plans":[]}"#
    let result = try AssistantReply.parse(json, table: Timetable(), profile: .standard)
    #expect(result.questions[0].options.count == 2)
    #expect(result.plans.isEmpty)
}

@Test func assistantCannotApplyStalePlanAfterTimeOrCourseChange() throws {
    let table = Timetable(courses: [course()])
    let snapshot = PlanSnapshot(table: table, profile: .standard)
    var profile = TimeProfile.standard; profile.periods[0].start += 5
    #expect(throws: AppFailure.self) { try snapshot.check(current: table, profile: profile) }
    var changed = table; changed.courses[0].name = "新课程名"
    #expect(throws: AppFailure.self) { try snapshot.check(current: changed, profile: .standard) }
    try snapshot.check(current: table, profile: .standard)
}

@Test func whitespaceNamesEmptyWeeksAndOutOfRangePeriodsAreRejected() {
    for bad in [course("  "), course(periods: [21]), course(weeks: []), course(periods: [1, 1])] {
        #expect(throws: AppFailure.self) { try bad.validate(profile: .standard, totalWeeks: 20) }
    }
}

@Test func malformedAndOversizedImportsFailWithoutMutatingData() {
    #expect(throws: (any Error).self) { _ = try TimetableTransfer.decode(Data("not JSON".utf8)) }
    #expect(throws: AppFailure.self) { _ = try TimetableTransfer.decode(Data(repeating: 32, count: 10_000_001)) }
}

@Test func tenDefaultPeriodsAndLinkedTimeEdits() throws {
    var profile = TimeProfile.standard
    #expect(profile.counts == [4,4,2])
    let original = profile
    try profile.moveStart(0, to: 510)
    for i in profile.periods.indices {
        #expect(profile.periods[i].start == original.periods[i].start + 30)
        #expect(profile.periods[i].end == original.periods[i].end + 30)
    }
    try profile.moveEnd(0, to: 560)
    #expect(profile.periods[0].start == 510)
    #expect(profile.periods[1].start == original.periods[1].start + 35)
    let valid = profile
    #expect(throws: AppFailure.self) { try profile.moveStart(0, to: 1430) }
    #expect(profile == valid)
}

@Test func durationAndGapReflowPreserveLunchAndEveningBreaks() throws {
    var profile = TimeProfile.standard
    let lunch = profile.periods[4].start - profile.periods[3].end
    try profile.setDuration(40, gap: 5)
    #expect(profile.periods.allSatisfy { $0.end - $0.start == 40 })
    #expect(profile.periods[1].start - profile.periods[0].end == 5)
    #expect(profile.periods[4].start - profile.periods[3].end == lunch)
    try profile.resizeSessions([4,4,3], duration: 40, gap: 5)
    #expect(profile.periods.count == 11)
    #expect(profile.counts == [4,4,3])
    try profile.resizeSessions([3,3,1], duration: 40, gap: 5)
    #expect(profile.periods.map(\.period) == Array(1...7))
    #expect(profile.counts == [3,3,1])
    #expect(throws: AppFailure.self) { try profile.resizeSessions([0,0,0], duration: 45, gap: 10) }
}

@Test func widgetUsesSelectedTableAndGlobalTimeIncludingHolidayAndOddWeeks() throws {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))!
    var table = Timetable(startDate: start, courses: [course(weeks: [1,3])])
    let other = Timetable(courses: [course("错误的课表")])
    var profile = TimeProfile.standard; try profile.moveStart(0, to: 540)
    var data = AppData(timeProfile: profile, timetables: [other,table], selectedID: table.id)
    let lessons = WidgetSchedule.lessons(data: data, from: start, calendar: calendar)
    #expect(lessons.count == 1)
    #expect(lessons.first?.course.name == "数学")
    #expect(calendar.component(.hour, from: lessons.first!.start) == 9)
    #expect(WidgetSchedule.lessons(data: data, from: lessons.first!.end, days: 1, calendar: calendar).isEmpty)
    table.holidays = [start]; data.timetables[1] = table
    #expect(WidgetSchedule.lessons(data: data, from: start, calendar: calendar).isEmpty)
}

@Test func suppliedPDFColumnFixturePreservesAllCoursesAndWeeks() throws {
    let url = Bundle.module.url(forResource: "timetable-grid-columns", withExtension: "json", subdirectory: "Fixtures")!
    let grid = try JSONDecoder().decode(PDFGridDocument.self, from: Data(contentsOf: url))
    let table = try PDFTimetableImporter.parse(grid, template: Timetable(), profile: .standard)
    #expect(Set(table.courses.filter { !$0.schedules.isEmpty }.map(\.name)).count == 12)
    #expect(table.courses.flatMap(\.schedules).count == 21)
    #expect(table.courses.filter { $0.unscheduledWeeks != nil }.count == 5)
    let chemistry = table.courses.first { $0.name == "普通化学II" && $0.location == "致明楼_501" }
    #expect(chemistry?.schedules.first?.weekday == 5)
    #expect(chemistry?.schedules.first?.weekPattern == [4,6,8,10,12])
    let evening = table.courses.first { $0.name == "习近平新时代中国特色社会主义思想概论" && $0.location == "未排地点" }
    #expect(evening?.schedules.first?.weekday == 3)
    #expect(evening?.schedules.first?.periods == [9,10])
    #expect(evening?.schedules.first?.weekPattern == [5,7,9,11])
    let crossPage = table.courses.first { $0.name == "新时代实践教育" && $0.location == "致明楼_2号多媒体教室" }
    #expect(crossPage?.teacher == "陈海兵")
    #expect(crossPage?.schedules.first?.weekPattern == [9])
    let exported = try TimetableTransfer.encode(table: table, profile: .standard)
    #expect(try TimetableTransfer.decode(exported).table.courses == table.courses)
}

@Test func AIUnscheduledCoursesAndNewIDsSurvivePreview() throws {
    let json = #"{"message":"导入预览","questions":[],"plans":[{"title":"课表","explanation":"未排时间的课程单独保留","courses":[{"name":"军事理论","teacher":"测试教师","schedules":[],"unscheduledWeeks":[1,2,3]}]}]}"#
    let reply = try AssistantReply.parse(json, table: Timetable(), profile: .standard)
    #expect(reply.plans[0].courses[0].id != nil)
    let first = try reply.plans[0].proposedTable(from: Timetable(), profile: .standard)
    let second = try reply.plans[0].proposedTable(from: Timetable(), profile: .standard)
    #expect(first.courses == second.courses)
    #expect(first.courses[0].unscheduledWeeks == [1,2,3])
    #expect(ScheduleEngine.blocks(table: first, week: 1).isEmpty)
}

@Test func resizingSessionsRemapsCoursePeriodsAndRejectsDeletingUsedPeriod() throws {
    let table = Timetable(courses: [course("下午课", periods: [5,6]), course("晚课", periods: [9,10])])
    let data = AppData(timetables: [table], selectedID: table.id)
    var profile = data.timeProfile
    try profile.resizeSessions([3,4,2], duration: 45, gap: 10)
    let next = try data.replacingTimeProfile(profile)
    #expect(next.timetables[0].courses[0].schedules[0].periods == [4,5])
    #expect(next.timetables[0].courses[1].schedules[0].periods == [8,9])
    try profile.resizeSessions([3,4,1], duration: 45, gap: 10)
    #expect(throws: AppFailure.self) { _ = try data.replacingTimeProfile(profile) }
    #expect(data.timeProfile == .standard)
}

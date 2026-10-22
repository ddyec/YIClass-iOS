import Foundation

/// Declarative date moves keep enumeration and week splitting out of the model.
public struct AssistantDateMove: Codable, Sendable {
    public var from: String
    public var to: String
    public var courseIDs: [UUID]?
    public var targetOriginal: String?
}

public enum AssistantDateEdits {
    public static func date(_ text: String, calendar: Calendar = .current) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let result = formatter.date(from: text), formatter.string(from: result) == text else {
            throw AppFailure("调课日期必须为有效的 yyyy-MM-dd。")
        }
        return result
    }
    public static func applying(_ moves: [AssistantDateMove], to table: Timetable,
                                calendar: Calendar = .current) throws -> Timetable {
        guard moves.count <= 30 else { throw AppFailure("一次最多调整 30 对日期。") }
        var result = table
        var sources = Set<String>(), targets = Set<String>()
        struct Move {
            var sourceWeek: Int; var sourceDay: Int; var targetWeek: Int; var targetDay: Int
            var targetDate: Date; var selected: Set<UUID>; var unschedule: Bool
        }
        var operations: [Move] = []
        // Read every source from the same snapshot, so swaps and chained dates
        // cannot move newly inserted lessons for a second time.
        for move in moves {
            let source = try date(move.from, calendar: calendar), target = try date(move.to, calendar: calendar)
            let sourceWeek = ScheduleEngine.week(on: source, table: table, calendar: calendar)
            let targetWeek = ScheduleEngine.week(on: target, table: table, calendar: calendar)
            let sourceDay = (calendar.component(.weekday, from: source) + 5) % 7 + 1
            let targetDay = (calendar.component(.weekday, from: target) + 5) % 7 + 1
            guard source != target, (1...table.totalWeeks).contains(sourceWeek), (1...table.totalWeeks).contains(targetWeek),
                  source >= calendar.startOfDay(for: table.startDate), target >= calendar.startOfDay(for: table.startDate),
                  sources.insert(move.from).inserted, targets.insert(move.to).inserted else {
                throw AppFailure("调课日期重复、相同或超出学期，请重新选择日期。")
            }
            let mode = move.targetOriginal ?? "keep"
            guard ["keep", "unschedule"].contains(mode) else { throw AppFailure("目标日原课程处理应为 keep 或 unschedule。") }
            let existing = Set(table.courses.filter { course in course.schedules.contains {
                $0.weekday == sourceDay && $0.weekPattern.contains(sourceWeek)
            }}.map(\.id))
            let selected = move.courseIDs.map(Set.init) ?? existing
            guard !selected.isEmpty, selected.isSubset(of: existing) else {
                throw AppFailure("\(move.from) 没有匹配的原始课程。不能报告已完成；请核对当前日期清单及先前调课记录。")
            }
            operations.append(Move(sourceWeek: sourceWeek, sourceDay: sourceDay, targetWeek: targetWeek,
                                   targetDay: targetDay, targetDate: target, selected: selected, unschedule: mode == "unschedule"))
        }
        for index in result.courses.indices {
            let original = table.courses[index]
            var schedules: [CourseSchedule] = []
            var unscheduled = Set(original.unscheduledWeeks ?? [])
            for schedule in original.schedules {
                var weeks = Set(schedule.weekPattern)
                for op in operations {
                    if op.sourceDay == schedule.weekday && op.selected.contains(original.id) { weeks.remove(op.sourceWeek) }
                }
                for op in operations {
                    if op.unschedule && op.targetDay == schedule.weekday && weeks.remove(op.targetWeek) != nil {
                        unscheduled.insert(op.targetWeek)
                    }
                }
                if !weeks.isEmpty { schedules.append(CourseSchedule(weekday: schedule.weekday, periods: schedule.periods, weekPattern: weeks.sorted())) }
                for op in operations where op.selected.contains(original.id) && schedule.weekday == op.sourceDay && schedule.weekPattern.contains(op.sourceWeek) {
                    schedules.append(CourseSchedule(weekday: op.targetDay, periods: schedule.periods, weekPattern: [op.targetWeek]))
                }
            }
            result.courses[index].schedules = schedules
            result.courses[index].unscheduledWeeks = unscheduled.isEmpty ? nil : unscheduled.sorted()
        }
        // An explicitly requested make-up lesson must not remain hidden by an
        // old holiday flag on the destination date.
        result.holidays.removeAll { holiday in operations.contains { calendar.isDate(holiday, inSameDayAs: $0.targetDate) } }
        if operations.contains(where: { $0.targetDay >= 6 }) { result.showWeekend = true }
        return result
    }

    public static func summary(before: Timetable, after: Timetable, moves: [AssistantDateMove], calendar: Calendar = .current) -> String {
        if !moves.isEmpty {
            return moves.map { move in
                let names = before.courses.filter { course in
                    guard let source = try? date(move.from, calendar: calendar) else { return false }
                    let week = ScheduleEngine.week(on: source, table: before, calendar: calendar)
                    let day = (calendar.component(.weekday, from: source) + 5) % 7 + 1
                    return (move.courseIDs == nil || move.courseIDs!.contains(course.id)) && course.schedules.contains { $0.weekday == day && $0.weekPattern.contains(week) }
                }.map(\.name)
                return "\(move.from) → \(move.to)：\(names.joined(separator: "、"))（\(names.count) 门）。" + (move.targetOriginal == "unschedule" ? "目标日原课程保留为未排时间。" : "")
            }.joined(separator: "\n")
        }
        let added = after.courses.filter { item in !before.courses.contains { $0.id == item.id } }
        let changed = after.courses.filter { item in before.courses.contains { $0.id == item.id && $0 != item } }
        let removed = before.courses.filter { item in !after.courses.contains { $0.id == item.id } }
        let parts = [("新增", added), ("调整", changed), ("删除", removed)].filter { !$0.1.isEmpty }
        if parts.isEmpty { return "课表没有变化。" }
        return parts.map { "\($0.0)：\($0.1.map(\.name).joined(separator: "、"))。" }.joined(separator: "\n")
    }
}

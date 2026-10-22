import SwiftUI
import WidgetKit
import YIClassCore

struct LessonEntry: TimelineEntry {
    let date: Date
    let tableName: String
    let lessons: [ScheduledLesson]
    let configured: Bool
    let syncIssue: String?
    var next: ScheduledLesson? { lessons.first { $0.end > date } }
}

struct LessonProvider: TimelineProvider {
    func placeholder(in context: Context) -> LessonEntry {
        LessonEntry(date: Date(), tableName: "我的课表", lessons: [], configured: false, syncIssue: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (LessonEntry) -> Void) {
        completion(entry(at: Date(), result: SharedLibrary.readResult()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LessonEntry>) -> Void) {
        let now = Date(), result = SharedLibrary.readResult()
        let data = try? result.get()
        let lessons = data.map { WidgetSchedule.lessons(data: $0, from: now) } ?? []
        let horizon = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let midnight = Calendar.current.startOfDay(for: horizon)
        let dates = Set([now] + ([midnight] + lessons.flatMap { [$0.start.addingTimeInterval(-3600), $0.start, $0.end.addingTimeInterval(-3600), $0.end] }).filter { $0 > now && $0 < horizon })
        completion(Timeline(entries: dates.sorted().map { entry(at: $0, result: result) }, policy: .after(data == nil ? now.addingTimeInterval(15 * 60) : horizon)))
    }
    private func entry(at date: Date, result: Result<AppData, AppFailure>) -> LessonEntry {
        let data = try? result.get()
        let issue: String?
        if case .failure(let error) = result { issue = error.localizedDescription } else { issue = nil }
        return LessonEntry(date: date, tableName: data?.timetables.first { $0.id == data?.selectedID }?.name ?? "YIClass",
                    lessons: data.map { WidgetSchedule.lessons(data: $0, from: date) } ?? [], configured: data != nil, syncIssue: issue)
    }
}

struct LessonWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LessonEntry
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                if let next = entry.next {
                    let clock = (next.start <= entry.date ? next.end : next.start).formatted(date: .omitted, time: .shortened)
                    Text("\(String(next.course.name.prefix(6))) · \(clock)" + (next.course.location.isEmpty ? "" : " · " + next.course.location))
                } else { Text(entry.configured ? "暂无课程" : "打开 YIClass 同步") }
            case .accessoryCircular:
                if let next = entry.next { circular(next) }
                else {
                    VStack(spacing: 2) {
                        Image(systemName: entry.configured ? "checkmark" : "arrow.triangle.2.circlepath")
                        Text(entry.configured ? "无课" : "待同步").font(.caption2)
                    }
                }
            case .accessoryRectangular:
                if let next = entry.next { rectangular(next) }
                else { Text(entry.configured ? "接下来暂无课程" : (entry.syncIssue ?? "打开 YIClass 同步课表")) }
            default:
                home
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "yiclass://schedule"))
        .privacySensitive()
    }
    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: entry.date) { return "今天" }
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: entry.date), Calendar.current.isDate(date, inSameDayAs: tomorrow) { return "明天" }
        return date.formatted(.dateTime.month().day())
    }
    private func circular(_ lesson: ScheduledLesson) -> some View {
        let ongoing = lesson.start <= entry.date
        let target = ongoing ? lesson.end : lesson.start
        let countdown = target.timeIntervalSince(entry.date) <= 3600
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Text(String(lesson.course.name.prefix(4))).font(.system(size: 10, weight: .medium)).lineLimit(1)
                if countdown {
                    Text(target, style: .timer).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                } else { Text(target, style: .time).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit() }
                Text(ongoing ? (countdown ? "距下课" : "下课") : (countdown ? "距上课" : dayLabel(lesson.start)))
                    .font(.system(size: 9)).lineLimit(1)
            }.padding(5)
        }.accessibilityLabel("\(lesson.course.name)，\(ongoing ? "下课" : "上课")时间 \(target.formatted(date: .abbreviated, time: .shortened))，\(lesson.course.location)")
    }
    private func rectangular(_ lesson: ScheduledLesson) -> some View {
        let ongoing = lesson.start <= entry.date
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(lesson.course.name).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                if ongoing { Text("上课中").font(.system(size: 9)).fixedSize() }
            }
            HStack(spacing: 2) {
                Text(lesson.start, style: .time); Text("–"); Text(lesson.end, style: .time)
                Spacer(minLength: 2)
                if !Calendar.current.isDate(lesson.start, inSameDayAs: entry.date) { Text(dayLabel(lesson.start)) }
            }.font(.caption2).monospacedDigit()
            if !lesson.course.location.isEmpty {
                Label(lesson.course.location, systemImage: "mappin").font(.caption2).lineLimit(1).minimumScaleFactor(0.75)
            } else {
                HStack(spacing: 3) {
                    Text(ongoing ? "距下课" : "距上课")
                    Text(ongoing ? lesson.end : lesson.start, style: .timer).monospacedDigit()
                }.font(.caption2)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    private var home: some View {
        VStack(alignment: .leading, spacing: family == .systemMedium ? 4 : 6) {
            HStack {
                Text(entry.next.map { $0.start <= entry.date ? "正在上课" : "下一节" } ?? "YIClass")
                    .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                Spacer(minLength: 4)
                Text(entry.next?.start ?? entry.date, format: .dateTime.month().day())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let next = entry.next {
                Text(next.course.name).font(.headline).lineLimit(family == .systemSmall ? 2 : 1)
                HStack(spacing: 3) {
                    Text(next.start, style: .time)
                    Text("–")
                    Text(next.end, style: .time)
                    if family == .systemMedium {
                        Spacer(minLength: 4)
                        Text(next.course.location.isEmpty ? "地点待定" : next.course.location)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.font(.subheadline.monospacedDigit())
                if family == .systemSmall {
                    Text(next.course.location.isEmpty ? "地点待定" : next.course.location)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if family == .systemMedium {
                    ForEach(Array(entry.lessons.filter { $0.id != next.id && $0.end > entry.date }.prefix(2))) { lesson in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(lesson.course.name).font(.caption).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(lesson.start, format: .dateTime.day().hour().minute())
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Text(lesson.course.location.isEmpty ? "地点待定" : lesson.course.location)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text(entry.configured ? "接下来暂无课程" : (entry.syncIssue ?? "打开 YIClass 同步课表"))
                    .font(.subheadline)
                Spacer(minLength: 0)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@main struct YIClassWidget: Widget {
    let kind = "YIClassLessons"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LessonProvider()) { LessonWidgetView(entry: $0) }
            .configurationDisplayName("课程安排")
            .description("下一节课、今日课程与上课倒计时。")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

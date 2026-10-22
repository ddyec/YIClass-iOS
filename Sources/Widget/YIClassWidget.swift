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
        let dates = Set([now] + lessons.flatMap { [$0.start, $0.end] }.filter { $0 > now && $0 < horizon })
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
                if let next = entry.next { Text("\(next.course.name) \(next.start.formatted(date: .omitted, time: .shortened))") }
                else { Text(entry.configured ? "暂无课程" : "打开 YIClass 同步") }
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: "graduationcap.fill")
                    if let next = entry.next {
                        if next.start > entry.date { Text(next.start, style: .timer).font(.caption2).monospacedDigit() }
                        else { Text("上课中").font(.caption2) }
                    } else { Text("无课").font(.caption2) }
                }
            case .accessoryRectangular:
                if let next = entry.next {
                    VStack(alignment: .leading) {
                        Text(next.course.name).font(.headline).lineLimit(1)
                        Text(next.start > entry.date ? "即将上课" : "正在上课").font(.caption)
                        Text(next.start, style: .time).font(.caption).monospacedDigit()
                    }
                } else { Text(entry.configured ? "接下来暂无课程" : (entry.syncIssue ?? "打开 YIClass 同步课表")) }
            default:
                home
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "yiclass://schedule"))
        .privacySensitive()
    }
    private var home: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(entry.tableName, systemImage: "graduationcap.fill").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            if let next = entry.next {
                Text(next.start > entry.date ? "下一节课" : "正在上课").font(.caption).foregroundStyle(.secondary)
                Text(next.course.name).font(.headline).lineLimit(2)
                HStack(spacing: 4) {
                    if !Calendar.current.isDate(next.start, inSameDayAs: entry.date) { Text(next.start, format: .dateTime.month().day()) }
                    Text(next.start, style: .time); Text("–"); Text(next.end, style: .time)
                }.font(.caption).monospacedDigit()
                if !next.course.location.isEmpty { Text(next.course.location).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if family == .systemMedium {
                    ForEach(Array(entry.lessons.filter { $0.id != next.id && Calendar.current.isDate($0.start, inSameDayAs: entry.date) }.prefix(2))) { lesson in
                        HStack { Text(lesson.start, style: .time); Text(lesson.course.name).lineLimit(1) }.font(.caption)
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text(entry.configured ? "接下来暂无课程" : (entry.syncIssue ?? "打开 YIClass 同步课表")).font(.headline)
            }
            Spacer(minLength: 0)
        }
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

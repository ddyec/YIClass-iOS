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
        let lessons = data.map { WidgetSchedule.lessons(data: $0, from: now.addingTimeInterval(-180)) } ?? []
        let horizon = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let dates = WidgetSchedule.lockScreenTimelineDates(lessons: lessons, from: now, until: horizon)
        let base = entry(at: now, result: result)
        let entries = dates.map { date in
            LessonEntry(date: date, tableName: base.tableName, lessons: lessons, configured: base.configured, syncIssue: base.syncIssue)
        }
        completion(Timeline(entries: entries, policy: .after(data == nil ? now.addingTimeInterval(15 * 60) : horizon)))
    }
    private func entry(at date: Date, result: Result<AppData, AppFailure>) -> LessonEntry {
        let data = try? result.get()
        let issue: String?
        if case .failure(let error) = result { issue = error.localizedDescription } else { issue = nil }
        return LessonEntry(date: date, tableName: data?.timetables.first { $0.id == data?.selectedID }?.name ?? "YIClass",
                    lessons: data.map { WidgetSchedule.lessons(data: $0, from: date.addingTimeInterval(-180)) } ?? [], configured: data != nil, syncIssue: issue)
    }
}

struct LessonWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var margins
    let entry: LessonEntry
    var position = 0
    var showsTwoLessons = false
    private var displayedLesson: ScheduledLesson? {
        let visible = WidgetSchedule.lockScreenLessons(entry.lessons, at: entry.date)
        return visible.indices.contains(position) ? visible[position] : nil
    }
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                if let next = displayedLesson {
                    let clock = (next.start <= entry.date ? next.end : next.start).formatted(date: .omitted, time: .shortened)
                    Text("\(String(next.course.name.prefix(6))) · \(clock)" + (next.course.location.isEmpty ? "" : " · " + next.course.location))
                } else { Text(entry.configured ? "暂无课程" : "打开 YIClass 同步") }
            case .accessoryCircular:
                if let next = displayedLesson { circular(next) }
                else {
                    Text(entry.configured ? "无课" : "待同步").font(.caption2)
                }
            case .accessoryRectangular:
                let lessons = WidgetSchedule.lockScreenLessons(entry.lessons, at: entry.date, completionGrace: 180)
                if showsTwoLessons && lessons.count == 2 { rectangularPair(lessons) }
                else if lessons.indices.contains(position) { rectangular(lessons[position]) }
                else { Text(entry.configured ? (position == 0 ? "接下来暂无课程" : "后续暂无课程") : (entry.syncIssue ?? "打开 YIClass 同步课表")) }
            default:
                home.padding(margins)
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall || family == .systemMedium { Rectangle().fill(.background) }
            else { Color.clear }
        }
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
    // The default lock-screen widget contains both lessons. A second widget
    // is optional, for people who prefer two larger single-course cards.
    private func rectangularPair(_ lessons: [ScheduledLesson]) -> some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 62
            VStack(spacing: 4) {
                ForEach(lessons) { lesson in
                    VStack(alignment: .leading, spacing: compact ? 0 : 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(lesson.course.name)
                                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(clockRange(lesson))
                                .font(.system(size: compact ? 9 : 10)).monospacedDigit().fixedSize()
                        }
                        if lesson.course.location.isEmpty {
                            HStack(spacing: 3) {
                                if lesson.end <= entry.date { Text("已下课") }
                                else {
                                    Text(lesson.start <= entry.date ? "距下课" : dayLabel(lesson.start))
                                    Text(lesson.start <= entry.date ? lesson.end : lesson.start, style: .timer).monospacedDigit()
                                }
                            }.font(.system(size: compact ? 10 : 11)).lineLimit(1)
                        } else {
                            Text((Calendar.current.isDate(lesson.start, inSameDayAs: entry.date) ? "" : dayLabel(lesson.start) + " · ") + lesson.course.location)
                                .font(.system(size: compact ? 10 : 11))
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background { batteryFill(lesson) }
                    .overlay { courseOutline(lesson) }
                    .foregroundStyle(.primary.opacity(courseEmphasis(lesson)))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(1)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    private func clockRange(_ lesson: ScheduledLesson) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: lesson.start) + "–" + formatter.string(from: lesson.end)
    }
    private func courseEmphasis(_ lesson: ScheduledLesson) -> Double {
        if lesson.end <= entry.date { return 0.38 }
        return lesson.start <= entry.date ? 1 : 0.72
    }
    @ViewBuilder private func batteryFill(_ lesson: ScheduledLesson) -> some View {
        if lesson.start <= entry.date && lesson.end > entry.date {
            GeometryReader { geometry in
                LessonOutline().fill(.primary.opacity(0.12))
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: geometry.size.height * WidgetSchedule.remainingFraction(lesson, at: entry.date))
                    }
            }
        }
    }
    private func courseOutline(_ lesson: ScheduledLesson) -> some View {
        let active = lesson.start <= entry.date && lesson.end > entry.date
        return LessonOutline().stroke(.primary.opacity(active ? 0.95 : (lesson.end <= entry.date ? 0.25 : 0.45)),
                                      lineWidth: active ? 1.4 : 1)
    }
    private func rectangular(_ lesson: ScheduledLesson) -> some View {
        let ongoing = lesson.start <= entry.date && lesson.end > entry.date
        return VStack(alignment: .leading, spacing: 2) {
            Text(lesson.course.name).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 2) {
                Text(lesson.start, style: .time); Text("–"); Text(lesson.end, style: .time)
                if !Calendar.current.isDate(lesson.start, inSameDayAs: entry.date) {
                    Spacer(minLength: 1)
                    Text(dayLabel(lesson.start)).minimumScaleFactor(0.75)
                }
            }.font(.caption2).monospacedDigit().lineLimit(1)
            if !lesson.course.location.isEmpty {
                Text(lesson.course.location).font(.caption2).lineLimit(1).minimumScaleFactor(0.75)
            } else {
                HStack(spacing: 3) {
                    if lesson.end <= entry.date { Text("已下课") }
                    else {
                        Text(ongoing ? "距下课" : "距上课")
                        Text(ongoing ? lesson.end : lesson.start, style: .timer).monospacedDigit()
                    }
                }.font(.caption2)
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background { batteryFill(lesson) }
        .overlay { courseOutline(lesson) }
        .foregroundStyle(.primary.opacity(courseEmphasis(lesson)))
        .padding(1)
        .accessibilityLabel("\(lesson.course.name)，\(lesson.end <= entry.date ? "已下课" : (ongoing ? "上课中" : "待上课"))，\(lesson.start.formatted(date: .abbreviated, time: .shortened))至\(lesson.end.formatted(date: .omitted, time: .shortened))，\(lesson.course.location)")
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

struct YIClassWidget: Widget {
    let kind = "YIClassLessons"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LessonProvider()) { LessonWidgetView(entry: $0, showsTwoLessons: true) }
            .contentMarginsDisabled()
            .configurationDisplayName("课程安排")
            .description("锁屏默认同时显示接下来的两节课；桌面查看课程与倒计时。")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

/// Starts and ends at the bottom centre, with a moderate ten-point radius.
private struct LessonOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(10, min(rect.width, rect.height) / 4)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

struct FollowingLessonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YIClassFollowingLesson", provider: LessonProvider()) {
            LessonWidgetView(entry: $0, position: 1)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("后续课程")
        .description("与单课组件并排放置，显示后面一节课；下课后自动顺延。")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct CurrentLessonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YIClassCurrentLesson", provider: LessonProvider()) {
            LessonWidgetView(entry: $0)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("单课 · 当前或下一节")
        .description("较大字号显示一节课，可与后续课程并排放置。")
        .supportedFamilies([.accessoryRectangular])
    }
}

@main struct YIClassWidgets: WidgetBundle {
    var body: some Widget {
        YIClassWidget()
        CurrentLessonWidget()
        FollowingLessonWidget()
    }
}

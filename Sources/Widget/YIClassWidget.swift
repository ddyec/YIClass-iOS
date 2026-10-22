import SwiftUI
import WidgetKit
import YIClassCore

struct LessonEntry: TimelineEntry {
    let date: Date
    let displayDay: Date
    let tableName: String
    let lessons: [ScheduledLesson]
    let configured: Bool
    let syncIssue: String?
    var next: ScheduledLesson? { lessons.first { $0.end > date } }
    var showsTomorrow: Bool { !Calendar.current.isDate(displayDay, inSameDayAs: date) }
    var emptyMessage: String { showsTomorrow ? "明天没有课程" : "今天没有更多课程" }
}

struct LessonProvider: TimelineProvider {
    func placeholder(in context: Context) -> LessonEntry {
        LessonEntry(date: Date(), displayDay: Date(), tableName: "我的课表", lessons: [], configured: false, syncIssue: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (LessonEntry) -> Void) {
        completion(entry(at: Date(), result: SharedLibrary.readResult()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LessonEntry>) -> Void) {
        let now = Date(), result = SharedLibrary.readResult()
        let data = try? result.get()
        let horizon = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let dates = data.map { WidgetSchedule.displayTimelineDates(data: $0, from: now, until: horizon) } ?? [now]
        let entries = dates.map { entry(at: $0, result: result) }
        completion(Timeline(entries: entries, policy: .after(data == nil ? now.addingTimeInterval(15 * 60) : horizon)))
    }
    private func entry(at date: Date, result: Result<AppData, AppFailure>) -> LessonEntry {
        let data = try? result.get()
        let issue: String?
        if case .failure(let error) = result { issue = error.localizedDescription } else { issue = nil }
        let schedule = data.map { WidgetSchedule.daySchedule(data: $0, at: date) }
        return LessonEntry(date: date, displayDay: schedule?.day ?? date, tableName: data?.timetables.first { $0.id == data?.selectedID }?.name ?? "YIClass",
                    lessons: schedule?.lessons ?? [], configured: data != nil, syncIssue: issue)
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
                } else if entry.configured { Color.clear.accessibilityHidden(true) }
                else { Text("打开 YIClass 同步") }
            case .accessoryCircular:
                if let next = displayedLesson { circular(next) }
                else if entry.configured { Color.clear.accessibilityHidden(true) }
                else { Text("待同步").font(.caption2) }
            case .accessoryRectangular:
                let lessons = WidgetSchedule.lockScreenLessons(entry.lessons, at: entry.date)
                if showsTwoLessons && lessons.count == 2 { rectangularPair(lessons) }
                else if lessons.indices.contains(position) { rectangular(lessons[position]) }
                else if entry.configured { Color.clear.accessibilityHidden(true) }
                else { Text(entry.syncIssue ?? "打开 YIClass 同步课表") }
            default:
                home.padding(margins)
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall || family == .systemMedium { Rectangle().fill(.background) }
            else { Color.clear }
        }
        .widgetURL(entry.configured && displayedLesson == nil && family != .systemSmall && family != .systemMedium ? nil : URL(string: "yiclass://schedule"))
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
            HStack(alignment: .top, spacing: 6) {
                ForEach(lessons) { lesson in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lesson.course.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true).layoutPriority(2)
                        Text(clockRange(lesson))
                            .font(.system(size: 9)).monospacedDigit().lineLimit(1)
                            .minimumScaleFactor(0.85).layoutPriority(1)
                        if lesson.course.location.isEmpty {
                            HStack(spacing: 2) {
                                Text(lesson.start <= entry.date ? "距下课" : "距上课")
                                Text(lesson.start <= entry.date ? lesson.end : lesson.start, style: .timer).monospacedDigit()
                            }.font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.8)
                        } else {
                            Text(lesson.course.location)
                                .font(.system(size: 10)).lineLimit(2).minimumScaleFactor(0.8)
                        }
                    }
                    .padding(.horizontal, 4).padding(.vertical, 5)
                    .frame(width: max(1, (geometry.size.width - 10) / 2), height: max(1, geometry.size.height - 4), alignment: .topLeading)
                    .overlay { courseOutline(lesson, single: false) }
                    .foregroundStyle(.primary.opacity(courseEmphasis(lesson)))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(2)
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
    @ViewBuilder private func courseOutline(_ lesson: ScheduledLesson, single: Bool) -> some View {
        let active = lesson.start <= entry.date && lesson.end > entry.date
        if single {
            LessonOutline().stroke(.primary.opacity(active ? 0.2 : 0.5), lineWidth: 2.4)
        }
        if active {
            LessonOutline().trim(from: 1 - WidgetSchedule.remainingFraction(lesson, at: entry.date), to: 1)
                .stroke(.primary, style: StrokeStyle(lineWidth: single ? 3.2 : 2.8, lineCap: .round))
        }
    }
    private func singleLockContent(_ lesson: ScheduledLesson, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lesson.course.name).font(.system(size: large ? 19 : 14, weight: .semibold))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true).layoutPriority(2)
            HStack(spacing: 2) {
                Text(clockRange(lesson)).monospacedDigit()
                if entry.showsTomorrow { Spacer(minLength: 1); Text("明天") }
            }.font(.system(size: large ? 14 : 11)).lineLimit(1).minimumScaleFactor(0.85)
            if !lesson.course.location.isEmpty {
                Text(lesson.course.location).font(.system(size: large ? 12 : 10))
                    .lineLimit(1).minimumScaleFactor(0.8)
            } else {
                HStack(spacing: 3) {
                    Text(lesson.start <= entry.date ? "距下课" : "距上课")
                    Text(lesson.start <= entry.date ? lesson.end : lesson.start, style: .timer).monospacedDigit()
                }.font(.system(size: large ? 12 : 10)).lineLimit(1)
            }
        }
    }
    private func rectangular(_ lesson: ScheduledLesson) -> some View {
        ViewThatFits(in: .vertical) {
            singleLockContent(lesson, large: true)
            singleLockContent(lesson, large: false)
        }
        .padding(.horizontal, 5).padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay { courseOutline(lesson, single: true) }
        .foregroundStyle(.primary.opacity(courseEmphasis(lesson)))
        .padding(2)
        .accessibilityLabel("\(lesson.course.name)，\(lesson.start <= entry.date ? "上课中" : "待上课")，\(lesson.start.formatted(date: .abbreviated, time: .shortened))至\(lesson.end.formatted(date: .omitted, time: .shortened))，\(lesson.course.location)")
    }
    private func singleHomeLesson(_ lesson: ScheduledLesson) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lesson.course.name).font(.title2.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
            Text(clockRange(lesson)).font(.body.monospacedDigit())
            if !lesson.course.location.isEmpty {
                Text(lesson.course.location).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    private var home: some View {
        VStack(alignment: .leading, spacing: family == .systemMedium ? 4 : 6) {
            HStack {
                Text(entry.next.map { $0.start <= entry.date ? "正在上课" : "下一节" } ?? (entry.configured ? (entry.showsTomorrow ? "明日课程" : "今日课程") : "YIClass"))
                    .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                Spacer(minLength: 4)
                Text(entry.next?.start ?? entry.displayDay, format: .dateTime.month().day())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let next = entry.next {
                if entry.lessons.count == 1 { singleHomeLesson(next) }
                else {
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
                }
            } else {
                Spacer(minLength: 0)
                Text(entry.configured ? entry.emptyMessage : (entry.syncIssue ?? "打开 YIClass 同步课表"))
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
            .description("锁屏双课左右并排，单课自动放大；今日结束后留白，夜间课节结束再切换明日。")
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

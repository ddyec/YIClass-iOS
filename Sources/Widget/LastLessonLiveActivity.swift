import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit
import YIClassCore

struct LastLessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LastLessonActivityAttributes.self) { context in
            LessonActivityContent(context: context)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "yiclass://schedule"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    if context.state.islandEnabled {
                        LessonActivityContent(context: context, island: true)
                    }
                }
            } compactLeading: {
                if context.state.islandEnabled && !context.isStale {
                    Text(String(context.state.window.name.prefix(5))).font(.caption.weight(.semibold)).lineLimit(1)
                }
            } compactTrailing: {
                if context.state.islandEnabled && !context.isStale {
                    Group {
                        if context.state.window.start <= context.state.referenceDate {
                            Text(timerInterval: context.state.window.start...context.state.window.end, countsDown: true)
                        } else { Text(context.state.window.start, style: .time) }
                    }.monospacedDigit().font(.caption).frame(maxWidth: 58)
                }
            } minimal: {
                if context.state.islandEnabled && !context.isStale {
                    Text(String(context.state.window.name.prefix(2))).font(.system(size: 10, weight: .semibold))
                }
            }
            .widgetURL(context.state.islandEnabled ? URL(string: "yiclass://schedule") : nil)
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

private struct LessonActivityContent: View {
    @Environment(\.activityFamily) private var family
    @Environment(\.isActivityFullscreen) private var fullscreen
    let context: ActivityViewContext<LastLessonActivityAttributes>
    var island = false
    private var state: LastLessonActivityAttributes.ContentState { context.state }
    private var daily: Bool { context.attributes.windowID.hasPrefix("daily-") }
    var body: some View {
        Group {
            if context.isStale {
                if daily && state.remainingCount > 1 {
                    Button(intent: RefreshLessonActivityIntent()) {
                        Text("刷新后续课程").font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.plain)
                } else { Color.clear.frame(height: 1).accessibilityHidden(true) }
            } else if family == .small && !island {
                small
            } else {
                full
            }
        }
        .foregroundStyle(.white)
        .privacySensitive()
    }
    private var full: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.lessons.count > 1 {
                HStack {
                    Text(state.window.start, format: .dateTime.month().day())
                    Spacer()
                    Text("剩余 \(state.remainingCount) 门")
                }.font(.system(size: 11)).opacity(0.7)
                HStack(alignment: .top, spacing: 14) {
                    ForEach(state.lessons, id: \.id) { lesson in
                        ActivityCourseCard(lesson: lesson, solo: false, referenceDate: state.referenceDate)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                ActivityCourseCard(lesson: state.window, solo: true, referenceDate: state.referenceDate,
                    enlarged: fullscreen && !island)
            }
            if daily && state.lessons.count > 1 {
                HStack {
                    Link("查看课表", destination: URL(string: "yiclass://schedule")!)
                    Spacer()
                    Button("刷新课程", intent: RefreshLessonActivityIntent())
                }.font(.system(size: 12)).buttonStyle(.plain)
                    .frame(minHeight: 28)
            }
        }
        .padding(state.lessons.count > 1 ? 8 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var small: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(state.window.name).font(.headline).lineLimit(2)
            CourseClock(lesson: state.window).font(.caption.monospacedDigit())
            if !state.window.location.isEmpty {
                Text(state.window.location).font(.caption).lineLimit(2)
            }
            CourseTimeProgress(lesson: state.window)
            if let next = state.following.first {
                Text("随后 · \(next.name)").font(.caption2).lineLimit(1).opacity(0.7)
            }
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityCourseCard: View {
    let lesson: WideLessonWindow
    let solo: Bool
    let referenceDate: Date
    var enlarged = false
    var body: some View {
        VStack(alignment: .leading, spacing: solo ? 6 : 4) {
            Text(lesson.name).font(.system(size: solo ? (enlarged ? 28 : 22) : 16, weight: .semibold))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: solo ? nil : 40, alignment: .topLeading)
            if solo {
                CourseClock(lesson: lesson)
                    .font(.system(size: enlarged ? 22 : 18).monospacedDigit())
                    .fixedSize(horizontal: true, vertical: false)
                if !lesson.location.isEmpty {
                    Text(lesson.location).font(.system(size: enlarged ? 18 : 15))
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                CourseClock(lesson: lesson).font(.system(size: 13).monospacedDigit()).lineLimit(1)
                Text(lesson.location.isEmpty ? " " : lesson.location).font(.system(size: 12))
                    .lineLimit(2).frame(height: 29, alignment: .topLeading).opacity(0.8)
            }
            CourseTimeProgress(lesson: lesson)
        }
        .padding(.horizontal, solo ? 18 : 7).padding(.vertical, solo ? 14 : 5)
        .frame(maxWidth: .infinity, minHeight: solo ? 140 : nil, alignment: .leading)
        .overlay {
            if solo {
                RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.85), lineWidth: 3)
            } else if lesson.start <= referenceDate {
                RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.75), lineWidth: 2.8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CourseClock: View {
    let lesson: WideLessonWindow
    var body: some View {
        HStack(spacing: 3) {
            Text(lesson.start, style: .time)
            Text("–")
            Text(lesson.end, style: .time)
        }
    }
}

private struct CourseTimeProgress: View {
    let lesson: WideLessonWindow
    var body: some View {
        ProgressView(timerInterval: lesson.start...lesson.end, countsDown: true) {
            EmptyView()
        } currentValueLabel: { EmptyView() }
        .progressViewStyle(.linear).tint(.white)
        .frame(height: 4)
    }
}

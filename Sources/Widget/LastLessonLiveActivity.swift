import ActivityKit
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
    let context: ActivityViewContext<LastLessonActivityAttributes>
    var island = false

    var body: some View {
        Group {
            if context.isStale {
                // Never retain an ended course or replace it with action text.
                Color.clear.frame(height: 1).accessibilityHidden(true)
            } else {
                ViewThatFits(in: .vertical) {
                    courses(compact: family == .small || island)
                    courses(compact: true)
                }
            }
        }
        .foregroundStyle(.white)
        .privacySensitive()
    }

    private func courses(compact: Bool) -> some View {
        let lessons = Array(context.state.lessons.prefix(family == .small && !island ? 1 : 2))
        return HStack(alignment: .top, spacing: compact ? 12 : 18) {
            ForEach(lessons, id: \.id) { lesson in
                ActivityCourseCard(lesson: lesson, solo: lessons.count == 1, compact: compact,
                    small: family == .small && !island)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, compact ? 14 : 18)
        .padding(.vertical, compact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityCourseCard: View {
    let lesson: WideLessonWindow
    let solo: Bool
    var compact = false
    var small = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Text(lesson.name)
                .font(.system(size: small ? 14 : solo ? (compact ? 18 : 22) : 16, weight: .semibold))
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            CourseClock(lesson: lesson)
                .font(.system(size: small ? 11 : solo ? (compact ? 14 : 18) : 13).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(lesson.location.isEmpty ? " " : lesson.location)
                .font(.system(size: small ? 11 : solo ? (compact ? 12 : 15) : 12))
                .lineLimit(small ? 1 : 2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

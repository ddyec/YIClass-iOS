import ActivityKit
import SwiftUI
import WidgetKit
import YIClassCore

struct LastLessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LastLessonActivityAttributes.self) { context in
            LessonActivityContent(context: context)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "yiclass://schedule"))
        } dynamicIsland: { context in
            let item = AgendaActivityItem(lesson: context.state.window)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.islandEnabled && !context.isStale {
                        AgendaActivityCard(items: context.state.lessons.map { AgendaActivityItem(lesson: $0) },
                            referenceDate: context.state.referenceDate, compact: true, island: true)
                    }
                }
            } compactLeading: {
                if context.state.islandEnabled && !context.isStale {
                    Image(systemName: "book.closed.fill").font(.system(size: 12)).foregroundStyle(.cyan).frame(width: 12)
                }
            } compactTrailing: {
                if context.state.islandEnabled && !context.isStale {
                    AgendaActivityCountdown(item: item, referenceDate: context.state.referenceDate, label: false, small: true)
                        .frame(width: 40).clipped()
                }
            } minimal: {
                if context.state.islandEnabled && !context.isStale {
                    Image(systemName: "book.closed.fill").font(.system(size: 12)).foregroundStyle(.cyan).frame(width: 12)
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
    var body: some View {
        Group {
            if context.isStale {
                Color.clear.frame(height: 1).accessibilityHidden(true)
            } else {
                AgendaActivityCard(items: context.state.lessons.map { AgendaActivityItem(lesson: $0) },
                    referenceDate: context.state.referenceDate, compact: family == .small)
            }
        }
        .privacySensitive()
    }
}

import ActivityKit
import SwiftUI
import WidgetKit
import YIClassCore

struct AgendaTaskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgendaTaskActivityAttributes.self) { context in
            TaskActivityContent(context: context)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "yiclass://todos"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.islandEnabled && !context.isStale {
                        AgendaActivityCard(items: [context.state.item], referenceDate: context.state.referenceDate,
                            compact: true, island: true)
                    }
                }
            } compactLeading: {
                if context.state.islandEnabled && !context.isStale {
                    Image(systemName: "checklist").font(.system(size: 12)).foregroundStyle(.mint).frame(width: 12)
                }
            } compactTrailing: {
                if context.state.islandEnabled && !context.isStale {
                    AgendaActivityCountdown(item: context.state.item, referenceDate: context.state.referenceDate, label: false, small: true)
                        .frame(width: 40).clipped()
                }
            } minimal: {
                if context.state.islandEnabled && !context.isStale {
                    Image(systemName: "checklist").font(.system(size: 12)).foregroundStyle(.mint).frame(width: 12)
                }
            }
            .widgetURL(context.state.islandEnabled ? URL(string: "yiclass://todos") : nil)
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

private struct TaskActivityContent: View {
    @Environment(\.activityFamily) private var family
    let context: ActivityViewContext<AgendaTaskActivityAttributes>
    var body: some View {
        Group {
            if context.isStale {
                Color.clear.frame(height: 1).accessibilityHidden(true)
            } else {
                AgendaActivityCard(items: [context.state.item], referenceDate: context.state.referenceDate,
                    compact: family == .small)
            }
        }.privacySensitive()
    }
}

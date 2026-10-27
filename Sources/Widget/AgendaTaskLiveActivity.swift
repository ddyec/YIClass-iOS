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
                .widgetURL(URL(string: context.state.item.kind == .course ? "yiclass://schedule" : "yiclass://todos"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading, priority: 1) {
                    if context.state.islandEnabled && !context.isStale { AgendaActivityIslandTitle(item: context.state.item) }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.islandEnabled && !context.isStale {
                        AgendaActivityCountdown(item: context.state.item, referenceDate: context.state.referenceDate)
                            .frame(width: 76, alignment: .trailing).clipped()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.islandEnabled && !context.isStale { AgendaActivityIslandBottom(item: context.state.item) }
                }
            } compactLeading: {
                if context.state.islandEnabled && !context.isStale {
                    Image(systemName: context.state.item.kind == .course ? "book.closed.fill" : "checklist")
                        .font(.system(size: 12))
                        .foregroundStyle(context.state.item.kind == .course ? Color.cyan : Color.mint)
                        .frame(width: 12)
                }
            } compactTrailing: {
                if context.state.islandEnabled && !context.isStale {
                    AgendaActivityCountdown(item: context.state.item, referenceDate: context.state.referenceDate, label: false, small: true)
                        .frame(width: 40).clipped()
                }
            } minimal: {
                if context.state.islandEnabled && !context.isStale {
                    Image(systemName: context.state.item.kind == .course ? "book.closed.fill" : "checklist")
                        .font(.system(size: 12))
                        .foregroundStyle(context.state.item.kind == .course ? Color.cyan : Color.mint)
                        .frame(width: 12)
                }
            }
            .widgetURL(context.state.islandEnabled ? URL(string: context.state.item.kind == .course ? "yiclass://schedule" : "yiclass://todos") : nil)
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

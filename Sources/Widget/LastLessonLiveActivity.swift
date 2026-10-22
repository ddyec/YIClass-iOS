import ActivityKit
import SwiftUI
import WidgetKit
import YIClassCore

struct LastLessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LastLessonActivityAttributes.self) { context in
            Group {
                if context.isStale { Color.clear.frame(height: 1).accessibilityHidden(true) }
                else { WideLastLessonView(window: context.state.window) }
            }
            .activityBackgroundTint(.clear)
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "yiclass://schedule"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    if !context.isStale {
                        WideLastLessonView(window: context.state.window)
                    }
                }
            } compactLeading: {
                if !context.isStale { Text(String(context.state.window.name.prefix(4))) }
            } compactTrailing: {
                if !context.isStale { Text(context.state.window.end, style: .time).monospacedDigit() }
            } minimal: {
                if !context.isStale { Text(String(context.state.window.name.prefix(2))) }
            }
            .widgetURL(URL(string: "yiclass://schedule"))
        }
    }
}

private struct WideLastLessonView: View {
    let window: WideLessonWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(window.name).font(.system(size: 22, weight: .semibold)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 3) {
                    Text(window.start, style: .time)
                    Text("–")
                    Text(window.end, style: .time)
                }.font(.system(size: 18)).monospacedDigit().fixedSize()
                Spacer(minLength: 0)
                if !window.location.isEmpty {
                    Text(window.location).font(.system(size: 15)).lineLimit(2)
                }
            }
            ProgressView(timerInterval: window.start...window.end, countsDown: true) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
            .progressViewStyle(.linear).tint(.white)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 17).padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.85), lineWidth: 3) }
        .padding(4)
        .accessibilityLabel("最后一节课，\(window.name)，\(window.start.formatted(date: .abbreviated, time: .shortened))至\(window.end.formatted(date: .omitted, time: .shortened))，\(window.location)")
    }
}

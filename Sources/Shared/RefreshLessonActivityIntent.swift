#if os(iOS)
import ActivityKit
import AppIntents
import Foundation
import WidgetKit
import YIClassCore

struct RefreshLessonActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "刷新课程活动"
    static let description = IntentDescription("从当前共享课表重新读取正在进行和后续课程。")
    @MainActor func perform() async throws -> some IntentResult {
        let data = try SharedLibrary.readResult().get()
        let now = Date()
        for activity in Activity<LastLessonActivityAttributes>.activities {
            let old = activity.content.state.window
            let lead = Int(old.start.timeIntervalSince(old.visibleFrom) / 60)
            let windows = WideLessonPlanner.windows(data: data, at: now, leadMinutes: lead)
            guard !activity.attributes.windowID.hasPrefix("daily-"),
                  let window = windows.first(where: { $0.id == activity.attributes.windowID }),
                  window.end > now,
                  window.isVisible(at: now) || activity.activityState == .pending else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            var state = LastLessonActivityAttributes.ContentState(window: window)
            state.referenceDate = max(now, window.visibleFrom)
            state.tableName = data.timetables.first { $0.id == data.selectedID }?.name ?? ""
            state.islandEnabled = activity.content.state.islandEnabled
            await activity.update(ActivityContent(state: state, staleDate: window.end))
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
#endif

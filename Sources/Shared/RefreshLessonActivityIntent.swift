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
        let remaining = WideLessonPlanner.remaining(data: data, at: now)
        for activity in Activity<LastLessonActivityAttributes>.activities where activity.attributes.windowID.hasPrefix("daily-") {
            guard let first = remaining.first else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            // Reuse the existing activity, without opening the app or advancing
            // based on a guessed lesson index. Always read the actual JSON.
            var state = LastLessonActivityAttributes.ContentState(window: first)
            state.following = Array(remaining.dropFirst())
            state.remainingCount = WidgetSchedule.daySchedule(data: data, at: now).lessons.count
            state.referenceDate = now
            state.tableName = data.timetables.first { $0.id == data.selectedID }?.name ?? ""
            state.islandEnabled = activity.content.state.islandEnabled
            let finalActivity = Activity<LastLessonActivityAttributes>.activities.first {
                !$0.attributes.windowID.hasPrefix("daily-") && $0.content.state.window.courseID == first.courseID &&
                $0.content.state.window.start == first.start && $0.content.state.window.visibleFrom <= now &&
                $0.activityState == .active
            }
            if state.remainingCount == 1 && finalActivity != nil {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.update(ActivityContent(state: state, staleDate: first.end))
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
#endif

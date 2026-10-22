import ActivityKit
import Observation
import UIKit
import WidgetKit
import YIClassCore

@MainActor @Observable final class LastLessonActivityManager {
    static let shared = LastLessonActivityManager()
    private(set) var enabled = UserDefaults.standard.object(forKey: "wideLastLesson.enabled") as? Bool ?? true
    private(set) var issue: String?
    private var worker: Task<Void, Never>?
    private var boundary: Task<Void, Never>?
    private var generation = 0
    func setEnabled(_ value: Bool, data: AppData) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "wideLastLesson.enabled")
        refresh(data: data)
    }
    func refresh(data: AppData) {
        guard UIApplication.shared.applicationState == .active else { return }
        generation += 1
        let revision = generation
        let previous = worker
        boundary?.cancel()
        worker = Task {
            await previous?.value
            guard revision == generation else { return }
            await reconcile(data: data)
        }
    }
    private func reconcile(data: AppData) async {
        boundary?.cancel()
        let now = Date()
        let allowed = ActivityAuthorizationInfo().areActivitiesEnabled
        let desired = enabled && allowed ? WideLessonPlanner.windows(data: data, at: now) : []
        issue = enabled && !allowed ? "请在系统设置中允许 YIClass 的实时活动。" : nil
        var retained: [Activity<LastLessonActivityAttributes>] = []
        for activity in Activity<LastLessonActivityAttributes>.activities {
            if desired.contains(activity.content.state.window), activity.activityState != .ended, activity.activityState != .dismissed {
                retained.append(activity)
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        for window in desired where !retained.contains(where: { $0.content.state.window == window }) {
            guard UIApplication.shared.applicationState == .active else { break }
            do {
                let attributes = LastLessonActivityAttributes(windowID: window.id)
                let content = ActivityContent(state: LastLessonActivityAttributes.ContentState(window: window), staleDate: window.end)
                let activity: Activity<LastLessonActivityAttributes>
                if window.visibleFrom > Date() {
                    activity = try Activity.request(attributes: attributes, content: content, pushType: nil,
                        style: .standard, alertConfiguration: nil, start: window.visibleFrom)
                } else {
                    activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                }
                retained.append(activity)
            } catch { issue = "宽幅卡片未启用，仍使用普通锁屏组件：\(error.localizedDescription)" }
        }
        do { try WideLessonBridge.write(retained.map { .init(activityID: $0.id, window: $0.content.state.window) }) }
        catch { issue = error.localizedDescription }
        WidgetCenter.shared.reloadAllTimelines()
        let dates = desired.flatMap { [$0.visibleFrom, $0.end] }.filter { $0 > Date() }
        if let next = dates.min() {
            boundary = Task {
                do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow))) }
                catch { return }
                self.refresh(data: data)
            }
        }
    }
}

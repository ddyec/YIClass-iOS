import ActivityKit
import Observation
import UIKit
import WidgetKit
import YIClassCore

@MainActor @Observable final class LastLessonActivityManager {
    static let shared = LastLessonActivityManager()
    private(set) var enabled = UserDefaults.standard.object(forKey: "wideLastLesson.enabled") as? Bool ?? true
    private(set) var allLessons = UserDefaults.standard.bool(forKey: "lessonActivity.allLessons")
    private(set) var islandEnabled = UserDefaults.standard.object(forKey: "lessonActivity.islandEnabled") as? Bool ?? true
    private(set) var scheduledTasks = UserDefaults.standard.object(forKey: "lessonActivity.scheduledTasks") as? Bool ?? true
    private var agenda = DayAgendaDocument()
    private(set) var issue: String?
    private var worker: Task<Void, Never>?
    private var boundary: Task<Void, Never>?
    private var generation = 0
    func setEnabled(_ value: Bool, data: AppData) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "wideLastLesson.enabled")
        refresh(data: data)
    }
    func setAllLessons(_ value: Bool, data: AppData) {
        allLessons = value
        UserDefaults.standard.set(value, forKey: "lessonActivity.allLessons")
        refresh(data: data)
    }
    func setIslandEnabled(_ value: Bool, data: AppData) {
        islandEnabled = value
        UserDefaults.standard.set(value, forKey: "lessonActivity.islandEnabled")
        refresh(data: data)
    }
    func setScheduledTasks(_ value: Bool, data: AppData) {
        scheduledTasks = value
        UserDefaults.standard.set(value, forKey: "lessonActivity.scheduledTasks")
        refresh(data: data)
    }
    func refresh(data: AppData, agenda: DayAgendaDocument? = nil) {
        if let agenda { self.agenda = agenda }
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
    private struct Request {
        let id: String
        let state: LastLessonActivityAttributes.ContentState
        var start: Date { state.window.visibleFrom }
    }
    private func reconcile(data: AppData) async {
        boundary?.cancel()
        let now = Date()
        let allowed = ActivityAuthorizationInfo().areActivitiesEnabled
        let windows = enabled && allowed ? WideLessonPlanner.windows(data: data, at: now) : []
        let tableName = data.timetables.first { $0.id == data.selectedID }?.name ?? ""
        var desired = windows.map { window in
            var state = LastLessonActivityAttributes.ContentState(window: window)
            state.referenceDate = max(now, window.visibleFrom)
            state.tableName = tableName
            state.islandEnabled = islandEnabled
            return Request(id: window.id, state: state)
        }
        let day = WidgetSchedule.daySchedule(data: data, at: now)
        if enabled && allowed && allLessons && day.lessons.count > 1,
           let first = WideLessonPlanner.remaining(data: data, at: now).first {
            var state = LastLessonActivityAttributes.ContentState(window: first)
            state.following = Array(WideLessonPlanner.remaining(data: data, at: now).dropFirst())
            state.remainingCount = day.lessons.count
            state.referenceDate = now
            state.tableName = tableName
            state.islandEnabled = islandEnabled
            desired.append(Request(id: "daily-\(data.selectedID)-\(day.day.timeIntervalSince1970)", state: state))
        }
        issue = enabled && !allowed ? "请在系统设置中允许 YIClass 的实时活动。" : nil
        var retained: [Activity<LastLessonActivityAttributes>] = []
        for activity in Activity<LastLessonActivityAttributes>.activities {
            if let request = desired.first(where: { $0.id == activity.attributes.windowID }),
               activity.activityState != .ended, activity.activityState != .dismissed {
                // Update content and island preference in place; never recreate
                // an activity merely because a setting or course changed.
                if activity.content.state != request.state {
                    await activity.update(ActivityContent(state: request.state, staleDate: request.state.window.end))
                }
                retained.append(activity)
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        for request in desired where !retained.contains(where: { $0.attributes.windowID == request.id }) {
            guard UIApplication.shared.applicationState == .active else { break }
            do {
                let attributes = LastLessonActivityAttributes(windowID: request.id)
                let content = ActivityContent(state: request.state, staleDate: request.state.window.end)
                let activity: Activity<LastLessonActivityAttributes>
                if request.start > Date() {
                    activity = try Activity.request(attributes: attributes, content: content, pushType: nil,
                        style: .standard,
                        alertConfiguration: AlertConfiguration(title: "最后一节课", body: "\(request.state.window.name)", sound: .default),
                        start: request.start)
                } else {
                    activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                }
                retained.append(activity)
            } catch { issue = "实时活动未能启用，普通锁屏组件仍可使用：\(error.localizedDescription)" }
        }
        do {
            try WideLessonBridge.write(retained.filter { !$0.attributes.windowID.hasPrefix("daily-") }
                .map { .init(activityID: $0.id, window: $0.content.state.window) })
        } catch { issue = error.localizedDescription }
        let taskItems = enabled && allowed && scheduledTasks ? AgendaActivityPlanner.tasks(agenda: agenda, at: now) : []
        await reconcileTasks(taskItems, at: now)
        WidgetCenter.shared.reloadAllTimelines()
        var dates = windows.flatMap { [$0.visibleFrom, $0.start, $0.end] }
        if allLessons { dates += day.lessons.flatMap { [$0.start, $0.end] } }
        dates += taskItems.flatMap { [$0.visibleFrom, $0.end.addingTimeInterval(-300), $0.end] }
        dates += windows.map { $0.end.addingTimeInterval(-300) }
        if let next = dates.filter({ $0 > Date() }).min() {
            boundary = Task {
                do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow))) }
                catch { return }
                self.refresh(data: data)
            }
        }
    }
    private func reconcileTasks(_ items: [AgendaActivityItem], at now: Date) async {
        var retained = Set<String>()
        for activity in Activity<AgendaTaskActivityAttributes>.activities {
            guard let item = items.first(where: { $0.id == activity.attributes.itemID }),
                  activity.activityState != .ended, activity.activityState != .dismissed,
                  retained.insert(item.id).inserted else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            let state = AgendaTaskActivityAttributes.ContentState(item: item,
                referenceDate: max(now, item.visibleFrom), islandEnabled: islandEnabled)
            await activity.update(ActivityContent(state: state, staleDate: item.end))
        }
        for item in items where !retained.contains(item.id) {
            guard UIApplication.shared.applicationState == .active else { break }
            let state = AgendaTaskActivityAttributes.ContentState(item: item,
                referenceDate: max(now, item.visibleFrom), islandEnabled: islandEnabled)
            let content = ActivityContent(state: state, staleDate: item.end)
            do {
                if item.visibleFrom > Date() {
                    _ = try Activity<AgendaTaskActivityAttributes>.request(
                        attributes: .init(itemID: item.id), content: content, pushType: nil, style: .standard,
                        alertConfiguration: AlertConfiguration(title: "日程安排", body: "\(item.title)", sound: .default),
                        start: item.visibleFrom)
                } else {
                    _ = try Activity<AgendaTaskActivityAttributes>.request(
                        attributes: .init(itemID: item.id), content: content, pushType: nil)
                }
            } catch { issue = "日程实时活动未能启用：\(error.localizedDescription)" }
        }
    }

}

import Foundation
import Observation
import UserNotifications
import YIClassCore

extension Notification.Name {
    static let lessonReminderOpened = Notification.Name("YIClass.lessonReminderOpened")
}

@MainActor @Observable final class LessonReminderManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LessonReminderManager()
    private(set) var enabled = UserDefaults.standard.bool(forKey: "reminders.enabled")
    private(set) var leadMinutes = UserDefaults.standard.object(forKey: "reminders.minutes") as? Int ?? 10
    private(set) var authorization = UNAuthorizationStatus.notDetermined
    private(set) var requesting = false
    private(set) var pendingCount = 0
    private(set) var issue: String?
    private var worker: Task<Void, Never>?
    private let center = UNUserNotificationCenter.current()

    func start(data: AppData) async {
        center.delegate = self
        if !UserDefaults.standard.bool(forKey: "reminders.permissionAsked") {
            await setEnabled(true, data: data)
        } else { refresh(data: data) }
    }
    func setEnabled(_ value: Bool, data: AppData) async {
        guard !requesting else { return }
        requesting = true
        defer { requesting = false }
        do {
            if value {
                UserDefaults.standard.set(true, forKey: "reminders.permissionAsked")
                let settings = await center.notificationSettings()
                if settings.authorizationStatus == .notDetermined {
                    enabled = try await center.requestAuthorization(options: [.alert, .sound])
                } else { enabled = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) }
            } else { enabled = false }
            UserDefaults.standard.set(enabled, forKey: "reminders.enabled")
            issue = nil
        } catch { enabled = false; UserDefaults.standard.set(false, forKey: "reminders.enabled"); issue = error.localizedDescription }
        refresh(data: data)
    }
    func setLeadMinutes(_ value: Int, data: AppData) {
        guard [0, 5, 10, 15, 30].contains(value) else { return }
        leadMinutes = value; UserDefaults.standard.set(value, forKey: "reminders.minutes")
        refresh(data: data)
    }
    func refresh(data: AppData) {
        let previous = worker
        previous?.cancel()
        let active = enabled, lead = leadMinutes
        // Serialize replacement jobs. A cancelled UN add may still finish;
        // the next job must wait for it before removing stale requests.
        worker = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await replaceRequests(data: data, enabled: active, minutes: lead)
        }
    }
    private func replaceRequests(data: AppData, enabled: Bool, minutes: Int) async {
        let settings = await center.notificationSettings()
        guard !Task.isCancelled else { return }
        authorization = settings.authorizationStatus
        let existing = await center.pendingNotificationRequests()
        guard !Task.isCancelled else { return }
        center.removePendingNotificationRequests(withIdentifiers: existing.filter { $0.identifier.hasPrefix(LessonReminderPlanner.identifierPrefix) }.map(\.identifier))
        pendingCount = 0
        guard enabled, [.authorized, .provisional, .ephemeral].contains(authorization) else { return }
        let reminders = await Task.detached(priority: .utility) {
            LessonReminderPlanner.reminders(data: data, leadMinutes: minutes)
        }.value
        guard !Task.isCancelled else { return }
        do {
            for reminder in reminders {
                try Task.checkCancellation()
                let content = UNMutableNotificationContent()
                content.title = reminder.title; content.body = reminder.body; content.sound = .default
                content.threadIdentifier = "yiclass.lessons"
                content.userInfo = ["tableID": reminder.tableID.uuidString, "courseID": reminder.courseID.uuidString]
                var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
                components.timeZone = Calendar.current.timeZone
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
                pendingCount += 1
            }
            issue = nil
        } catch is CancellationError { }
        catch { issue = "上课提醒未全部安排：\(error.localizedDescription)" }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let tableID = response.notification.request.content.userInfo["tableID"] as? String ?? ""
        await MainActor.run { NotificationCenter.default.post(name: .lessonReminderOpened, object: nil, userInfo: ["tableID": tableID]) }
    }
}

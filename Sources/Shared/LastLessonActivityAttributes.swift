#if os(iOS)
import ActivityKit
import Foundation
import YIClassCore

struct LastLessonActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let window: WideLessonWindow
    }
    let windowID: String
}

/// Only successful ActivityKit requests suppress the corresponding narrow card.
/// Resolve all accessible signing groups, just like the shared timetable.
enum WideLessonBridge {
    struct Record: Codable {
        let activityID: String
        let window: WideLessonWindow
    }
    static func write(_ records: [Record]) throws {
        let bytes = try JSONEncoder().encode(records)
        var written = false
        for container in SharedGroup.containers() {
            do {
                try bytes.write(to: container.url.appendingPathComponent("wide-lesson.json"),
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                written = true
            } catch { continue }
        }
        if !written { throw AppFailure("末课宽幅状态未能同步。") }
    }
    static func covers(_ lesson: ScheduledLesson, tableID: UUID, at date: Date) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        let activities = Activity<LastLessonActivityAttributes>.activities
            .filter { $0.activityState != .ended && $0.activityState != .dismissed }
        let files = SharedGroup.containers().map { $0.url.appendingPathComponent("wide-lesson.json") }.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
            ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for file in files {
            guard let bytes = try? Data(contentsOf: file), let records = try? JSONDecoder().decode([Record].self, from: bytes) else { continue }
            return records.contains { record in
                let w = record.window
                return w.tableID == tableID && w.courseID == lesson.course.id && w.start == lesson.start && w.end == lesson.end &&
                    w.name == lesson.course.name && w.location == lesson.course.location && w.visibleFrom <= date && date < w.end &&
                    activities.contains { $0.id == record.activityID && $0.content.state.window == w }
            }
        }
        return false
    }
}
#endif

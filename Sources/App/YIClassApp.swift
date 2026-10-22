import SwiftUI
import YIClassCore

@main struct YIClassApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("theme.accent") private var accent = 0xFF637EEA
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    var body: some Scene {
        WindowGroup {
            Group {
                if store.loadFailed {
                    ContentUnavailableView {
                        Label("无法读取课表", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("本地原文件已保留。可恢复上次备份，或先分享原文件以便排查。")
                    } actions: {
                        Button("恢复上次备份") { store.recoverBackup() }
                        ShareLink("导出原文件", item: store.damagedFile)
                    }
                } else { RootView() }
            }
            .task {
                if !store.loadFailed { await LessonReminderManager.shared.start(data: store.data) }
                if !store.loadFailed { LastLessonActivityManager.shared.refresh(data: store.data) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                if !store.loadFailed { LessonReminderManager.shared.refresh(data: store.data) }
                if !store.loadFailed { LastLessonActivityManager.shared.refresh(data: store.data) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.syncWidgets() }
            }
            .environment(store)
            .tint(Color(argb: UInt32(clamping: accent)))
            .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).colorScheme)
            .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("好", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var selected = 0
    var body: some View {
        TabView(selection: $selected) {
            Tab("课表", systemImage: "calendar", value: 0) { ScheduleView() }
            Tab("助手", systemImage: "sparkles", value: 1) { AssistantView() }
            Tab("待办", systemImage: "checklist", value: 3) { TodoView() }
            Tab("设置", systemImage: "slider.horizontal.3", value: 2) { SettingsView() }
        }
        .onOpenURL { url in if url.scheme == "yiclass" { selected = 0 } }
        .onReceive(NotificationCenter.default.publisher(for: .lessonReminderOpened)) { notification in
            selected = 0
            if let rawID = notification.userInfo?["tableID"] as? String, let id = UUID(uuidString: rawID),
               store.data.timetables.contains(where: { $0.id == id }), id != store.table.id {
                store.perform { try store.select(id) }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

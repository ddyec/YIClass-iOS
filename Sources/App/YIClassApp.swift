import SwiftUI
import YIClassCore

@main struct YIClassApp: App {
    @State private var store = AppStore()
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
            .environment(store)
            .tint(.indigo)
            .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).colorScheme)
            .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("好", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("课表", systemImage: "calendar") { ScheduleView() }
            Tab("助手", systemImage: "sparkles") { AssistantView() }
            Tab("设置", systemImage: "slider.horizontal.3") { SettingsView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

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
    @AppStorage("theme.accent") private var accent = 0xFF637EEA
    @State private var selected = 0
    @State private var assistantPresented = false
    @State private var bottomNavigationHeight: CGFloat = 72
    @State private var bottomNavigationFrame: CGRect?
    @State private var navigationMinimized = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            TabView(selection: $selected) {
                Tab("课表", systemImage: "calendar", value: 0) {
                    ScheduleView(bottomNavigationInset: bottomNavigationHeight, bottomNavigationTop: bottomNavigationFrame?.minY)
                        .toolbar(.hidden, for: .tabBar)
                }
                Tab("待办", systemImage: "checklist", value: 3) {
                    TodoView().safeAreaPadding(.bottom, bottomNavigationHeight)
                        .toolbar(.hidden, for: .tabBar)
                }
                Tab("设置", systemImage: "slider.horizontal.3", value: 2) {
                    SettingsView().safeAreaPadding(.bottom, bottomNavigationHeight)
                        .toolbar(.hidden, for: .tabBar)
                }
            }
            .onOpenURL { url in if url.scheme == "yiclass" { selected = url.host == "todos" ? 3 : 0 } }
            .onReceive(NotificationCenter.default.publisher(for: .lessonReminderOpened)) { notification in
                selected = 0
                if let rawID = notification.userInfo?["tableID"] as? String, let id = UUID(uuidString: rawID),
                   store.data.timetables.contains(where: { $0.id == id }), id != store.table.id {
                    store.perform { try store.select(id) }
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .environment(\.minimizeFloatingNavigation, { minimized in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) {
                    navigationMinimized = minimized
                }
            })
            .onChange(of: selected) { _, _ in navigationMinimized = false }
            .overlay(alignment: .bottom) {
                // Keep the bar floating. Only scrolling content and the evening
                // control account for its measured height; no navigation row.
                bottomNavigation.padding(.horizontal, 18).padding(.top, 8)
                    .padding(.bottom, max(8, geometry.safeAreaInsets.bottom - 8))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        bottomNavigationHeight = $0.height
                        bottomNavigationFrame = $0
                    }
            }
            // Apply to the content AND overlay so the custom bar reaches the
            // screen bottom, with home clearance measured by the outer reader.
            .ignoresSafeArea(.container, edges: .bottom)
            .sheet(isPresented: $assistantPresented) {
                AssistantView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(32)
            }
        }
    }
    private var bottomNavigation: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                NativeNavigationControl(selection: $selected, minimized: navigationMinimized,
                    accent: Color(argb: UInt32(clamping: accent))) {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) { navigationMinimized = false }
                    }
                    .frame(maxWidth: navigationMinimized ? 60 : .infinity)
                    .frame(height: 60)
                if navigationMinimized { Spacer(minLength: 12) }
                Button { assistantPresented = true } label: {
                    AssistantLogo(size: 34)
                        // Match the 50pt item + 5pt capsule padding on each side.
                        .frame(width: 60, height: 60)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("AI 助手")
                .accessibilityIdentifier("ai-assistant-button")
            }
        }
        .accessibilityIdentifier("bottom-navigation")
    }
}

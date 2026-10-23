import SwiftUI
import UIKit

/// UIKit owns the entire bar: material, capsule shape, selection lens, pan
/// selection, the separate trailing entry and scroll minimization.
@MainActor struct NativeTabNavigation<Schedule: View, Todos: View, Settings: View>: UIViewControllerRepresentable {
    @Binding var selection: Int
    var accent: Color
    var openAssistant: () -> Void
    var schedule: Schedule
    var todos: Todos
    var settings: Settings
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UITabBarController {
        let controller = UITabBarController()
        controller.delegate = context.coordinator
        controller.mode = .tabBar
        controller.tabBarMinimizeBehavior = .onScrollDown
        controller.tabs = context.coordinator.tabs
        updateUIViewController(controller, context: context)
        return controller
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.schedule.rootView = AnyView(schedule.tint(accent))
        coordinator.todos.rootView = AnyView(todos.tint(accent))
        coordinator.settings.rootView = AnyView(settings.tint(accent))
        controller.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        controller.view.tintColor = UIColor(accent)
        controller.tabBar.unselectedItemTintColor = .label
        if let tab = coordinator.tabs.first(where: { $0.identifier == String(selection) }),
           controller.selectedTab !== tab {
            controller.selectedTab = tab
        }
    }

    @MainActor final class Coordinator: NSObject, UITabBarControllerDelegate {
        var parent: NativeTabNavigation
        let schedule: UIHostingController<AnyView>
        let todos: UIHostingController<AnyView>
        let settings: UIHostingController<AnyView>
        let assistant: UISearchTab
        let tabs: [UITab]

        init(_ parent: NativeTabNavigation) {
            self.parent = parent
            // Keep each hosting controller and its NavigationStack alive when
            // switching tabs, changing the theme or opening the assistant.
            let scheduleHost = UIHostingController(rootView: AnyView(parent.schedule.tint(parent.accent)))
            let todosHost = UIHostingController(rootView: AnyView(parent.todos.tint(parent.accent)))
            let settingsHost = UIHostingController(rootView: AnyView(parent.settings.tint(parent.accent)))
            schedule = scheduleHost
            todos = todosHost
            settings = settingsHost
            let assistantTab = UISearchTab { _ in UIViewController() }
            assistantTab.title = "AI 助手"
            assistantTab.image = UIImage(named: "AssistantLogo")?.withRenderingMode(.alwaysTemplate)
            assistantTab.accessibilityIdentifier = "ai-assistant-button"
            assistantTab.automaticallyActivatesSearch = false
            assistant = assistantTab
            tabs = [
                UITab(title: "课表", image: UIImage(systemName: "calendar"), identifier: "0") { _ in scheduleHost },
                UITab(title: "待办", image: UIImage(systemName: "checklist"), identifier: "3") { _ in todosHost },
                UITab(title: "设置", image: UIImage(systemName: "slider.horizontal.3"), identifier: "2") { _ in settingsHost },
                assistantTab
            ]
            super.init()
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            guard tab !== assistant else {
                // Public delegate veto: open the drawer without selecting the
                // search tab, activating a search field or replacing the page.
                parent.openAssistant()
                return false
            }
            return true
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
            if let value = Int(selectedTab.identifier) { parent.selection = value }
        }
    }
}

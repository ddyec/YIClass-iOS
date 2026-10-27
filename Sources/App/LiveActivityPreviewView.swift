import ActivityKit
import Observation
import SwiftUI
import YIClassCore

private enum ActivityPreviewScenario: String, CaseIterable, Identifiable {
    case idle = "空闲", upcoming = "未开始", ongoing = "进行中", breakTime = "课间", ending = "即将结束"
    var id: String { rawValue }
}

struct LiveActivityPreviewView: View {
    @State private var scenario = ActivityPreviewScenario.ongoing
    @State private var kind = AgendaActivityItem.Kind.course
    @State private var longTitle = false
    @State private var anchor = Date()
    @State private var controller = LiveActivityPreviewController.shared

    private var item: AgendaActivityItem {
        let title = kind == .course ? (longTitle ? "习近平新时代中国特色社会主义思想概论与实践课程" : "大学英语（一）") :
            (longTitle ? "完成实验报告并整理实验数据，提交课程平台" : "完成实验报告")
        let start = anchor.addingTimeInterval(scenario == .upcoming ? 60 :
            (scenario == .ending || scenario == .breakTime ? -600 : -60))
        let end = anchor.addingTimeInterval(scenario == .ending ? 45 : 600)
        let firstEnd = anchor.addingTimeInterval(scenario == .ending ? -300 : scenario == .breakTime ? -30 : 240)
        let secondStart = anchor.addingTimeInterval(scenario == .ending ? -240 : scenario == .breakTime ? 60 : 300)
        let periods: [AgendaActivityPeriod]? = kind == .course ? [
            .init(number: 1, start: start, end: firstEnd),
            .init(number: 2, start: secondStart, end: end)
        ] : nil
        return AgendaActivityItem(id: "preview", kind: kind, title: "测试 · \(title)",
            location: kind == .course ? (longTitle ? "蘭榕楼 2 号多媒体教室（东区）" : "致明楼 501") : "",
            start: start, end: end, periods: periods)
    }

    var body: some View {
        Form {
            Section {
                Picker("状态", selection: $scenario) {
                    ForEach(ActivityPreviewScenario.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("内容", selection: $kind) {
                    Text("课程").tag(AgendaActivityItem.Kind.course)
                    Text("待办").tag(AgendaActivityItem.Kind.task)
                }
                Toggle("使用长标题测试边界", isOn: $longTitle)
            }
            Section("样式预览") {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if scenario == .idle || item.end <= context.date {
                        Text(scenario == .idle ? "暂无进行中的安排" : "测试已结束")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 64)
                    } else {
                        AgendaActivityIslandPreview(item: item, referenceDate: context.date)
                            .background(.black, in: RoundedRectangle(cornerRadius: 24))
                    }
                }
            }
            Section {
                Button(scenario == .idle ? "应用空闲状态（结束测试）" : "应用到锁屏与灵动岛") {
                    Task {
                        if scenario == .idle { await controller.stop() }
                        else { await controller.show(item) }
                    }
                }.disabled(controller.busy)
                if scenario == .upcoming {
                    Button("模拟开始，启动倒计时") {
                        anchor = Date()
                        scenario = .ongoing
                        Task { await controller.show(item) }
                    }.disabled(controller.busy)
                }
                Button("结束测试", role: .destructive) {
                    Task { await controller.stop() }
                }.disabled(controller.busy)
            } footer: {
                Text("应用后可返回桌面或锁屏查看。未开始状态可点“模拟开始”切换为倒计时；其他状态也可随时切换后重新应用。测试不修改课程或待办，结束测试不影响真实活动。")
            }
            if let message = controller.message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("实时活动样式测试")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenario) { _, _ in anchor = Date() }
    }
}

/// One reusable test activity, isolated from canonical placements and course bridges.
@MainActor @Observable private final class LiveActivityPreviewController {
    static let shared = LiveActivityPreviewController()
    private(set) var busy = false
    private(set) var message: String?

    func show(_ item: AgendaActivityItem) async {
        guard !busy else { return }
        guard LastLessonActivityManager.shared.enabled,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "请先开启锁屏实时活动，并在系统设置中允许实时活动。"
            return
        }
        busy = true
        defer { busy = false }
        let content = ActivityContent(state: AgendaTaskActivityAttributes.ContentState(item: item,
            referenceDate: Date(), islandEnabled: LastLessonActivityManager.shared.islandEnabled), staleDate: item.end)
        do {
            var updated = false
            for activity in Activity<AgendaTaskActivityAttributes>.activities
                where activity.attributes.itemID.hasPrefix("preview-") {
                if !updated && (activity.activityState == .active || activity.activityState == .stale) {
                    await activity.update(content)
                    updated = true
                } else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            if !updated {
                _ = try Activity<AgendaTaskActivityAttributes>.request(attributes: .init(itemID: "preview-\(UUID())"),
                    content: content, pushType: nil)
            }
            message = "测试已应用，可在锁屏查看。灵动岛是否显示遵循设置中的活动内容开关。"
        } catch { message = "测试活动未能启动：\(error.localizedDescription)" }
    }

    func stop() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        for activity in Activity<AgendaTaskActivityAttributes>.activities where activity.attributes.itemID.hasPrefix("preview-") {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        message = "测试活动已结束。"
    }
}

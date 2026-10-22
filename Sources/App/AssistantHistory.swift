import Foundation
import SwiftUI
import YIClassCore

struct AssistantHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onOpen: (ConversationRecord) -> Void
    let onNew: () -> Void
    let onRestored: () -> Void
    var body: some View {
        NavigationStack {
            List {
                if let issue = store.historyIssue { Text(issue).font(.footnote).foregroundStyle(.secondary) }
                Section("对话") {
                    if store.conversations.isEmpty { Text("暂无历史对话").foregroundStyle(.secondary) }
                    ForEach(store.conversations) { conversation in
                        Button { onOpen(conversation) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title).foregroundStyle(Color.primary).lineLimit(1)
                                Text(conversation.date, format: .dateTime.month().day().hour().minute())
                                    .font(.caption).foregroundStyle(Color.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                Section("课表恢复记录") {
                    if store.revisions.isEmpty { Text("修改课表后会保留恢复记录").foregroundStyle(.secondary) }
                    ForEach(store.revisions) { revision in
                        NavigationLink {
                            RevisionReviewView(revision: revision, onRestored: onRestored)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(revision.title) · 更改前").lineLimit(2)
                                Text(revision.date, format: .dateTime.month().day().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("历史记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("新对话", systemImage: "square.and.pencil", action: onNew) }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}

private struct RevisionReviewView: View {
    @Environment(AppStore.self) private var store
    let revision: LibraryRevision
    let onRestored: () -> Void
    @State private var confirming = false
    var body: some View {
        List {
            Section {
                Text(revision.title).font(.headline)
                Text(revision.date, format: .dateTime.year().month().day().hour().minute())
                Text("恢复此操作前的全部课表和统一课节时间，当前状态也会保存为恢复记录。")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent("统一课节", value: "\(revision.data.timeProfile.periods.count) 节")
            }
            ForEach(revision.data.timetables) { table in
                Section(table.name) {
                    ForEach(table.courses) { course in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(course.name)
                            if !course.location.isEmpty { Text(course.location).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section { Button("恢复到此状态") { confirming = true } }
        }.navigationTitle("查看恢复记录").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("恢复全部课表和统一时间到此记录？当前状态会保留。", isPresented: $confirming, titleVisibility: .visible) {
                Button("恢复") { store.perform { try store.restoreRevision(revision.id); onRestored() } }
            }
    }
}

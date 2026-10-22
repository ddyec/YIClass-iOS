import Foundation
import YIClassCore

struct ConversationRecord: Codable, Identifiable {
    var id: UUID
    var title: String
    var date: Date
    var messages: [ChatMessage]
    var modelHistory: [ChatMessage]
    var importing: Bool
    var importTable: Timetable?
}
struct LibraryRevision: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var title: String
    var data: AppData
}
struct AssistantArchive: Codable {
    var conversations: [ConversationRecord] = []
    var revisions: [LibraryRevision] = []
}


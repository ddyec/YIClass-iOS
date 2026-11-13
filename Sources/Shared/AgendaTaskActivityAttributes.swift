#if os(iOS)
import ActivityKit
import Foundation
import YIClassCore

struct AgendaTaskActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let item: AgendaActivityItem
        let referenceDate: Date
        let islandEnabled: Bool
    }
    let itemID: String
}
#endif

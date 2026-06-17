import Foundation
import SwiftData

enum MainDestination: Hashable {
    case inbox
    case today
    case upcoming
    case category(PersistentIdentifier)

    var title: String {
        switch self {
        case .inbox: "All"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .category: "Category"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "square.stack.3d.up"
        case .today: "calendar"
        case .upcoming: "calendar.badge.clock"
        case .category: "number"
        }
    }
}

enum DetailDisplayMode: String, CaseIterable {
    case board = "Board"
    case list = "List"
    case gantt = "Gantt"
}

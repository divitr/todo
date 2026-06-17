import Foundation
import SwiftData

@Model
final class TaskLink {
    var uuid: UUID
    var kindRaw: String

    var fromTask: TaskItem?

    var toTask: TaskItem?

    init(kind: TaskLinkKind = .finishToStart, from: TaskItem?, to: TaskItem?) {
        self.uuid = UUID()
        self.kindRaw = kind.rawValue
        self.fromTask = from
        self.toTask = to
    }

    var kind: TaskLinkKind {
        get { TaskLinkKind(rawValue: kindRaw) ?? .finishToStart }
        set { kindRaw = newValue.rawValue }
    }
}

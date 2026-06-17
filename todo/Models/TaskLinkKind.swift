import Foundation

enum TaskLinkKind: String, CaseIterable, Identifiable, Codable {
    case finishToStart = "FS"
    case startToStart = "SS"
    case finishToFinish = "FF"
    case startToFinish = "SF"

    var id: String { rawValue }

    var shortCode: String { rawValue }

    var label: String {
        switch self {
        case .finishToStart: "Finish → Start"
        case .startToStart: "Start → Start"
        case .finishToFinish: "Finish → Finish"
        case .startToFinish: "Start → Finish"
        }
    }

    var detail: String {
        switch self {
        case .finishToStart: "This starts after the other task finishes"
        case .startToStart: "Both tasks start together (this not earlier)"
        case .finishToFinish: "Both tasks finish together (this not earlier)"
        case .startToFinish: "This finishes when the other starts"
        }
    }
}

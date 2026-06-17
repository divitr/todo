import Foundation
import SwiftData
import SwiftUI

@Model
final class TaskItem {
    var uuid: UUID
    var title: String
    var notes: String
    var isComplete: Bool
    var sortOrder: Int
    var createdAt: Date

    var durationDays: Double
    var useManualStart: Bool
    var manualStart: Date?
    var dueDate: Date?
    var predecessor: TaskItem?
    var project: Project?

    var parent: TaskItem?

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.parent)
    var subtasks: [TaskItem] = []

    @Relationship(deleteRule: .cascade, inverse: \TaskLink.fromTask)
    var outgoingLinks: [TaskLink] = []

    @Relationship(deleteRule: .cascade, inverse: \TaskLink.toTask)
    var incomingLinks: [TaskLink] = []

    var scheduledStart: Date?
    var scheduledEnd: Date?

    var priority: Int
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var hasDueTime: Bool
    var reminderAt: Date?

    var calendarEventID: String?
    var calendarEventTitle: String?
    var calendarEventCalendarName: String?
    var calendarEventStart: Date?
    var calendarEventEnd: Date?
    var calendarLastSyncedAt: Date?
    var calendarColorRed: Double = 0.38
    var calendarColorGreen: Double = 0.48
    var calendarColorBlue: Double = 0.72
    var calendarColorStored: Bool = false
    var scheduleWarningFingerprint: String?
    var planForTodayStored: Bool = false

    init(
        title: String,
        durationDays: Double = 1,
        sortOrder: Int = 0,
        dueDate: Date? = nil,
        project: Project? = nil,
        parent: TaskItem? = nil
    ) {
        self.uuid = UUID()
        self.title = title
        self.notes = ""
        self.isComplete = false
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.durationDays = max(durationDays, Self.minDurationDays)
        self.useManualStart = false
        self.manualStart = nil
        self.dueDate = dueDate
        self.project = project
        self.parent = parent
        self.priority = 0
        self.reminderEnabled = false
        self.reminderHour = 9
        self.reminderMinute = 0
        self.hasDueTime = false
        self.reminderAt = nil
    }

    var isSubtask: Bool { parent != nil }

    var root: TaskItem {
        var node: TaskItem = self
        while let p = node.parent { node = p }
        return node
    }

    var sortedSubtasks: [TaskItem] {
        subtasks.sorted { $0.sortOrder < $1.sortOrder }
    }

    var displayOrderedSubtasks: [TaskItem] {
        let open = sortedSubtasks.filter { !$0.isComplete }
        let done = sortedSubtasks.filter { $0.isComplete }
        return open + done
    }

    var priorityLabel: String? {
        Self.priorityName(for: priority)
    }

    static func priorityName(for value: Int) -> String? {
        switch value {
        case 1: "P4"
        case 2: "P3"
        case 3: "P2"
        case 4: "P1"
        default: nil
        }
    }

    var dayAnchor: Date? {
        guard let dueDate else { return nil }
        return Calendar.current.startOfDay(for: dueDate)
    }

    var effectiveStart: Date {
        scheduledStart ?? Calendar.current.startOfDay(for: dueDate ?? .now)
    }

    var effectiveEnd: Date {
        if let scheduledEnd { return scheduledEnd }
        return Self.inclusiveScheduleEnd(start: effectiveStart, durationDays: durationDays)
    }

    static func inclusiveScheduleEnd(
        start: Date,
        durationDays: Double,
        calendar: Calendar = .current
    ) -> Date {
        let startDay = calendar.startOfDay(for: start)
        let span = max(Int(ceil(durationDays)), 1)
        return calendar.date(byAdding: .day, value: span - 1, to: startDay)!
    }

    static func inclusiveScheduleStart(
        end: Date,
        durationDays: Double,
        calendar: Calendar = .current
    ) -> Date {
        let endDay = calendar.startOfDay(for: end)
        let span = max(Int(ceil(durationDays)), 1)
        return calendar.date(byAdding: .day, value: -(span - 1), to: endDay)!
    }

    var reminderTimeLabel: String {
        let hour12 = reminderHour % 12
        let h = hour12 == 0 ? 12 : hour12
        let m = String(format: "%02d", reminderMinute)
        let suffix = reminderHour < 12 ? "AM" : "PM"
        return "\(h):\(m) \(suffix)"
    }

    var isGanttEligible: Bool {
        guard !isComplete else { return false }
        guard durationDays > 0 else { return false }
        return dueDate != nil || useManualStart || predecessor != nil || !incomingLinks.isEmpty
    }

    var sortedIncomingLinks: [TaskLink] {
        incomingLinks.sorted { ($0.fromTask?.title ?? "") < ($1.fromTask?.title ?? "") }
    }
}

extension TaskItem {
    static let minDurationDays: Double = 15.0 / (60 * 24)
    static let defaultReminderHour = 9
    static let defaultReminderMinute = 0

    var hasCalendarLink: Bool {
        calendarEventID != nil
    }

    var calendarAccentColor: Color? {
        guard hasCalendarLink, calendarColorStored else { return nil }
        return Color(red: calendarColorRed, green: calendarColorGreen, blue: calendarColorBlue)
    }

    func migrateLegacyPredecessorIfNeeded(in context: ModelContext) {
        guard let pred = predecessor, incomingLinks.isEmpty else { return }
        let link = TaskLink(kind: .finishToStart, from: pred, to: self)
        incomingLinks.append(link)
        context.insert(link)
        predecessor = nil
    }
}

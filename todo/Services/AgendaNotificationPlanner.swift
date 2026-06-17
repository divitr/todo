import Foundation
import UserNotifications

enum NotificationPreferences {
    static let morningAgendaHour = 8
    static let morningAgendaMinute = 0
    static let overdueNudgeHour = 20
    static let overdueNudgeMinute = 0
    static let agendaHorizonDays = 14
    static let maxAgendaTitles = 5
}

enum AgendaNotificationPlanner {
    static func morningAgendaIdentifier(for day: Date, calendar: Calendar = .current) -> String {
        let dayStart = calendar.startOfDay(for: day)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "todo.agenda.\(formatter.string(from: dayStart))"
    }

    static func plannedMorningAgendaIdentifiers(calendar: Calendar = .current) -> [String] {
        let today = calendar.startOfDay(for: .now)
        return (0..<NotificationPreferences.agendaHorizonDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return morningAgendaIdentifier(for: day, calendar: calendar)
        }
    }

    static func morningAgendaFireDate(for day: Date, calendar: Calendar = .current) -> Date? {
        let dayStart = calendar.startOfDay(for: day)
        return calendar.date(
            bySettingHour: NotificationPreferences.morningAgendaHour,
            minute: NotificationPreferences.morningAgendaMinute,
            second: 0,
            of: dayStart
        )
    }

    static func buildMorningAgendaContent(for day: Date, tasks: [TaskItem]) -> UNMutableNotificationContent {
        let calendar = Calendar.current
        let agendaTasks = TaskFilters.agenda(on: day, tasks: tasks, calendar: calendar)
        let overdue = calendar.isDateInToday(day) ? TaskFilters.overdue(tasks, calendar: calendar) : []

        let blocked = calendar.isDateInToday(day)
            ? agendaTasks.filter(\.isBlockedToday)
            : []
        let dueOnDay = agendaTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: day)
                && !blocked.contains(where: { $0.uuid == task.uuid })
        }

        let content = UNMutableNotificationContent()
        content.sound = .default

        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        let dayLabel = weekday.string(from: day)

        if agendaTasks.isEmpty && overdue.isEmpty {
            content.title = calendar.isDateInToday(day) ? "All clear today" : "\(dayLabel): nothing planned"
            content.body = "No tasks on your agenda in todo."
            return content
        }

        content.title = calendar.isDateInToday(day) ? "Today’s agenda" : "\(dayLabel) agenda"

        var summary: [String] = []
        if !blocked.isEmpty { summary.append("\(blocked.count) blocked") }
        if !dueOnDay.isEmpty { summary.append("\(dueOnDay.count) due") }
        if !overdue.isEmpty { summary.append("\(overdue.count) overdue") }
        content.subtitle = summary.joined(separator: " · ")

        var lines: [String] = []
        for task in (blocked + dueOnDay).prefix(NotificationPreferences.maxAgendaTitles) {
            let title = task.title.isEmpty ? "Untitled" : task.title
            lines.append("• \(title)")
        }
        let remaining = agendaTasks.count - min(agendaTasks.count, NotificationPreferences.maxAgendaTitles)
        if remaining > 0 {
            lines.append("+\(remaining) more")
        }
        if !overdue.isEmpty, lines.count < NotificationPreferences.maxAgendaTitles + 1 {
            lines.append("\(overdue.count) overdue from earlier")
        }
        content.body = lines.joined(separator: "\n")

        return content
    }

    static func overdueFireDate(for task: TaskItem, calendar: Calendar = .current) -> Date? {
        guard !task.isComplete, let due = task.dueDate else { return nil }
        let dueDay = calendar.startOfDay(for: due)
        return calendar.date(
            bySettingHour: NotificationPreferences.overdueNudgeHour,
            minute: NotificationPreferences.overdueNudgeMinute,
            second: 0,
            of: dueDay
        )
    }

    static func buildOverdueContent(for task: TaskItem) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Overdue"
        let name = task.title.isEmpty ? "Untitled" : task.title
        if let label = DueDateFormatting.taskDueLabel(task) {
            content.body = "\(name) was due \(label)."
        } else {
            content.body = "\(name) is past its due date."
        }
        content.sound = .default
        return content
    }
}

enum OverdueNudgeTracker {
    private static let storageKey = "todo.overdueNudgeSentKeys"

    static func contains(_ key: String) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? []).contains(key)
    }

    static func mark(_ key: String) {
        var keys = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
        keys.insert(key)
        UserDefaults.standard.set(Array(keys), forKey: storageKey)
    }

    static func remove(for task: TaskItem, calendar: Calendar = .current) {
        guard let due = task.dueDate else { return }
        let dueDay = calendar.startOfDay(for: due)
        let key = notificationKey(taskUUID: task.uuid, dueDay: dueDay)
        var keys = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
        keys = keys.filter { !$0.hasPrefix("\(task.uuid.uuidString)|") }
        UserDefaults.standard.set(Array(keys), forKey: storageKey)
    }

    static func notificationKey(taskUUID: UUID, dueDay: Date) -> String {
        "\(taskUUID.uuidString)|\(Int(dueDay.timeIntervalSince1970))"
    }

    static func notificationKey(for task: TaskItem, calendar: Calendar = .current) -> String? {
        guard let due = task.dueDate else { return nil }
        return notificationKey(taskUUID: task.uuid, dueDay: calendar.startOfDay(for: due))
    }
}

import Foundation

enum TaskFilters {
    static func active(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { !$0.isComplete }
    }

    static func all(_ tasks: [TaskItem]) -> [TaskItem] {
        active(tasks)
    }

    static func inbox(_ tasks: [TaskItem]) -> [TaskItem] {
        all(tasks)
    }

    static func dueToday(_ tasks: [TaskItem], calendar: Calendar = .current) -> [TaskItem] {
        active(tasks).filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDateInToday(due)
        }
    }

    static func blockedToday(_ tasks: [TaskItem]) -> [TaskItem] {
        active(tasks).filter { $0.isBlockedToday }
    }

    static func today(_ tasks: [TaskItem], calendar: Calendar = .current) -> [TaskItem] {
        var seen = Set<UUID>()
        var result: [TaskItem] = []
        for task in blockedToday(tasks) + dueToday(tasks, calendar: calendar) {
            guard seen.insert(task.uuid).inserted else { continue }
            result.append(task)
        }
        return sortedByDueDate(result, calendar: calendar)
    }

    static func dueTodayExcludingBlocked(_ tasks: [TaskItem], calendar: Calendar = .current) -> [TaskItem] {
        dueToday(tasks, calendar: calendar).filter { !$0.isBlockedToday }
    }

    static func dueTomorrow(_ tasks: [TaskItem], calendar: Calendar = .current) -> [TaskItem] {
        active(tasks).filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDateInTomorrow(due)
        }
    }

    static func on(day: Date, tasks: [TaskItem], calendar: Calendar = .current) -> [TaskItem] {
        let target = calendar.startOfDay(for: day)
        return active(tasks).filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: target)
        }
    }

    static func agenda(on day: Date, tasks: [TaskItem], calendar: Calendar = .current) -> [TaskItem] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let isToday = calendar.isDateInToday(day)
        var seen = Set<UUID>()
        var result: [TaskItem] = []

        for task in active(tasks) {
            var include = false
            if let due = task.dueDate, due >= dayStart, due < dayEnd { include = true }
            if isToday, task.planForToday { include = true }
            if let start = task.calendarEventStart, let end = task.calendarEventEnd,
               start < dayEnd, end > dayStart {
                include = true
            }
            if include, seen.insert(task.uuid).inserted {
                result.append(task)
            }
        }
        return sortedByDueDate(result, calendar: calendar)
    }

    static func overdue(_ tasks: [TaskItem], calendar: Calendar = .current) -> [TaskItem] {
        let todayStart = calendar.startOfDay(for: .now)
        return active(tasks).filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.startOfDay(for: due) < todayStart
        }
    }

    static func upcomingDays(from start: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        let base = calendar.startOfDay(for: start)
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: base) }
    }

    static func forCategory(_ project: Project, tasks: [TaskItem]) -> [TaskItem] {
        active(tasks).filter { $0.project?.persistentModelID == project.persistentModelID }
    }

    static func scheduled(_ tasks: [TaskItem]) -> [TaskItem] {
        active(tasks).filter { $0.dueDate != nil }
    }

    static func sortedByDueDate(_ tasks: [TaskItem], calendar: Calendar = .current) -> [TaskItem] {
        tasks.sorted { compareByDueDate($0, $1, calendar: calendar) }
    }

    static func compareByDueDate(_ lhs: TaskItem, _ rhs: TaskItem, calendar: Calendar = .current) -> Bool {
        switch (dueSortDay(lhs, calendar: calendar), dueSortDay(rhs, calendar: calendar)) {
        case let (left?, right?):
            if left != right { return left < right }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.createdAt < rhs.createdAt
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case (nil, nil):
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private static func dueSortDay(_ task: TaskItem, calendar: Calendar) -> Date? {
        task.dueDate.map { calendar.startOfDay(for: $0) }
    }
}

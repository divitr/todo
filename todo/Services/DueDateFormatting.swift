import Foundation

enum DueDateFormatting {
    static func label(for date: Date, calendar: Calendar = .current) -> String {
        label(for: date, hasTime: false, at: date, calendar: calendar)
    }

    static func label(for date: Date, hasTime: Bool, at fullDate: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let dayPart: String
        if calendar.isDateInToday(day) { dayPart = "Today" }
        else if calendar.isDateInTomorrow(day) { dayPart = "Tomorrow" }
        else if calendar.isDateInYesterday(day) { dayPart = "Yesterday" }
        else if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: day).day,
                  abs(days) < 7 {
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            dayPart = f.string(from: day)
        } else {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            dayPart = f.string(from: day)
        }

        guard hasTime else { return dayPart }
        let tf = DateFormatter()
        tf.dateFormat = "h:mm a"
        return "\(dayPart) · \(tf.string(from: fullDate))"
    }

    static func taskDueLabel(_ task: TaskItem) -> String? {
        guard let due = task.dueDate else { return nil }
        return label(for: due, hasTime: true, at: due)
    }

    static func plannedStartLabel(_ task: TaskItem) -> String? {
        guard task.useManualStart, let start = task.manualStart else { return nil }
        return label(for: start, hasTime: true, at: start)
    }

    static func reminderLabel(_ task: TaskItem) -> String? {
        guard task.reminderEnabled else { return nil }
        if let at = task.reminderAt {
            return "Remind \(label(for: at, hasTime: true, at: at))"
        }
        return "Remind \(task.reminderTimeLabel)"
    }
}

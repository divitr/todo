import Foundation

enum ScheduleConflict: Equatable {
    case workStartsAfterDue(workStart: Date, due: Date)
    case workEndsAfterDue(workEnd: Date, due: Date)

    var fingerprint: String {
        switch self {
        case .workStartsAfterDue(let s, let d):
            "start:\(s.timeIntervalSince1970):\(d.timeIntervalSince1970)"
        case .workEndsAfterDue(let e, let d):
            "end:\(e.timeIntervalSince1970):\(d.timeIntervalSince1970)"
        }
    }

    var title: String {
        switch self {
        case .workStartsAfterDue: "Work scheduled after due date"
        case .workEndsAfterDue: "Work runs past due date"
        }
    }

    var message: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        switch self {
        case .workStartsAfterDue(let work, let due):
            return "Calendar block starts \(f.string(from: work)), but this task is due \(f.string(from: due))."
        case .workEndsAfterDue(let work, let due):
            return "Calendar block ends \(f.string(from: work)), after the due date \(f.string(from: due))."
        }
    }
}

extension TaskItem {
    var scheduleConflict: ScheduleConflict? {
        guard let due = dueDate, !isComplete else { return nil }
        guard let workStart = calendarEventStart, let workEnd = calendarEventEnd else { return nil }

        let cal = Calendar.current
        let dueCutoff: Date = {
            if hasDueTime { return due }
            let day = cal.startOfDay(for: due)
            return cal.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
        }()

        if workStart > dueCutoff {
            return .workStartsAfterDue(workStart: workStart, due: dueCutoff)
        }
        if workEnd > dueCutoff {
            return .workEndsAfterDue(workEnd: workEnd, due: dueCutoff)
        }
        return nil
    }
}

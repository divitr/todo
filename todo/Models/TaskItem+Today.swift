import Foundation

extension TaskItem {
    var planForToday: Bool {
        get { planForTodayStored }
        set { planForTodayStored = newValue }
    }

    var isCalendarBlockedToday: Bool {
        guard !isComplete else { return false }
        return isCalendarEventToday
    }

    var isBlockedToday: Bool {
        guard !isComplete else { return false }
        return planForToday || isCalendarBlockedToday
    }

    var isDueToday: Bool {
        guard !isComplete, let due = dueDate else { return false }
        return Calendar.current.isDateInToday(due)
    }

    var isOnTodayAgenda: Bool {
        isBlockedToday || isDueToday
    }

    var matchesTodayList: Bool {
        let cal = Calendar.current
        let dueOnToday = dueDate.map { cal.isDateInToday($0) } ?? false
        return dueOnToday || planForToday || isCalendarEventToday
    }

    var isCalendarEventToday: Bool {
        guard hasCalendarLink,
              let start = calendarEventStart,
              let end = calendarEventEnd else { return false }
        return Self.eventOverlapsToday(start: start, end: end)
    }

    var todayPlanHelp: String {
        if planForToday && isCalendarBlockedToday {
            return "Blocked for today — click to remove from today"
        }
        if planForToday {
            return "Blocked for today — click to remove"
        }
        if isCalendarBlockedToday {
            return "On your calendar today — click to mark blocked for today"
        }
        return "Block for today — choose a time on your calendar"
    }

    var todayBlockTimeLabel: String? {
        guard isCalendarBlockedToday,
              let start = calendarEventStart,
              let end = calendarEventEnd else { return nil }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return "\(f.string(from: start))–\(f.string(from: end))"
        }
        f.dateStyle = .short
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    static func eventOverlapsToday(start: Date, end: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: .now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return start < dayEnd && end > dayStart
    }
}

import Foundation

enum ScheduleDateDefaults {
    enum Kind {
        case plannedStart
        case due
    }

    static func defaultDate(for kind: Kind, on day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        switch kind {
        case .plannedStart:
            return start
        case .due:
            return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: start) ?? start
        }
    }

    static func applyingDayChange(_ newDay: Date, kind: Kind, calendar: Calendar = .current) -> Date {
        defaultDate(for: kind, on: newDay, calendar: calendar)
    }

    static func mergingDay(_ newDay: Date, preservingTimeFrom existing: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: newDay)
        let time = calendar.dateComponents([.hour, .minute, .second], from: existing)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: day
        ) ?? day
    }

    static func dueDateForEditing(_ due: Date?, hasDueTime: Bool, calendar: Calendar = .current) -> Date {
        guard let due else { return defaultDate(for: .due, on: .now, calendar: calendar) }
        if hasDueTime { return due }
        if calendar.isDate(due, equalTo: calendar.startOfDay(for: due), toGranularity: .minute) {
            return defaultDate(for: .due, on: due, calendar: calendar)
        }
        return due
    }

    static func plannedStartForEditing(_ start: Date?, calendar: Calendar = .current) -> Date {
        guard let start else { return defaultDate(for: .plannedStart, on: .now, calendar: calendar) }
        return start
    }
}

import Foundation

extension TaskItem {
    func linkCalendarEvent(_ summary: CalendarEventSummary, updateDuration: Bool = true) {
        calendarEventID = summary.id
        calendarEventTitle = summary.title
        calendarEventCalendarName = summary.calendarTitle
        calendarEventStart = summary.start
        calendarEventEnd = summary.end
        calendarLastSyncedAt = .now
        calendarColorRed = summary.calendarColorRed
        calendarColorGreen = summary.calendarColorGreen
        calendarColorBlue = summary.calendarColorBlue
        calendarColorStored = true
        if updateDuration {
            durationDays = max(summary.durationDays, Self.minDurationDays)
        }
    }

    func clearCalendarLink() {
        calendarEventID = nil
        calendarEventTitle = nil
        calendarEventCalendarName = nil
        calendarEventStart = nil
        calendarEventEnd = nil
        calendarLastSyncedAt = nil
        calendarColorStored = false
        scheduleWarningFingerprint = nil
    }

    @MainActor
    @discardableResult
    func syncCalendarFromEventStore() -> Bool {
        guard let id = calendarEventID else { return false }
        guard let fresh = CalendarService.shared.resolveEvent(identifier: id) else {
            return false
        }

        let oldStart = calendarEventStart
        let oldEnd = calendarEventEnd
        let oldTitle = calendarEventTitle

        calendarEventTitle = fresh.title
        calendarEventCalendarName = fresh.calendarTitle
        calendarEventStart = fresh.start
        calendarEventEnd = fresh.end
        calendarLastSyncedAt = .now
        calendarColorRed = fresh.calendarColorRed
        calendarColorGreen = fresh.calendarColorGreen
        calendarColorBlue = fresh.calendarColorBlue
        calendarColorStored = true

        return oldStart != fresh.start || oldEnd != fresh.end || oldTitle != fresh.title
    }

    var calendarDurationDays: Double {
        guard let start = calendarEventStart, let end = calendarEventEnd else { return durationDays }
        return max(end.timeIntervalSince(start) / 86_400, Self.minDurationDays)
    }
}

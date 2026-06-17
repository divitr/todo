import Foundation

extension TaskItem {
    func ganttBarSpan(calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let duration = max(durationDays, TaskItem.minDurationDays)

        if let due = dueDate {
            let end = calendar.startOfDay(for: due)
            var start = GanttScheduleMath.inclusiveStart(end: end, durationDays: duration, calendar: calendar)
            if useManualStart, let manual = manualStart {
                start = max(start, calendar.startOfDay(for: manual))
            }
            if start > end { start = end }
            return (start, end)
        }

        if useManualStart, let manual = manualStart {
            let start = calendar.startOfDay(for: manual)
            let end = GanttScheduleMath.inclusiveEnd(start: start, durationDays: duration, calendar: calendar)
            return (start, end)
        }

        if let s = scheduledStart, let e = scheduledEnd {
            return (calendar.startOfDay(for: s), calendar.startOfDay(for: e))
        }

        return nil
    }

    var hasGanttBar: Bool {
        ganttBarSpan() != nil
    }

    var hasSubtaskGanttDuration: Bool {
        parent != nil && durationDays >= 1
    }
}

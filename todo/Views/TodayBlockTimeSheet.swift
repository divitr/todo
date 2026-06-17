import SwiftUI

struct TodayBlockTimeSheet: View {
    @Bindable var task: TaskItem
    var onSaved: () -> Void
    var onDismiss: () -> Void

    private var today: Date { Calendar.current.startOfDay(for: .now) }

    var body: some View {
        CalendarEventComposerSheet(
            taskTitle: task.title,
            taskNotes: task.notes,
            anchorDay: today,
            suggestedStart: task.manualStart ?? task.dueDate,
            suggestedEnd: task.calendarEventEnd,
            durationDays: min(task.durationDays, 1),
            mode: .blockToday,
            onConfirm: { summary in
                task.linkCalendarEvent(summary, updateDuration: true)
                task.planForToday = true
                NotificationCenter.default.post(name: .externalStoreChanged, object: nil)
                onSaved()
                onDismiss()
            },
            onDismiss: onDismiss
        )
    }
}

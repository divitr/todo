import SwiftUI

struct SubtaskDraft: Identifiable {
    let id = UUID()
    var title: String = ""
    var notes: String = ""
    var durationDays = 1.0
    var hasStart = false
    var startDate = Date()
    var hasEnd = false
    var endDate = Date()
    var hasDueTime = false
    var reminderEnabled = false
    var reminderAt = Date()
    var usesCustomReminder = false
    var reminderHour = TaskItem.defaultReminderHour
    var reminderMinute = TaskItem.defaultReminderMinute
    var calendarEventID: String?
    var calendarEventTitle: String?
    var calendarEventStart: Date?
    var calendarEventEnd: Date?
    var calendarLastSynced: Date?
    var calendarEventCalendarName: String?
    var calendarColorRed = CalendarRGB.fallback.red
    var calendarColorGreen = CalendarRGB.fallback.green
    var calendarColorBlue = CalendarRGB.fallback.blue
    var calendarColorStored = false
}

struct SubtaskDraftEditor: View {
    @Binding var draft: SubtaskDraft

    private var draftCalendarColor: Color? {
        guard draft.calendarEventID != nil, draft.calendarColorStored else { return nil }
        return Color(red: draft.calendarColorRed, green: draft.calendarColorGreen, blue: draft.calendarColorBlue)
    }

    private var draftScheduleConflict: ScheduleConflict? {
        guard draft.hasEnd else { return nil }
        guard let start = draft.calendarEventStart, let end = draft.calendarEventEnd else { return nil }
        let cal = Calendar.current
        let dueCutoff = draft.endDate
        if start > dueCutoff {
            return .workStartsAfterDue(workStart: start, due: dueCutoff)
        }
        if end > dueCutoff {
            return .workEndsAfterDue(workEnd: end, due: dueCutoff)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Subtask title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(Theme.sans(13))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 0.5))

            TaskNotesSection(notes: $draft.notes, minLines: 2)

            ScheduleEditorView(
                durationDays: $draft.durationDays,
                hasStart: $draft.hasStart,
                startDate: $draft.startDate,
                hasEnd: $draft.hasEnd,
                endDate: $draft.endDate,
                hasDueTime: $draft.hasDueTime,
                reminderEnabled: $draft.reminderEnabled,
                reminderAt: $draft.reminderAt,
                usesCustomReminder: $draft.usesCustomReminder,
                reminderHour: $draft.reminderHour,
                reminderMinute: $draft.reminderMinute,
                compact: true,
                hasLinkedCalendar: draft.calendarEventID != nil
            )

            CalendarLinkEditor(
                eventID: $draft.calendarEventID,
                eventTitle: $draft.calendarEventTitle,
                eventStart: $draft.calendarEventStart,
                eventEnd: $draft.calendarEventEnd,
                lastSyncedAt: $draft.calendarLastSynced,
                calendarColor: draftCalendarColor,
                calendarTitle: draft.calendarEventCalendarName,
                scheduleConflict: draftScheduleConflict,
                taskTitle: draft.title,
                taskNotes: draft.notes,
                suggestedStart: draft.hasStart ? draft.startDate : (draft.hasEnd ? draft.endDate : nil),
                suggestedEnd: draft.calendarEventEnd ?? (draft.hasEnd ? draft.endDate : nil),
                durationDays: draft.durationDays
            ) { summary in
                draft.calendarEventCalendarName = summary.calendarTitle
                draft.calendarColorRed = summary.calendarColorRed
                draft.calendarColorGreen = summary.calendarColorGreen
                draft.calendarColorBlue = summary.calendarColorBlue
                draft.calendarColorStored = true
                CalendarScheduleApplier.applyDurationOnly(summary, durationDays: &draft.durationDays)
            }
        }
    }
}

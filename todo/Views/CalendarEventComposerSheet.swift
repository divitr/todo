import SwiftUI

enum CalendarComposerMode {
    case createAndLink
    case blockToday
}

struct CalendarEventComposerSheet: View {
    let taskTitle: String
    let taskNotes: String
    var anchorDay: Date = .now
    var suggestedStart: Date?
    var suggestedEnd: Date?
    var durationDays: Double = 1
    var mode: CalendarComposerMode = .createAndLink
    var onConfirm: (CalendarEventSummary) -> Void
    var onDismiss: () -> Void

    @StateObject private var calendar = CalendarService.shared
    @State private var title = ""
    @State private var focusDay: Date
    @State private var events: [CalendarEventSummary] = []
    @State private var selectionStart: Date?
    @State private var selectionEnd: Date?
    @State private var selectedCalendarID: String?
    @State private var calendars: [CalendarPickerCalendar] = []
    @State private var accessDenied = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showNotes = false

    private let cal = Calendar.current

    init(
        taskTitle: String,
        taskNotes: String,
        anchorDay: Date = .now,
        suggestedStart: Date? = nil,
        suggestedEnd: Date? = nil,
        durationDays: Double = 1,
        mode: CalendarComposerMode = .createAndLink,
        onConfirm: @escaping (CalendarEventSummary) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.taskTitle = taskTitle
        self.taskNotes = taskNotes
        self.anchorDay = anchorDay
        self.suggestedStart = suggestedStart
        self.suggestedEnd = suggestedEnd
        self.durationDays = durationDays
        self.mode = mode
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        _focusDay = State(initialValue: Calendar.current.startOfDay(for: anchorDay))
    }

    private var selectionIsValid: Bool {
        guard let selectionStart, let selectionEnd else { return false }
        return selectionEnd > selectionStart
    }

    private var sheetTitle: String {
        mode == .blockToday ? "Block for today" : "New calendar event"
    }

    private var confirmTitle: String {
        mode == .blockToday ? "Block this time" : "Create & link"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)

            if accessDenied {
                ContentUnavailableView {
                    Label("Calendar Access Required", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Allow todo in System Settings → Privacy & Security → Calendars.")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    titleField
                    dayNavigator
                    selectionBar
                    durationChips
                    grid
                    calendarPicker
                    notesSection
                }
                .padding(.top, 8)
            }

            Divider().overlay(Theme.border)
            footer
        }
        .frame(width: 400, height: mode == .blockToday ? 600 : 620)
        .onAppear { bootstrapFields() }
        .task(id: focusDay) { await loadDay() }
    }

    private var header: some View {
        HStack {
            Text(sheetTitle)
                .font(Theme.sans(16, weight: .semibold))
            Spacer()
            Button("Cancel", action: onDismiss)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var titleField: some View {
        TextField("Event title", text: $title)
            .font(Theme.sans(14, weight: .medium))
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
            .padding(.horizontal, 14)
    }

    private var dayNavigator: some View {
        HStack(spacing: 8) {
            Button { shiftDay(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(dayTitle(focusDay))
                    .font(Theme.sans(14, weight: .semibold))
                if cal.isDateInToday(focusDay) {
                    Text("Today")
                        .font(Theme.sans(10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }

            Spacer()

            Button { shiftDay(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)

            Button("Today") {
                focusDay = cal.startOfDay(for: .now)
                alignSelectionToFocusDay()
            }
            .buttonStyle(.borderless)
            .font(Theme.sans(11, weight: .medium))
            .disabled(cal.isDateInToday(focusDay))
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var selectionBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.day.timeline.left")
                .foregroundStyle(Theme.primary)
            if let start = selectionStart, let end = selectionEnd {
                Text(CalendarEventFormatting.rangeLabel(start: start, end: end, isAllDay: false))
                    .font(Theme.sans(13, weight: .semibold))
            } else {
                Text("Drag on the grid to choose a time")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var durationChips: some View {
        HStack(spacing: 8) {
            Text("Duration")
                .font(Theme.sans(11))
                .foregroundStyle(Theme.muted)
            ForEach([30, 60, 90, 120], id: \.self) { minutes in
                Button("\(minutes)m") { applyDuration(minutes: minutes) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    private var grid: some View {
        TodayTimeBlockGridView(
            day: focusDay,
            events: events,
            selectionStart: $selectionStart,
            selectionEnd: $selectionEnd,
            draftTitle: title.isEmpty ? nil : title
        )
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var calendarPicker: some View {
        if !calendars.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(calendars) { item in
                        let selected = selectedCalendarID == item.id
                        Button {
                            selectedCalendarID = item.id
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(item.color).frame(width: 8, height: 8)
                                Text(item.title)
                                    .font(Theme.sans(11, weight: selected ? .semibold : .regular))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selected ? item.color.opacity(0.18) : Theme.hover)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(selected ? item.color.opacity(0.5) : Theme.border, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private var notesSection: some View {
        DisclosureGroup(isExpanded: $showNotes) {
            Text(CalendarEventNotes.formatted(description: taskNotes))
                .font(Theme.sans(11))
                .foregroundStyle(Theme.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Text("Notes sent to Calendar")
                .font(Theme.sans(11, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        HStack {
            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.sans(11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Text(confirmTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!selectionIsValid || accessDenied || isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func bootstrapFields() {
        let trimmed = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmed.isEmpty ? "Untitled" : trimmed

        let window = CalendarService.defaultEventWindow(
            suggestedStart: suggestedStart,
            suggestedEnd: suggestedEnd,
            durationDays: durationDays
        )
        var start = window.start
        if !cal.isDate(start, inSameDayAs: focusDay) {
            start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: focusDay) ?? focusDay
        }
        selectionStart = start
        selectionEnd = window.end > start ? window.end : (cal.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600))
    }

    private func shiftDay(by offset: Int) {
        guard let next = cal.date(byAdding: .day, value: offset, to: focusDay) else { return }
        focusDay = cal.startOfDay(for: next)
        alignSelectionToFocusDay()
    }

    private func alignSelectionToFocusDay() {
        guard let start = selectionStart, let end = selectionEnd else {
            bootstrapFields()
            return
        }
        let duration = end.timeIntervalSince(start)
        let hour = cal.component(.hour, from: start)
        let minute = cal.component(.minute, from: start)
        let newStart = cal.date(bySettingHour: hour, minute: minute, second: 0, of: focusDay) ?? focusDay
        selectionStart = newStart
        selectionEnd = newStart.addingTimeInterval(max(duration, 15 * 60))
    }

    private func applyDuration(minutes: Int) {
        guard let start = selectionStart else { return }
        selectionEnd = start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func dayTitle(_ day: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: day)
    }

    @MainActor
    private func loadDay() async {
        let granted = await calendar.requestAccess()
        accessDenied = !granted
        guard granted else { return }

        calendars = calendar.writableCalendars()
        if selectedCalendarID == nil {
            selectedCalendarID = calendar.defaultWritableCalendarIdentifier()
        }

        let start = cal.startOfDay(for: focusDay)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        events = calendar.fetchEvents(from: start, to: end)
    }

    @MainActor
    private func save() async {
        guard let start = selectionStart, let end = selectionEnd else { return }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let request = CalendarCreateEventRequest(
            title: title,
            description: taskNotes,
            start: start,
            end: end,
            calendarIdentifier: selectedCalendarID
        )

        do {
            let summary = try calendar.createEvent(request)
            onConfirm(summary)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

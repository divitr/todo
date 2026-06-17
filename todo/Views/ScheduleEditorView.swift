import SwiftData
import SwiftUI

struct DurationEditor: View {
    @Binding var days: Double

    @State private var showsCustom = false
    @State private var customText = ""
    @State private var customUnit: DurationInputUnit = .hours

    private var canDecrement: Bool {
        days > DurationFormatting.modelMinDays + 0.0001
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Duration", systemImage: "clock")
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 100, alignment: .leading)

                stepButton(systemImage: "minus", enabled: canDecrement, action: decrement)

                Text(DurationFormatting.label(for: days))
                    .font(Theme.sans(14, weight: .semibold))
                    .frame(minWidth: 56)
                    .help("Estimated work length")

                stepButton(systemImage: "plus", enabled: days < 60, action: increment)

                Spacer(minLength: 8)

                Button(showsCustom ? "Presets" : "Custom") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showsCustom.toggle()
                        if showsCustom {
                            syncCustomFieldsFromDays()
                        }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .controlSize(.small)
            }

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(DurationFormatting.presetDays, id: \.self) { preset in
                    let isActive = abs(days - preset) < 0.001
                    Button {
                        days = DurationFormatting.clamp(preset)
                        showsCustom = false
                    } label: {
                        Text(DurationFormatting.label(for: preset))
                    }
                    .buttonStyle(MetaPillButtonStyle(isActive: isActive))
                }
            }

            if showsCustom {
                HStack(spacing: 8) {
                    TextField("Amount", text: $customText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .font(Theme.sans(12))
                        .onSubmit(applyCustom)

                    Picker("", selection: $customUnit) {
                        ForEach(DurationInputUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)

                    Button("Apply") { applyCustom() }
                        .buttonStyle(MonoProminentButtonStyle())

                    Text("≈ \(DurationFormatting.label(for: days))")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func stepButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.borderless)
        .background(Theme.hover)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func decrement() {
        var value = days
        DurationFormatting.decrement(&value)
        days = value
    }

    private func increment() {
        var value = days
        DurationFormatting.increment(&value)
        days = value
    }

    private func syncCustomFieldsFromDays() {
        customText = DurationFormatting.customDisplayValue(for: days, unit: customUnit)
    }

    private func applyCustom() {
        guard let parsed = DurationFormatting.parseCustom(value: customText, unit: customUnit) else { return }
        days = parsed
    }
}

private enum ReminderWhen: String, CaseIterable, Identifiable {
    case morningOnDueDay
    case atDueDateTime
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .morningOnDueDay: "Morning of due date"
        case .atDueDateTime: "At due date & time"
        case .custom: "Custom"
        }
    }
}

enum ReminderScheduleHelper {
    static func preview(
        enabled: Bool,
        hasEnd: Bool,
        hasDueTime: Bool,
        endDate: Date,
        usesCustomReminder: Bool,
        reminderAt: Date,
        reminderHour: Int,
        reminderMinute: Int
    ) -> String {
        guard enabled else { return "Reminder off" }
        guard hasEnd else { return "Set a due date first" }
        let cal = Calendar.current
        if usesCustomReminder {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return "Will notify \(f.string(from: reminderAt))"
        }
        if hasDueTime {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return "Will notify \(f.string(from: endDate))"
        }
        let day = cal.startOfDay(for: endDate)
        let fire = cal.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: day) ?? endDate
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return "Will notify \(f.string(from: fire))"
    }

    @MainActor
    static func syncNotification(for task: TaskItem) async {
        if task.shouldScheduleReminder {
            guard await NotificationScheduler.shared.ensureAuthorization() else { return }
            await NotificationScheduler.shared.schedule(task: task)
        } else {
            NotificationScheduler.shared.cancel(task: task)
        }
    }
}

struct ScheduleEditorView: View {
    @Binding var durationDays: Double
    @Binding var hasStart: Bool
    @Binding var startDate: Date
    @Binding var hasEnd: Bool
    @Binding var endDate: Date
    @Binding var hasDueTime: Bool
    @Binding var reminderEnabled: Bool
    @Binding var reminderAt: Date
    @Binding var usesCustomReminder: Bool
    @Binding var reminderHour: Int
    @Binding var reminderMinute: Int

    var compact: Bool = false
    var hasLinkedCalendar: Bool = false
    var onReminderChange: (() -> Void)?

    @State private var reminderWhen: ReminderWhen = .morningOnDueDay
    @ObservedObject private var notifications = NotificationScheduler.shared

    private var cal: Calendar { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Deadline")

            dateRow(
                title: "Due date",
                isOn: $hasEnd,
                date: $endDate,
                quickOffsets: [0, 1],
                timeKind: .due
            )

            DurationEditor(days: $durationDays)

            dateRow(
                title: "Planned start",
                isOn: $hasStart,
                date: $startDate,
                quickOffsets: nil,
                timeKind: .plannedStart
            )

            Text("Due date is your deadline. Calendar work time is linked separately below.")
                .font(Theme.sans(10))
                .foregroundStyle(Theme.faint)

            Divider().overlay(Theme.border)

            reminderSection
        }
        .padding(compact ? 10 : 14)
        .background(Theme.hover)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .onChange(of: hasEnd) { _, on in
            if on {
                endDate = ScheduleDateDefaults.defaultDate(for: .due, on: endDate)
                hasDueTime = true
            } else {
                reminderEnabled = false
                hasDueTime = false
                usesCustomReminder = false
            }
            notifyReminderChange()
        }
        .onChange(of: hasStart) { _, on in
            if on {
                startDate = ScheduleDateDefaults.defaultDate(for: .plannedStart, on: startDate)
            }
        }
        .onChange(of: endDate) { _, _ in
            if reminderEnabled, reminderWhen == .morningOnDueDay {
                alignReminderToDueMorning()
            }
            notifyReminderChange()
        }
        .onAppear { syncReminderWhenFromBindings() }
    }

    @ViewBuilder
    private var reminderNotificationExtras: some View {
        if notifications.authorizationDenied {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bell.slash")
                    .foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications are off for todo.")
                        .font(Theme.sans(11, weight: .medium))
                    Button("Open Notification Settings") {
                        notifications.openNotificationSettings()
                    }
                    .buttonStyle(.link)
                    .font(Theme.sans(11))
                }
                Spacer()
            }
            .padding(10)
            .background(Theme.hover)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Morning agenda at 8:00 AM · overdue nudge at 8:00 PM on due dates.")
                    .font(Theme.sans(10))
                    .foregroundStyle(Theme.faint)
                Button("Send test alert in 3 seconds") {
                    Task { await notifications.sendTestNotification() }
                }
                .buttonStyle(.link)
                .font(Theme.sans(11))
            }
        }
    }

    @ViewBuilder
    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Reminder")

            if !hasEnd {
                Text("Turn on a due date above to enable reminders.")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.muted)
            } else {
                Toggle("Remind me", isOn: $reminderEnabled)
                    .font(Theme.sans(13, weight: .medium))
                    .toggleStyle(.switch)
                    .onChange(of: reminderEnabled) { _, on in
                        if on {
                            if !usesCustomReminder { alignReminderToDueMorning() }
                            Task { await NotificationScheduler.shared.ensureAuthorization() }
                        }
                        notifyReminderChange()
                    }

                if reminderEnabled {
                    Text(reminderPreview)
                        .font(Theme.sans(11, weight: .medium))
                        .foregroundStyle(Theme.secondary)

                    reminderNotificationExtras

                    if hasLinkedCalendar {
                        Text("Calendar.app may also alert you for the linked event. This is an extra todo notification.")
                            .font(Theme.sans(10))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Picker("When", selection: $reminderWhen) {
                        ForEach(ReminderWhen.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: reminderWhen) { _, mode in
                        applyReminderWhen(mode)
                    }

                    if reminderWhen == .custom {
                        DatePicker("Remind on", selection: $reminderAt, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.field)
                            .font(Theme.sans(12))
                            .onChange(of: reminderAt) { _, _ in notifyReminderChange() }
                    } else if reminderWhen == .morningOnDueDay {
                        HStack {
                            Text("Time")
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.muted)
                            DatePicker("", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .datePickerStyle(.field)
                                .frame(maxWidth: 140)
                        }
                    }

                }
            }
        }
    }

    private var reminderPreview: String {
        let fireAtDueTime = reminderWhen == .atDueDateTime
        return ReminderScheduleHelper.preview(
            enabled: reminderEnabled,
            hasEnd: hasEnd,
            hasDueTime: fireAtDueTime || hasEnd,
            endDate: endDate,
            usesCustomReminder: usesCustomReminder,
            reminderAt: reminderAt,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute
        )
    }

    private func alignReminderToDueMorning() {
        guard hasEnd else { return }
        let day = cal.startOfDay(for: endDate)
        reminderAt = cal.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: day) ?? endDate
    }

    private func alignReminderAtToDueDay() {
        guard hasEnd else { return }
        let day = cal.startOfDay(for: endDate)
        let comps = cal.dateComponents([.hour, .minute], from: reminderAt)
        reminderAt = cal.date(
            bySettingHour: comps.hour ?? TaskItem.defaultReminderHour,
            minute: comps.minute ?? 0,
            second: 0,
            of: day
        ) ?? endDate
    }

    private func syncReminderWhenFromBindings() {
        if usesCustomReminder {
            reminderWhen = .custom
        } else {
            reminderWhen = .morningOnDueDay
        }
    }

    private func applyReminderWhen(_ mode: ReminderWhen) {
        switch mode {
        case .morningOnDueDay:
            usesCustomReminder = false
            alignReminderToDueMorning()
        case .atDueDateTime:
            usesCustomReminder = false
            hasDueTime = true
            if hasEnd {
                endDate = ScheduleDateDefaults.defaultDate(for: .due, on: endDate)
            }
        case .custom:
            usesCustomReminder = true
            alignReminderAtToDueDay()
        }
        notifyReminderChange()
    }

    private func notifyReminderChange() {
        onReminderChange?()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.sans(11, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .textCase(.uppercase)
    }

    @ViewBuilder
    private func dateRow(
        title: String,
        isOn: Binding<Bool>,
        date: Binding<Date>,
        quickOffsets: [Int]?,
        timeKind: ScheduleDateDefaults.Kind
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: isOn)
                .font(Theme.sans(13, weight: .medium))
                .toggleStyle(.switch)

            if isOn.wrappedValue {
                HStack(spacing: 10) {
                    DatePicker(
                        "",
                        selection: dayBinding(for: date, timeKind: timeKind),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .font(Theme.sans(13))

                    if let quickOffsets {
                        HStack(spacing: 6) {
                            ForEach(quickOffsets, id: \.self) { offset in
                                quickDateButton(
                                    offset == 0 ? "Today" : "Tomorrow",
                                    dayOffset: offset,
                                    date: date,
                                    timeKind: timeKind
                                )
                            }
                        }
                    }
                }

                DatePicker("Time", selection: date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                    .font(Theme.sans(12))

                Text(DueDateFormatting.label(for: date.wrappedValue, hasTime: true, at: date.wrappedValue))
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.faint)
            }
        }
    }

    private func dayBinding(for date: Binding<Date>, timeKind: ScheduleDateDefaults.Kind) -> Binding<Date> {
        Binding(
            get: { date.wrappedValue },
            set: { newDay in
                date.wrappedValue = ScheduleDateDefaults.applyingDayChange(newDay, kind: timeKind)
                if timeKind == .due { hasDueTime = true }
            }
        )
    }

    private func quickDateButton(
        _ title: String,
        dayOffset: Int,
        date: Binding<Date>,
        timeKind: ScheduleDateDefaults.Kind
    ) -> some View {
        Button {
            let base = cal.startOfDay(for: .now)
            let day = cal.date(byAdding: .day, value: dayOffset, to: base) ?? base
            date.wrappedValue = ScheduleDateDefaults.defaultDate(for: timeKind, on: day)
            if timeKind == .due { hasDueTime = true }
        } label: {
            Text(title)
                .font(Theme.sans(11, weight: .medium))
        }
        .buttonStyle(MetaPillButtonStyle(isActive: isQuickDateSelected(dayOffset, date: date.wrappedValue)))
    }

    private func isQuickDateSelected(_ offset: Int, date: Date) -> Bool {
        let base = cal.startOfDay(for: .now)
        guard let target = cal.date(byAdding: .day, value: offset, to: base) else { return false }
        return cal.isDate(date, inSameDayAs: target)
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: { reminderAt },
            set: { newValue in
                let comps = cal.dateComponents([.hour, .minute], from: newValue)
                reminderHour = comps.hour ?? TaskItem.defaultReminderHour
                reminderMinute = comps.minute ?? 0
                if let merged = cal.date(
                    bySettingHour: reminderHour,
                    minute: reminderMinute,
                    second: 0,
                    of: cal.startOfDay(for: endDate)
                ) {
                    reminderAt = merged
                }
                notifyReminderChange()
            }
        )
    }

}

struct TaskScheduleEditorView: View {
    @Bindable var task: TaskItem

    @State private var durationDays = 1.0
    @State private var hasStart = false
    @State private var startDate = Date()
    @State private var hasEnd = false
    @State private var endDate = Date()
    @State private var hasDueTime = false
    @State private var reminderEnabled = false
    @State private var reminderAt = Date()
    @State private var usesCustomReminder = false
    @State private var reminderHour = TaskItem.defaultReminderHour
    @State private var reminderMinute = TaskItem.defaultReminderMinute

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScheduleEditorView(
                durationDays: $durationDays,
                hasStart: $hasStart,
                startDate: $startDate,
                hasEnd: $hasEnd,
                endDate: $endDate,
                hasDueTime: $hasDueTime,
                reminderEnabled: $reminderEnabled,
                reminderAt: $reminderAt,
                usesCustomReminder: $usesCustomReminder,
                reminderHour: $reminderHour,
                reminderMinute: $reminderMinute,
                hasLinkedCalendar: task.hasCalendarLink,
                onReminderChange: { apply(); Task { await ReminderScheduleHelper.syncNotification(for: task) } }
            )

            sectionHeader("Calendar")

            CalendarLinkEditor(
                eventID: $task.calendarEventID,
                eventTitle: $task.calendarEventTitle,
                eventStart: $task.calendarEventStart,
                eventEnd: $task.calendarEventEnd,
                lastSyncedAt: $task.calendarLastSyncedAt,
                calendarColor: task.calendarAccentColor,
                calendarTitle: task.calendarEventCalendarName,
                scheduleConflict: task.scheduleConflict,
                taskTitle: task.title,
                taskNotes: task.notes,
                suggestedStart: task.manualStart ?? task.calendarEventStart ?? task.dueDate,
                suggestedEnd: task.calendarEventEnd ?? task.dueDate,
                durationDays: task.durationDays
            ) { summary in
                task.linkCalendarEvent(summary, updateDuration: true)
                loadFromTask()
            }
        }
        .onAppear {
            load()
            if task.syncCalendarFromEventStore() {
                loadFromTask()
            }
        }
        .onChange(of: durationDays) { _, _ in apply() }
        .onChange(of: hasStart) { _, _ in apply() }
        .onChange(of: startDate) { _, _ in apply() }
        .onChange(of: hasEnd) { _, _ in apply() }
        .onChange(of: endDate) { _, _ in apply() }
        .onChange(of: hasDueTime) { _, _ in apply() }
        .onChange(of: reminderEnabled) { _, _ in
            apply()
            Task { await ReminderScheduleHelper.syncNotification(for: task) }
        }
        .onChange(of: reminderAt) { _, _ in apply() }
        .onChange(of: usesCustomReminder) { _, _ in apply() }
        .onChange(of: reminderHour) { _, _ in apply() }
        .onChange(of: reminderMinute) { _, _ in apply() }
    }

    private func load() {
        loadFromTask()
    }

    private func loadFromTask() {
        durationDays = task.durationDays
        hasStart = task.useManualStart
        startDate = ScheduleDateDefaults.plannedStartForEditing(
            task.manualStart ?? task.calendarEventStart
        )
        hasEnd = task.dueDate != nil
        endDate = ScheduleDateDefaults.dueDateForEditing(task.dueDate, hasDueTime: task.hasDueTime)
        hasDueTime = task.dueDate != nil
        reminderEnabled = task.reminderEnabled
        reminderHour = task.reminderHour
        reminderMinute = task.reminderMinute
        reminderAt = task.reminderAt ?? defaultReminderDate()
        usesCustomReminder = task.reminderAt != nil
    }

    private func apply() {
        let cal = Calendar.current
        durationDays = DurationFormatting.clamp(durationDays)
        task.durationDays = durationDays
        task.useManualStart = hasStart
        task.manualStart = hasStart ? startDate : nil

        if hasEnd {
            task.dueDate = endDate
            task.hasDueTime = true
        } else {
            task.dueDate = nil
            task.hasDueTime = false
        }

        task.reminderEnabled = reminderEnabled && hasEnd
        task.reminderHour = reminderHour
        task.reminderMinute = reminderMinute
        if task.reminderEnabled {
            task.reminderAt = usesCustomReminder ? reminderAt : nil
        } else {
            task.reminderAt = nil
        }
    }

    private func defaultReminderDate() -> Date {
        let cal = Calendar.current
        let day = cal.startOfDay(for: task.dueDate ?? .now)
        return cal.date(bySettingHour: task.reminderHour, minute: task.reminderMinute, second: 0, of: day) ?? day
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.sans(11, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .textCase(.uppercase)
    }
}

enum TaskScheduleApplier {
    static func apply(
        to task: TaskItem,
        durationDays: Double,
        hasStart: Bool,
        startDate: Date,
        hasEnd: Bool,
        endDate: Date,
        hasDueTime: Bool,
        reminderEnabled: Bool,
        reminderAt: Date,
        usesCustomReminder: Bool,
        reminderHour: Int = TaskItem.defaultReminderHour,
        reminderMinute: Int = TaskItem.defaultReminderMinute
    ) {
        let cal = Calendar.current
        task.durationDays = DurationFormatting.clamp(durationDays)
        task.useManualStart = hasStart
        task.manualStart = hasStart ? startDate : nil

        if hasEnd {
            task.dueDate = endDate
            task.hasDueTime = true
        } else {
            task.dueDate = nil
            task.hasDueTime = false
        }

        task.reminderEnabled = reminderEnabled && hasEnd
        task.reminderHour = reminderHour
        task.reminderMinute = reminderMinute
        task.reminderAt = task.reminderEnabled && usesCustomReminder ? reminderAt : nil
    }

    static func apply(
        to task: TaskItem,
        hasDueDate: Bool,
        dueDate: Date,
        hasDueTime: Bool,
        reminderEnabled: Bool,
        reminderAt: Date,
        usesCustomReminder: Bool
    ) {
        apply(
            to: task,
            durationDays: task.durationDays,
            hasStart: task.useManualStart,
            startDate: task.manualStart ?? .now,
            hasEnd: hasDueDate,
            endDate: dueDate,
            hasDueTime: hasDueTime,
            reminderEnabled: reminderEnabled,
            reminderAt: reminderAt,
            usesCustomReminder: usesCustomReminder
        )
    }
}

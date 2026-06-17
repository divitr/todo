import SwiftData
import SwiftUI

struct AddTaskComposerView: View {
    let projects: [Project]
    var defaultProject: Project?
    var defaultDueDate: Date?
    var peerTasks: [TaskItem] = []
    var embeddedInList: Bool = false
    var onCancel: () -> Void
    var onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext
    @FocusState private var titleFocused: Bool

    @State private var title = ""
    @State private var notes = ""
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
    @State private var priority = 0
    @State private var durationDays = 1.0
    @State private var selectedProjectID: PersistentIdentifier?
    @State private var dependencyDrafts: [DependencyDraft] = []
    @State private var subtaskDrafts: [SubtaskDraft] = [SubtaskDraft()]
    @State private var showSubtasks = false
    @State private var showDependencies = false
    @State private var calendarEventID: String?
    @State private var calendarEventTitle: String?
    @State private var calendarEventStart: Date?
    @State private var calendarEventEnd: Date?
    @State private var calendarLastSynced: Date?
    @State private var calendarEventCalendarName: String?
    @State private var calendarColorRed = CalendarRGB.fallback.red
    @State private var calendarColorGreen = CalendarRGB.fallback.green
    @State private var calendarColorBlue = CalendarRGB.fallback.blue
    @State private var calendarColorStored = false

    private var draftCalendarColor: Color? {
        guard calendarEventID != nil, calendarColorStored else { return nil }
        return Color(red: calendarColorRed, green: calendarColorGreen, blue: calendarColorBlue)
    }

    private var categories: [Project] {
        projects.filter(\.isUserCategory)
    }

    private var draftScheduleConflict: ScheduleConflict? {
        guard hasEnd else { return nil }
        guard let start = calendarEventStart, let end = calendarEventEnd else { return nil }
        let cal = Calendar.current
        let dueCutoff = endDate
        if start > dueCutoff {
            return .workStartsAfterDue(workStart: start, due: dueCutoff)
        }
        if end > dueCutoff {
            return .workEndsAfterDue(workEnd: end, due: dueCutoff)
        }
        return nil
    }

    private var dependencyCandidates: [TaskItem] {
        let pool: [TaskItem]
        if let id = selectedProjectID,
           let cat = projects.first(where: { $0.persistentModelID == id && $0.isUserCategory }) {
            pool = peerTasks.filter { $0.project?.persistentModelID == cat.persistentModelID }
        } else if let cat = categories.first {
            pool = peerTasks.filter { $0.project?.persistentModelID == cat.persistentModelID }
        } else {
            pool = peerTasks
        }
        return TaskHierarchy.candidatePredecessors(for: nil, in: pool, sameCategoryOnly: false)
    }

    private var scrollMaxHeight: CGFloat {
        embeddedInList ? 480 : 560
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                composerScrollContent
            }
            .frame(maxHeight: scrollMaxHeight)

            Divider().overlay(Theme.border)

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .frame(minWidth: embeddedInList ? nil : 480)
        .frame(maxWidth: .infinity, alignment: .leading)
        .composerChrome()
        .onAppear(perform: setupDefaults)
    }

    private var composerScrollContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Task name", text: $title, axis: .vertical)
                    .font(Theme.sans(16, weight: .medium))
                    .textFieldStyle(.plain)
                    .lineLimit(3)
                    .focused($titleFocused)

                TaskNotesSection(notes: $notes)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            metaPills
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

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
                hasLinkedCalendar: calendarEventID != nil
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            CalendarLinkEditor(
                eventID: $calendarEventID,
                eventTitle: $calendarEventTitle,
                eventStart: $calendarEventStart,
                eventEnd: $calendarEventEnd,
                lastSyncedAt: $calendarLastSynced,
                calendarColor: draftCalendarColor,
                calendarTitle: calendarEventCalendarName,
                scheduleConflict: draftScheduleConflict,
                taskTitle: title,
                taskNotes: notes,
                suggestedStart: hasStart ? startDate : (hasEnd ? endDate : nil),
                suggestedEnd: calendarEventEnd ?? (hasEnd ? endDate : nil),
                durationDays: durationDays
            ) { summary in
                calendarEventCalendarName = summary.calendarTitle
                calendarColorRed = summary.calendarColorRed
                calendarColorGreen = summary.calendarColorGreen
                calendarColorBlue = summary.calendarColorBlue
                calendarColorStored = true
                CalendarScheduleApplier.applyDurationOnly(summary, durationDays: &durationDays)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            dependenciesSection
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

            subtasksSection
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaPills: some View {
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            Menu {
                Button("Priority 1 (highest)") { priority = 4 }
                Button("Priority 2") { priority = 3 }
                Button("Priority 3") { priority = 2 }
                Button("Priority 4") { priority = 1 }
                Divider()
                Button("None") { priority = 0 }
            } label: {
                Label(
                    priority > 0 ? (TaskItem.priorityName(for: priority) ?? "Priority") : "Priority",
                    systemImage: priority > 0 ? "flag.fill" : "flag"
                )
            }
            .buttonStyle(MetaPillButtonStyle(isActive: priority > 0))
        }
    }

    private var dependenciesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showDependencies.toggle() }
            } label: {
                HStack {
                    Image(systemName: showDependencies ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Dependencies")
                        .font(Theme.sans(13, weight: .medium))
                    Spacer()
                    if !dependencyDrafts.isEmpty {
                        Text("\(dependencyDrafts.count)")
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .foregroundStyle(Theme.primary)
            }
            .buttonStyle(.plain)

            if showDependencies {
                if dependencyCandidates.isEmpty {
                    Text("Add other tasks in this category first to link dependencies.")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.muted)
                } else {
                    TaskDependencyDraftEditor(drafts: $dependencyDrafts, candidates: dependencyCandidates)
                }
            }
        }
    }

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showSubtasks.toggle() }
            } label: {
                HStack {
                    Image(systemName: showSubtasks ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Subtasks")
                        .font(Theme.sans(13, weight: .medium))
                    Spacer()
                    Text("\(subtaskDrafts.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }.count)")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.primary)
            }
            .buttonStyle(.plain)

            if showSubtasks {
                ForEach($subtaskDrafts) { $draft in
                    HStack(alignment: .top, spacing: 8) {
                        SubtaskDraftEditor(draft: $draft)
                        if subtaskDrafts.count > 1 {
                            Button {
                                subtaskDrafts.removeAll { $0.id == draft.id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(Theme.muted)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                    }
                }
                Button { subtaskDrafts.append(SubtaskDraft()) } label: {
                    Label("Add subtask", systemImage: "plus")
                        .font(Theme.sans(12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            categoryMenu
            Spacer(minLength: 12)
            Button("Cancel", action: onCancel)
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button("Add task", action: save)
                .buttonStyle(MonoProminentButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var categoryMenu: some View {
        Menu {
            if let allProject = projects.first(where: \.isInbox) {
                Button("All") { selectedProjectID = allProject.persistentModelID }
            }
            ForEach(categories) { cat in
                Button(cat.hashTag) { selectedProjectID = cat.persistentModelID }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "tray.full")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                categoryMenuLabel
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.hover)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private var categoryMenuLabel: some View {
        if let id = selectedProjectID,
           let project = projects.first(where: { $0.persistentModelID == id }),
           project.isUserCategory {
            CategoryTag(project: project, size: 13, weight: .medium)
        } else {
            Text("All")
                .font(Theme.sans(13, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
    }

    private func setupDefaults() {
        let cal = Calendar.current
        if let defaultDueDate {
            hasEnd = true
            endDate = ScheduleDateDefaults.defaultDate(for: .due, on: defaultDueDate)
            hasDueTime = true
        }
        if let defaultProject {
            selectedProjectID = defaultProject.persistentModelID
        } else if let first = categories.first {
            selectedProjectID = first.persistentModelID
        }
        titleFocused = true
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let project: Project? = {
            if let id = selectedProjectID {
                return projects.first { $0.persistentModelID == id }
            }
            return projects.first(where: \.isInbox)
        }()

        let task = TaskItem(
            title: trimmed,
            durationDays: durationDays,
            sortOrder: project?.tasks.count ?? 0,
            dueDate: nil,
            project: project
        )
        task.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.priority = priority
        TaskScheduleApplier.apply(
            to: task,
            durationDays: durationDays,
            hasStart: hasStart,
            startDate: startDate,
            hasEnd: hasEnd,
            endDate: endDate,
            hasDueTime: hasDueTime,
            reminderEnabled: reminderEnabled,
            reminderAt: reminderAt,
            usesCustomReminder: usesCustomReminder,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute
        )
        applyCalendarLink(
            to: task,
            eventID: calendarEventID,
            title: calendarEventTitle,
            start: calendarEventStart,
            end: calendarEventEnd,
            calendarName: calendarEventCalendarName,
            lastSynced: calendarLastSynced,
            colorRed: calendarColorRed,
            colorGreen: calendarColorGreen,
            colorBlue: calendarColorBlue,
            colorStored: calendarColorStored
        )
        for draft in dependencyDrafts {
            guard let from = peerTasks.first(where: { $0.uuid == draft.fromUUID }) else { continue }
            let link = TaskLink(kind: draft.kind, from: from, to: task)
            task.incomingLinks.append(link)
            modelContext.insert(link)
        }

        project?.tasks.append(task)
        modelContext.insert(task)

        for (i, draft) in subtaskDrafts.enumerated() {
            let subTitle = draft.title.trimmingCharacters(in: .whitespaces)
            guard !subTitle.isEmpty else { continue }
            let sub = TaskItem(
                title: subTitle,
                durationDays: 1,
                sortOrder: i,
                dueDate: nil,
                project: project,
                parent: task
            )
            sub.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            TaskScheduleApplier.apply(
                to: sub,
                durationDays: draft.durationDays,
                hasStart: draft.hasStart,
                startDate: draft.startDate,
                hasEnd: draft.hasEnd,
                endDate: draft.endDate,
                hasDueTime: draft.hasDueTime,
                reminderEnabled: draft.reminderEnabled,
                reminderAt: draft.reminderAt,
                usesCustomReminder: draft.usesCustomReminder,
                reminderHour: draft.reminderHour,
                reminderMinute: draft.reminderMinute
            )
            applyCalendarLink(
                to: sub,
                eventID: draft.calendarEventID,
                title: draft.calendarEventTitle,
                start: draft.calendarEventStart,
                end: draft.calendarEventEnd,
                calendarName: draft.calendarEventCalendarName,
                lastSynced: draft.calendarLastSynced,
                colorRed: draft.calendarColorRed,
                colorGreen: draft.calendarColorGreen,
                colorBlue: draft.calendarColorBlue,
                colorStored: draft.calendarColorStored
            )
            task.subtasks.append(sub)
            modelContext.insert(sub)
        }

        PersistenceController.save(modelContext)
        onSaved()
    }

    private func applyCalendarLink(
        to task: TaskItem,
        eventID: String?,
        title: String?,
        start: Date?,
        end: Date?,
        calendarName: String?,
        lastSynced: Date?,
        colorRed: Double,
        colorGreen: Double,
        colorBlue: Double,
        colorStored: Bool
    ) {
        guard let id = eventID, let start, let end else { return }
        let summary = CalendarEventSummary(
            id: id,
            title: title ?? "Untitled event",
            start: start,
            end: end,
            isAllDay: false,
            calendarTitle: calendarName ?? "Calendar",
            calendarColorRed: colorRed,
            calendarColorGreen: colorGreen,
            calendarColorBlue: colorBlue
        )
        task.linkCalendarEvent(summary, updateDuration: false)
        task.calendarLastSyncedAt = lastSynced
    }
}

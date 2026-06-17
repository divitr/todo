import SwiftData
import SwiftUI

struct TaskEditSheet: View {
    @Bindable var task: TaskItem
    let projects: [Project]
    let peerTasks: [TaskItem]
    var onDismiss: () -> Void
    var onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showSubtasks = true
    @State private var showDependencies = false
    @State private var expandedSubtaskID: UUID?

    private var categories: [Project] {
        projects.filter(\.isUserCategory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    headerBlock
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    metaPills
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)

                    TaskScheduleEditorView(task: task)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)

                    if !task.isSubtask {
                        dependenciesSection
                            .padding(.horizontal, 18)
                            .padding(.bottom, 12)

                        subtasksSection
                            .padding(.horizontal, 18)
                            .padding(.bottom, 14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 480)

            Divider().overlay(Theme.border)

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .frame(width: 520)
        .frame(maxHeight: 560)
        .composerChrome()
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.isSubtask ? "Subtask" : "Edit task")
                .font(Theme.sans(12, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField("Title", text: $task.title)
                .font(Theme.sans(18, weight: .semibold))
                .textFieldStyle(.plain)
            TaskNotesSection(notes: $task.notes)
        }
    }

    private var metaPills: some View {
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            Menu {
                Button("Priority 1 (highest)") { task.priority = 4 }
                Button("Priority 2") { task.priority = 3 }
                Button("Priority 3") { task.priority = 2 }
                Button("Priority 4") { task.priority = 1 }
                Divider()
                Button("None") { task.priority = 0 }
            } label: {
                Label(
                    task.priority > 0 ? (task.priorityLabel ?? "Priority") : "Priority",
                    systemImage: task.priority > 0 ? "flag.fill" : "flag"
                )
            }
            .buttonStyle(MetaPillButtonStyle(isActive: task.priority > 0))

            if !task.isSubtask {
                categoryMenu
            }
        }
    }

    private var categoryMenu: some View {
        Menu {
            if let allProject = projects.first(where: \.isInbox) {
                Button("All") { task.project = allProject }
            }
            ForEach(categories) { cat in
                Button(cat.hashTag) { task.project = cat }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "tray.full")
                    .font(.system(size: 11))
                if let project = task.project, project.isUserCategory {
                    CategoryTag(project: project, size: 12, weight: .medium)
                } else {
                    Text("All")
                        .font(Theme.sans(12))
                }
            }
        }
        .buttonStyle(MetaPillButtonStyle(isActive: true))
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
                    if !task.sortedIncomingLinks.isEmpty {
                        Text("\(task.sortedIncomingLinks.count)")
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .foregroundStyle(Theme.primary)
            }
            .buttonStyle(.plain)

            if showDependencies {
                TaskDependencyEditor(task: task, peerTasks: peerTasks, sameCategoryOnly: false)
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
                    Text("\(task.sortedSubtasks.count)")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.primary)
            }
            .buttonStyle(.plain)

            if showSubtasks {
                if task.sortedSubtasks.isEmpty {
                    Text("Add subtasks with their own due dates, reminders, and calendar links.")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(task.displayOrderedSubtasks) { sub in
                        SubtaskEditRow(
                            sub: sub,
                            peerTasks: peerTasks,
                            isExpanded: expandedSubtaskID == sub.uuid,
                            onToggleExpand: {
                                expandedSubtaskID = expandedSubtaskID == sub.uuid ? nil : sub.uuid
                            },
                            onDelete: { modelContext.delete(sub) },
                            onChange: {
                                PersistenceController.save(modelContext)
                            }
                        )
                    }
                }

                Button {
                    let sub = TaskItem(
                        title: "",
                        sortOrder: task.subtasks.count,
                        project: task.project,
                        parent: task
                    )
                    task.subtasks.append(sub)
                    modelContext.insert(sub)
                    expandedSubtaskID = sub.uuid
                    showSubtasks = true
                } label: {
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
            Spacer()
            Button("Cancel", action: onDismiss)
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                PersistenceController.save(modelContext)
                onSaved()
            }
            .buttonStyle(MonoProminentButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(task.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

}

private struct SubtaskEditRow: View {
    @Bindable var sub: TaskItem
    let peerTasks: [TaskItem]
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onDelete: () -> Void
    var onChange: () -> Void

    @State private var showDependencies = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TaskCompletionButton(task: sub, onChange: onChange)

                TextField("Subtask", text: $sub.title)
                    .textFieldStyle(.plain)
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(sub.isComplete ? Theme.muted : Theme.primary)
                    .strikethrough(sub.isComplete)

                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "slider.horizontal.3")
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .help("Schedule, calendar & links")

                Button(action: onDelete) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                TaskNotesSection(notes: $sub.notes, minLines: 2)
                TaskScheduleEditorView(task: sub)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showDependencies.toggle() }
                } label: {
                    HStack {
                        Image(systemName: showDependencies ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Dependencies")
                            .font(Theme.sans(12, weight: .medium))
                        Spacer()
                        if !sub.sortedIncomingLinks.isEmpty {
                            Text("\(sub.sortedIncomingLinks.count)")
                                .font(Theme.sans(10))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)

                if showDependencies {
                    TaskDependencyEditor(task: sub, peerTasks: peerTasks, sameCategoryOnly: false)
                }
            } else {
                subtaskSummary
            }
        }
        .padding(10)
        .background(sub.isComplete ? Theme.hover.opacity(0.5) : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
        .opacity(sub.isComplete ? 0.55 : 1)
    }

    @ViewBuilder
    private var subtaskSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label = DueDateFormatting.taskDueLabel(sub) {
                Text(label)
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.secondary)
            }
            if sub.hasCalendarLink {
                Label("Calendar linked", systemImage: "calendar.badge.checkmark")
                    .font(Theme.sans(10, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            if let rem = DueDateFormatting.reminderLabel(sub) {
                Text(rem)
                    .font(Theme.sans(10))
                    .foregroundStyle(Theme.faint)
            }
        }
    }
}

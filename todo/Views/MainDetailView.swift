import SwiftData
import SwiftUI

struct MainDetailView: View {
    let destination: MainDestination
    let allTasks: [TaskItem]
    let projects: [Project]
    @Binding var displayMode: DetailDisplayMode
    @Binding var boardStart: Date
    @Binding var isComposing: Bool
    var ganttViewportStore: GanttViewportStore
    var onReschedule: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var editingTask: TaskItem?

    private var categories: [Project] {
        projects.filter(\.isUserCategory).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var selectedProject: Project? {
        if case .category(let id) = destination {
            return projects.first { $0.persistentModelID == id }
        }
        return nil
    }

    private var isAllView: Bool {
        destination == .inbox
    }

    private var usesTaskList: Bool {
        destination == .today
    }

    private var usesFullWidthDetail: Bool {
        effectiveDisplayMode == .gantt
    }

    private var effectiveDisplayMode: DetailDisplayMode {
        if usesTaskList { return .list }
        if destination == .upcoming { return .board }
        return displayMode
    }

    private var defaultProject: Project? {
        if let selected = selectedProject, selected.isUserCategory {
            return selected
        }
        return projects.first(where: \.isInbox)
    }

    private var defaultDueDate: Date? {
        switch destination {
        case .today: Calendar.current.startOfDay(for: .now)
        default: nil
        }
    }

    private var listRoots: [TaskItem] {
        switch destination {
        case .inbox:
            return TaskHierarchy.roots(in: allTasks)
        case .today:
            return TaskHierarchy.rootsMatching(in: allTasks) { $0.matchesTodayList }
        case .category(let id):
            guard let project = projects.first(where: { $0.persistentModelID == id }) else { return [] }
            return TaskHierarchy.rootsMatching(in: allTasks) {
                $0.project?.persistentModelID == project.persistentModelID
            }
        default:
            return []
        }
    }

    private var openDisplayRows: [TaskDisplayRow] {
        let roots = listRoots.filter { !$0.isComplete }
        let rows = TaskHierarchy.flatten(roots: roots, includeCompleted: true)
        guard destination == .today else { return rows }
        return TaskHierarchy.applyTodaySingleSubtaskEmphasis(rows: rows, roots: roots)
    }

    private var completedDisplayRows: [TaskDisplayRow] {
        TaskHierarchy.flatten(roots: listRoots.filter(\.isComplete), includeCompleted: true)
    }

    private var hasOpenRows: Bool { !openDisplayRows.isEmpty }
    private var hasCompletedRows: Bool { !completedDisplayRows.isEmpty }

    private var editSheetPresented: Binding<Bool> {
        Binding(
            get: { editingTask != nil },
            set: { if !$0 { editingTask = nil } }
        )
    }

    private var ganttTasks: [TaskItem] {
        switch destination {
        case .inbox:
            return allTasks
        case .category(let id):
            guard let project = projects.first(where: { $0.persistentModelID == id }) else { return [] }
            return allTasks.filter { $0.project?.persistentModelID == project.persistentModelID }
        default:
            return allTasks
        }
    }

    private var listRowStyle: TaskListRowStyle {
        switch destination {
        case .inbox, .today:
            return .inbox
        default:
            return .category
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if destination != .upcoming {
                detailHeader
                Divider().overlay(Theme.border)
            }

            Group {
                switch destination {
                case .upcoming:
                    UpcomingBoardView(
                        allTasks: allTasks,
                        projects: projects,
                        boardStart: $boardStart,
                        onChange: onReschedule
                    )
                default:
                    if effectiveDisplayMode == .gantt {
                        GanttChartView(
                            viewport: ganttViewportStore.state(for: destination),
                            tasks: ganttTasks,
                            colorByCategory: isAllView,
                            onEditTask: { editingTask = $0 }
                        )
                    } else {
                        taskListBody
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .appBackground()
        .onAppear { onReschedule() }
        .sheet(isPresented: editSheetPresented) {
            if let task = editingTask {
                TaskEditSheet(
                    task: task,
                    projects: projects,
                    peerTasks: allTasks,
                    onDismiss: { editingTask = nil },
                    onSaved: {
                        editingTask = nil
                        onReschedule()
                    }
                )
            }
        }
    }

    private var detailHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                headerTitleView
                if let subtitle = headerSubtitle {
                    headerSubtitleView(subtitle)
                }
            }
            Spacer(minLength: 12)

            if !usesTaskList {
                Picker("", selection: $displayMode) {
                    Text("List").tag(DetailDisplayMode.list)
                    Text("Gantt").tag(DetailDisplayMode.gantt)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
        }
        .detailContentWidth(fullWidth: usesFullWidthDetail)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func headerSubtitleView(_ text: String) -> some View {
        if destination == .today {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Text(text)
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.muted)
            }
        } else {
            Text(text)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private var headerTitleView: some View {
        switch destination {
        case .category(let id):
            if let project = projects.first(where: { $0.persistentModelID == id }) {
                Text(project.listTitle)
                    .font(Theme.sans(28, weight: .bold))
                    .foregroundStyle(Theme.primary)
            } else {
                Text("Category")
                    .font(Theme.sans(28, weight: .bold))
            }
        default:
            Text(headerTitle)
                .font(Theme.sans(28, weight: .bold))
                .foregroundStyle(Theme.primary)
        }
    }

    private var headerTitle: String {
        switch destination {
        case .inbox: "All"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .category(let id):
            projects.first { $0.persistentModelID == id }?.hashTag ?? "Category"
        }
    }

    private var headerSubtitle: String? {
        switch destination {
        case .inbox:
            let count = allTasks.filter { !$0.isComplete }.count
            return "\(count) open · color-coded by category"
        case .today:
            let blocked = TaskFilters.blockedToday(allTasks).count
            let due = TaskFilters.dueTodayExcludingBlocked(allTasks).count
            if blocked == 0 && due == 0 { return "Nothing today" }
            var parts: [String] = []
            if blocked > 0 { parts.append("\(blocked) blocked") }
            if due > 0 { parts.append("\(due) due") }
            return parts.joined(separator: " · ")
        case .category(let id):
            guard let project = projects.first(where: { $0.persistentModelID == id }) else { return nil }
            return "\(project.openTaskCount) open"
        default:
            return nil
        }
    }

    private var taskListBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !hasOpenRows && !hasCompletedRows && !isComposing {
                    listEmptyState
                } else {
                    taskListSection(rows: openDisplayRows)

                    if hasCompletedRows {
                        if hasOpenRows {
                            CompletedTasksSectionHeader()
                                .padding(.top, 20)
                                .padding(.bottom, 8)
                        }
                        taskListSection(rows: completedDisplayRows)
                    }
                }

                composerSection
                    .padding(.top, (!hasOpenRows && !hasCompletedRows) && !isComposing ? 16 : 4)
            }
            .centeredDetailColumn()
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func taskListSection(rows: [TaskDisplayRow]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            TaskListRowView(
                task: row.task,
                style: listRowStyle,
                depth: row.depth,
                todayEmphasis: row.todayEmphasis,
                onChange: onReschedule,
                onEdit: { editingTask = row.task }
            )
            .contextMenu { taskContextMenu(for: row.task) }

            if index < rows.count - 1 {
                ListRowDivider(leadingInset: 38 + CGFloat(row.depth) * 20)
            }
        }
    }

    private var listEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.muted)
            Text(emptyTitle)
                .font(Theme.sans(16, weight: .semibold))
                .foregroundStyle(Theme.primary)
            Text(emptyMessage)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: 360, alignment: .leading)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var composerSection: some View {
        if isComposing {
            AddTaskComposerView(
                projects: projects,
                defaultProject: defaultProject,
                defaultDueDate: defaultDueDate,
                peerTasks: allTasks,
                embeddedInList: true,
                onCancel: { isComposing = false },
                onSaved: {
                    isComposing = false
                    onReschedule()
                }
            )
            .padding(.top, 8)
        } else {
            ListAddTaskButton { isComposing = true }
        }
    }

    @ViewBuilder
    private func taskContextMenu(for task: TaskItem) -> some View {
        Button("Edit task…") { editingTask = task }

        Button("Add subtask…") {
            let sub = TaskItem(
                title: "",
                sortOrder: task.subtasks.count,
                dueDate: task.dueDate,
                project: task.project,
                parent: task
            )
            task.subtasks.append(sub)
            modelContext.insert(sub)
            editingTask = sub
        }

        if !categories.isEmpty {
            Menu("Move to category") {
                ForEach(categories) { cat in
                    Button(cat.hashTag) {
                        task.project = cat
                        onReschedule()
                    }
                }
            }
        }

        Button(task.reminderEnabled ? "Turn off reminder" : "Remind me") {
            task.reminderEnabled.toggle()
            if task.reminderEnabled, task.dueDate != nil {
                Task { await ReminderScheduleHelper.syncNotification(for: task) }
            } else {
                NotificationScheduler.shared.cancel(task: task)
            }
            onReschedule()
        }
        .disabled(task.dueDate == nil)

        Button("Clear due date", role: .destructive) {
            task.dueDate = nil
            task.reminderEnabled = false
            NotificationScheduler.shared.cancel(task: task)
            onReschedule()
        }

        Button("Delete task", role: .destructive) {
            deleteTask(task)
        }
    }

    private func deleteTask(_ task: TaskItem) {
        NotificationScheduler.shared.cancel(task: task)
        for sub in task.subtasks {
            NotificationScheduler.shared.cancel(task: sub)
        }
        modelContext.delete(task)
        onReschedule()
    }

    private var emptyTitle: String {
        "No tasks"
    }

    private var emptyMessage: String {
        "Add a task below."
    }
}

import SwiftData
import SwiftUI
import WidgetKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskItem.sortOrder) private var allTasks: [TaskItem]

    @State private var destination: MainDestination = .upcoming
    @State private var displayMode: DetailDisplayMode = .list
    @State private var boardStart = Calendar.current.startOfDay(for: .now)
    @State private var isComposing = false
    @State private var showAddTaskSheet = false
    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryColor = Project.defaultPaletteColor(at: 0)
    @State private var editingCategory: Project?
    @State private var ganttViewportStore = GanttViewportStore()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                destination: $destination,
                projects: projects,
                allTasks: allTasks,
                onEditCategory: { project in
                    guard project.isUserCategory else { return }
                    editingCategory = project
                },
                onAddTask: {
                    if destination == .upcoming {
                        showAddTaskSheet = true
                    } else {
                        isComposing = true
                    }
                },
                onAddCategory: { showAddCategory = true }
            )
        } detail: {
            MainDetailView(
                destination: destination,
                allTasks: allTasks,
                projects: projects,
                displayMode: $displayMode,
                boardStart: $boardStart,
                isComposing: $isComposing,
                ganttViewportStore: ganttViewportStore,
                onReschedule: persistChanges
            )
            .appAccentColor(appAccentColor)
        }
        .appBackground()
        .onAppear {
            ensureSystemProjects()
            migrateLegacyAllAggregateSelection()
            ensureSampleCategoriesIfNeeded()
            TaskLinkMigration.migrateAll(context: modelContext)
            CalendarSyncService.shared.start()
            syncDisplayModeForDestination()
            persistChanges()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                CalendarSyncService.shared.beginActiveRefresh()
                Task { await refreshCalendarAndPersist() }
            case .inactive, .background:
                CalendarSyncService.shared.endActiveRefresh()
                persistChanges()
            default:
                break
            }
        }
        .onChange(of: destination) { new in
            isComposing = false
            if new == .upcoming {
                boardStart = Calendar.current.startOfDay(for: .now)
            }
            syncDisplayModeForDestination()
        }
        .sheet(isPresented: $showAddTaskSheet) {
            AddTaskSheet(
                projects: projects,
                peerTasks: allTasks,
                onDismiss: {
                    showAddTaskSheet = false
                    persistChanges()
                }
            )
        }
        .sheet(isPresented: $showAddCategory) {
            newCategorySheet
        }
        .sheet(item: $editingCategory) { project in
            CategoryEditorSheet(project: project) {
                editingCategory = nil
            } onSaved: {
                editingCategory = nil
                persistChanges()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTask)) { _ in
            if destination == .upcoming {
                showAddTaskSheet = true
            } else {
                isComposing = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in
            destination = .today
        }
        .onReceive(NotificationCenter.default.publisher(for: .externalStoreChanged)) { _ in
            modelContext.processPendingChanges()
            persistChanges()
        }
    }

    private var newCategorySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New category")
                .font(Theme.sans(20, weight: .bold))
            Text("Shown as #name in the sidebar.")
                .font(Theme.sans(13))
                .foregroundStyle(Theme.muted)
            TextField("e.g. school", text: $newCategoryName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("Bar color")
                    .font(Theme.sans(13))
                Spacer()
                ColorPicker("", selection: $newCategoryColor, supportsOpacity: false)
                    .labelsHidden()
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    showAddCategory = false
                    newCategoryName = ""
                }
                Button("Create") { createCategory() }
                    .buttonStyle(MonoProminentButtonStyle())
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func syncDisplayModeForDestination() {
        switch destination {
        case .upcoming:
            displayMode = .board
        case .inbox:
            displayMode = .list
        case .today:
            displayMode = .list
        case .category:
            break
        }
    }

    private func migrateLegacyAllAggregateSelection() {
        if case .category(let id) = destination,
           let project = projects.first(where: { $0.persistentModelID == id }),
           project.isAllAggregate {
            destination = .inbox
        }
    }

    private func ensureSystemProjects() {
        if projects.first(where: \.isInbox) == nil {
            let inbox = Project(name: "Inbox", sortOrder: -2, colorHue: 0.55, isInbox: true)
            modelContext.insert(inbox)
        }
        PersistenceController.save(modelContext)
    }

    private func ensureSampleCategoriesIfNeeded() {
        guard projects.filter(\.isUserCategory).isEmpty else { return }

        let samples: [(String, Double)] = [
            ("school", 0.25),
            ("research", 0.45),
            ("personal/misc", 0.65),
        ]
        for (index, sample) in samples.enumerated() {
            let cat = Project(
                name: sample.0,
                sortOrder: index + 1,
                colorHue: sample.1,
                isInbox: false
            )
            cat.applyColor(Project.defaultPaletteColor(at: index))
            modelContext.insert(cat)
        }
        persistChanges()
    }

    private func createCategory() {
        let name = Project.normalizedCategoryName(newCategoryName)
        guard !name.isEmpty, name.lowercased() != "all" else { return }
        let hue = Project.defaultCategoryHues[categories.count % Project.defaultCategoryHues.count]
        let cat = Project(name: name, sortOrder: projects.count, colorHue: hue, isInbox: false)
        cat.applyColor(newCategoryColor)
        modelContext.insert(cat)
        persistChanges()
        destination = .category(cat.persistentModelID)
        newCategoryName = ""
        newCategoryColor = Project.defaultPaletteColor(at: categories.count)
        showAddCategory = false
    }

    private var categories: [Project] {
        projects.filter(\.isUserCategory)
    }

    private var appAccentColor: Color {
        if destination == .inbox {
            return Theme.defaultAccent
        }
        if case .category(let id) = destination,
           let project = projects.first(where: { $0.persistentModelID == id }) {
            return project.accentTint
        }
        return Theme.defaultAccent
    }

    private func persistChanges() {
        Task { @MainActor in
            await refreshCalendarAndPersist()
        }
    }

    @MainActor
    private func refreshCalendarAndPersist() async {
        let tasks = allTasks
        let calendarChanged = await CalendarSyncService.shared.refreshLinkedTasks(tasks)
            || CalendarSyncService.shared.shouldRunPendingRefresh

        Scheduler.reschedule(tasks: tasks)

        PersistenceController.save(modelContext)

        await NotificationScheduler.shared.syncAll(tasks: tasks)
        WidgetCenter.shared.reloadAllTimelines()

        if calendarChanged {
            CalendarSyncService.shared.clearPendingRefresh()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PersistenceController.shared)
}

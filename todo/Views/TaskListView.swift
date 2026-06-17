import SwiftData
import SwiftUI

struct TaskListView: View {
    @Bindable var project: Project
    let tasks: [TaskItem]
    var onChange: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if tasks.isEmpty {
            ContentUnavailableView("No tasks", systemImage: "checklist", description: Text("Add a task above."))
                .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(tasks) { task in
                    TaskRowView(
                        task: task,
                        allTasks: tasks,
                        onChange: onChange
                    )
                }
                .onDelete(perform: deleteTasks)
            }
            .listStyle(.inset)
        }
    }

    private func deleteTasks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tasks[index])
        }
        onChange()
        try? modelContext.save()
    }
}

import SwiftData
import SwiftUI

struct TaskRowView: View {
    @Bindable var task: TaskItem
    let allTasks: [TaskItem]
    var onChange: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Toggle("", isOn: $task.isComplete)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .onChange(of: task.isComplete) { _ in onChange() }

                TextField("Task", text: $task.title)
                    .textFieldStyle(.plain)
                    .strikethrough(task.isComplete)
                    .onSubmit { onChange() }

                Spacer()

                if let start = task.scheduledStart {
                    Text(dateRangeLabel(start: start, end: task.scheduledEnd))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                detailFields
            }
        }
        .padding(.vertical, 4)
    }

    private var detailFields: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Duration (days)").foregroundStyle(.secondary)
                TextField("Days", value: $task.durationDays, format: .number)
                    .frame(width: 60)
                    .onChange(of: task.durationDays) { _ in onChange() }
            }
            GridRow {
                Text("Due date").foregroundStyle(.secondary)
                DatePicker("", selection: dueDateBinding, displayedComponents: .date)
                    .labelsHidden()
            }
            GridRow {
                Text("After task").foregroundStyle(.secondary)
                Picker("", selection: predecessorBinding) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(predecessorCandidates, id: \.uuid) { other in
                        Text(other.title.isEmpty ? "Untitled" : other.title)
                            .tag(Optional(other.uuid))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }
            GridRow {
                Text("Fixed start").foregroundStyle(.secondary)
                Toggle("", isOn: $task.useManualStart)
                    .labelsHidden()
                    .onChange(of: task.useManualStart) { _ in onChange() }
                if task.useManualStart {
                    DatePicker("", selection: manualStartBinding, displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
        .font(.caption)
        .padding(.leading, 28)
    }

    private var predecessorCandidates: [TaskItem] {
        allTasks.filter { $0.persistentModelID != task.persistentModelID }
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { task.dueDate ?? Date() },
            set: { task.dueDate = $0; onChange() }
        )
    }

    private var manualStartBinding: Binding<Date> {
        Binding(
            get: { task.manualStart ?? Date() },
            set: { task.manualStart = $0; onChange() }
        )
    }

    private var predecessorBinding: Binding<UUID?> {
        Binding(
            get: { task.predecessor?.uuid },
            set: { newID in
                if let newID {
                    task.predecessor = allTasks.first { $0.uuid == newID }
                } else {
                    task.predecessor = nil
                }
                onChange()
            }
        )
    }

    private func dateRangeLabel(start: Date, end: Date?) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        if let end {
            return "\(f.string(from: start)) – \(f.string(from: end))"
        }
        return f.string(from: start)
    }
}

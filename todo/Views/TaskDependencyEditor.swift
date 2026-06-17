import SwiftData
import SwiftUI

struct TaskDependencyEditor: View {
    @Bindable var task: TaskItem
    let peerTasks: [TaskItem]
    var sameCategoryOnly: Bool = true

    @Environment(\.modelContext) private var modelContext
    @State private var newFromID: UUID?
    @State private var newKind: TaskLinkKind = .finishToStart

    private var candidates: [TaskItem] {
        TaskHierarchy.candidatePredecessors(for: task, in: peerTasks, sameCategoryOnly: sameCategoryOnly)
            .sorted { lhs, rhs in
                let ls = lhs.parent?.uuid == task.parent?.uuid && lhs.uuid != task.uuid
                let rs = rhs.parent?.uuid == task.parent?.uuid && rhs.uuid != task.uuid
                if ls != rs { return ls }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var predecessorPickerLabel: String {
        task.parent == nil ? "Task in category" : "Predecessor"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dependencies")
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.muted)

            if task.sortedIncomingLinks.isEmpty {
                Text("No links yet — add what must happen before this task can start or finish.")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.faint)
            } else {
                ForEach(task.sortedIncomingLinks, id: \.uuid) { link in
                    linkRow(link)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Add link")
                    .font(Theme.sans(11, weight: .medium))
                    .foregroundStyle(Theme.muted)

                Picker("Type", selection: $newKind) {
                    ForEach(TaskLinkKind.allCases) { kind in
                        Text("\(kind.shortCode) · \(kind.label)").tag(kind)
                    }
                }
                .font(Theme.sans(12))

                Picker(predecessorPickerLabel, selection: $newFromID) {
                    Text("Choose task…").tag(Optional<UUID>.none)
                    ForEach(candidates, id: \.uuid) { other in
                        Text(predecessorLabel(for: other)).tag(Optional(other.uuid))
                    }
                }
                .labelsHidden()

                Button("Add dependency") { addLink() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(newFromID == nil)
            }
        }
        .padding(12)
        .background(Theme.hover)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.border, lineWidth: 0.5))
    }

    private func linkRow(_ link: TaskLink) -> some View {
        HStack(spacing: 8) {
            Text(link.kind.shortCode)
                .font(Theme.sans(11, weight: .bold))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.fromTask?.title ?? "Task")
                    .font(Theme.sans(12, weight: .medium))
                    .lineLimit(1)
                Text(link.kind.label)
                    .font(Theme.sans(10))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { link.kind },
                set: { link.kind = $0 }
            )) {
                ForEach(TaskLinkKind.allCases) { kind in
                    Text(kind.shortCode).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 64)

            Button {
                task.incomingLinks.removeAll { $0.uuid == link.uuid }
                modelContext.delete(link)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
        }
    }

    private func predecessorLabel(for other: TaskItem) -> String {
        let name = other.title.isEmpty ? "Untitled" : other.title
        if let parent = task.parent, other.parent?.uuid == parent.uuid {
            return name
        }
        if task.parent != nil, other.uuid == task.parent?.uuid {
            return "\(name) (parent task)"
        }
        return name
    }

    private func addLink() {
        guard let id = newFromID,
              let from = candidates.first(where: { $0.uuid == id }) else { return }
        guard !task.incomingLinks.contains(where: { $0.fromTask?.uuid == id }) else { return }
        guard !TaskHierarchy.wouldCreateDependencyCycle(from: from, to: task) else { return }
        let link = TaskLink(kind: newKind, from: from, to: task)
        task.incomingLinks.append(link)
        modelContext.insert(link)
        task.predecessor = nil
    }
}

import SwiftUI

struct DependencyDraft: Identifiable {
    let id = UUID()
    var fromUUID: UUID
    var kind: TaskLinkKind
}

struct TaskDependencyDraftEditor: View {
    @Binding var drafts: [DependencyDraft]
    let candidates: [TaskItem]

    @State private var newFromID: UUID?
    @State private var newKind: TaskLinkKind = .finishToStart

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dependencies")
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.muted)

            if drafts.isEmpty {
                Text("Optional — link to other tasks in this category (FS, SS, FF, SF).")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.faint)
            } else {
                ForEach($drafts) { $draft in
                    HStack(spacing: 8) {
                        Text(draft.kind.shortCode)
                            .font(Theme.sans(11, weight: .bold))
                            .frame(width: 26)
                        Text(candidates.first { $0.uuid == draft.fromUUID }?.title ?? "Task")
                            .font(Theme.sans(12))
                            .lineLimit(1)
                        Spacer()
                        Picker("", selection: $draft.kind) {
                            ForEach(TaskLinkKind.allCases) { k in
                                Text(k.shortCode).tag(k)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 64)
                        Button { drafts.removeAll { $0.id == draft.id } } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Theme.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Picker("Type", selection: $newKind) {
                ForEach(TaskLinkKind.allCases) { kind in
                    Text("\(kind.shortCode) · \(kind.label)").tag(kind)
                }
            }
            .font(Theme.sans(12))

            Picker("Task in category", selection: $newFromID) {
                Text("Choose task…").tag(Optional<UUID>.none)
                ForEach(candidates, id: \.uuid) { other in
                    Text(other.title.isEmpty ? "Untitled" : other.title).tag(Optional(other.uuid))
                }
            }
            .labelsHidden()

            Button("Add dependency") {
                guard let id = newFromID else { return }
                guard !drafts.contains(where: { $0.fromUUID == id }) else { return }
                drafts.append(DependencyDraft(fromUUID: id, kind: newKind))
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(newFromID == nil || candidates.isEmpty)
        }
        .padding(12)
        .background(Theme.hover)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.border, lineWidth: 0.5))
        .onChange(of: candidates.count) { _, _ in
            if let id = newFromID, !candidates.contains(where: { $0.uuid == id }) {
                newFromID = nil
            }
        }
    }
}

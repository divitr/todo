import SwiftData
import SwiftUI

struct TaskCardView: View {
    @Bindable var task: TaskItem
    var isSelected: Bool = false
    var onChange: () -> Void
    var onSelect: (() -> Void)? = nil
    var onEdit: (() -> Void)?

    @Environment(\.appAccent) private var accent
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TaskCompletionButton(task: task, onChange: onChange)

            VStack(alignment: .leading, spacing: 8) {
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(task.isComplete ? Theme.muted : Theme.primary)
                    .strikethrough(task.isComplete)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let project = task.project, project.isUserCategory {
                    CategoryTag(project: project, size: 12, weight: .medium)
                }

                if task.scheduleConflict != nil {
                    Label("Past due", systemImage: "exclamationmark.triangle")
                        .font(Theme.sans(10, weight: .medium))
                        .foregroundStyle(Theme.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect?()
                onEdit?()
            }
        }
        .padding(12)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(cardBorder, lineWidth: isSelected ? 1.5 : 0.5)
        )
        .onHover { isHovered = $0 }
        .opacity(task.isComplete ? 0.55 : 1)
        .help("Click task to edit")
    }

    private var cardBackground: Color {
        if isSelected { return Theme.softAccentFill(accent, opacity: 0.12) }
        if isHovered { return Theme.hover }
        return Theme.background
    }

    private var cardBorder: Color {
        if isSelected { return Theme.softAccentStroke(accent, opacity: 0.55) }
        return Theme.border
    }
}

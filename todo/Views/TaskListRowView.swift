import SwiftData
import SwiftUI

enum TaskListRowStyle {
    case category
    case inbox
}

struct TaskListRowView: View {
    @Bindable var task: TaskItem
    var style: TaskListRowStyle = .category
    var depth: Int = 0
    var todayEmphasis: TodayListEmphasis?
    var onChange: () -> Void
    var onEdit: (() -> Void)?

    @State private var isHovered = false

    private var isSubtaskRow: Bool { depth > 0 }

    private var rowOpacity: Double {
        if task.isComplete { return isSubtaskRow ? 0.42 : 0.5 }
        if todayEmphasis == .context { return 0.42 }
        return 1
    }

    private var titleWeight: Font.Weight {
        if todayEmphasis == .focus { return .semibold }
        return isSubtaskRow ? .regular : .regular
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if depth > 0 {
                Color.clear.frame(width: CGFloat(depth) * 20)
            }

            TaskCompletionButton(task: task, onChange: onChange)
                .padding(.top, style == .category ? 2 : 0)

            if !task.isComplete {
                TodayPlanToggle(task: task, onChange: onChange)
                    .padding(.top, style == .category ? 1 : 0)
            }

            Button {
                onEdit?()
            } label: {
                rowContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, isSubtaskRow ? 10 : (style == .category ? 14 : 12))
        .padding(.leading, isSubtaskRow ? 4 : 0)
        .background(isHovered ? Theme.hover.opacity(0.65) : Color.clear)
        .onHover { isHovered = $0 }
        .opacity(rowOpacity)
    }

    @ViewBuilder
    private var rowContent: some View {
        switch style {
        case .category:
            categoryLayout
        case .inbox:
            inboxLayout
        }
    }

    private var categoryLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleText(size: isSubtaskRow ? 14 : 16)

            if let due = dueDateLine {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text(due)
                        .font(Theme.sans(12, weight: .medium))
                }
                .foregroundStyle(Theme.dueAccent)
            }

            secondaryMeta

            if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(task.notes)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
        }
    }

    private var inboxLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                titleText(size: isSubtaskRow ? 14 : 16)
                secondaryMeta
                if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(task.notes)
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if !isSubtaskRow, let project = task.project, project.isUserCategory {
                CategoryTag(project: project, size: 13, weight: .medium)
                    .padding(.top, 2)
            }
        }
    }

    private func titleText(size: CGFloat) -> some View {
        HStack(spacing: 6) {
            if isSubtaskRow {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.faint)
            }
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(Theme.sans(size, weight: titleWeight))
                .foregroundStyle(task.isComplete ? Theme.muted : Theme.primary)
                .strikethrough(task.isComplete)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var secondaryMeta: some View {
        if task.isBlockedToday {
            HStack(spacing: 8) {
                Label(
                    task.isCalendarBlockedToday && !task.planForToday ? "On calendar today" : "Today",
                    systemImage: "calendar.day.timeline.left"
                )
                .font(Theme.sans(10, weight: .medium))
                .foregroundStyle(Theme.todayLine)
                if let time = task.todayBlockTimeLabel {
                    Text(time)
                        .font(Theme.sans(10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
        } else if style == .inbox, let due = dueDateLine {
            Text(due)
                .font(Theme.sans(11, weight: .medium))
                .foregroundStyle(Theme.dueAccent)
        } else if task.scheduleConflict != nil || task.hasCalendarLink {
            HStack(spacing: 10) {
                if task.scheduleConflict != nil {
                    Label("Past due", systemImage: "exclamationmark.triangle")
                        .font(Theme.sans(10, weight: .medium))
                        .foregroundStyle(Theme.primary)
                }
                if task.hasCalendarLink {
                    Label("Calendar", systemImage: "calendar.badge.checkmark")
                        .font(Theme.sans(10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var dueDateLine: String? {
        DueDateFormatting.taskDueLabel(task)
    }
}

import SwiftData
import SwiftUI

private struct DaySlot: Identifiable {
    let day: Date
    var id: Date { day }
}

struct UpcomingBoardView: View {
    let allTasks: [TaskItem]
    let projects: [Project]
    @Binding var boardStart: Date
    var onChange: () -> Void

    @State private var addTaskDay: DaySlot?
    @State private var editingTask: TaskItem?
    @State private var highlightedTaskID: UUID?

    private let columnCount = 7
    private let columnSpacing: CGFloat = 10

    private var days: [Date] {
        TaskFilters.upcomingDays(from: boardStart, count: columnCount)
    }

    private var weekRangeLabel: String {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: columnCount - 1, to: boardStart) ?? boardStart
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: boardStart)) – \(f.string(from: end))"
    }

    private var editSheetPresented: Binding<Bool> {
        Binding(
            get: { editingTask != nil },
            set: { if !$0 { editingTask = nil } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            boardHeader

            GeometryReader { geometry in
                let totalSpacing = columnSpacing * CGFloat(columnCount - 1)
                let innerWidth = max(geometry.size.width, 0)
                let columnWidth = max((innerWidth - totalSpacing) / CGFloat(columnCount), 100)

                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(days, id: \.self) { day in
                        dayColumn(day)
                            .frame(width: columnWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .id(boardStart.timeIntervalSinceReferenceDate)
                .frame(width: innerWidth, height: geometry.size.height, alignment: .topLeading)
                .padding(.vertical, 12)
            }
            .detailContentWidth(fullWidth: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $addTaskDay) { slot in
            AddTaskSheet(
                projects: projects,
                defaultDueDate: slot.day,
                defaultProject: projects.first(where: \.isInbox),
                peerTasks: allTasks,
                onDismiss: { addTaskDay = nil; onChange() }
            )
        }
        .sheet(isPresented: editSheetPresented) {
            if let task = editingTask {
                TaskEditSheet(
                    task: task,
                    projects: projects,
                    peerTasks: allTasks,
                    onDismiss: { editingTask = nil },
                    onSaved: {
                        editingTask = nil
                        onChange()
                    }
                )
            }
        }
    }

    private var boardHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Upcoming")
                    .font(Theme.sans(28, weight: .bold))
                    .foregroundStyle(Theme.primary)
                Text("Next 7 days · \(weekRangeLabel)")
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 12)
            boardNavControls
        }
        .detailContentWidth(fullWidth: true)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .background(Theme.background)
    }

    private var boardNavControls: some View {
        HStack(spacing: 4) {
            navChevron("chevron.left", help: "Previous 7 days") {
                shiftBoard(by: -columnCount)
            }

            Button {
                boardStart = Calendar.current.startOfDay(for: .now)
            } label: {
                Text("Today")
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.hover)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            navChevron("chevron.right", help: "Next 7 days") {
                shiftBoard(by: columnCount)
            }
        }
    }

    private func navChevron(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func shiftBoard(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: boardStart) else { return }
        highlightedTaskID = nil
        boardStart = Calendar.current.startOfDay(for: next)
    }

    private func dayColumn(_ day: Date) -> some View {
        let tasks = TaskFilters.sortedByDueDate(
            TaskFilters.on(day: day, tasks: allTasks)
        )

        return VStack(alignment: .leading, spacing: 10) {
            dayColumnHeader(day: day, count: tasks.count)

            if tasks.isEmpty {
                Text("No tasks")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.faint)
                Spacer(minLength: 0)
            } else {
                ForEach(tasks) { task in
                    TaskCardView(
                        task: task,
                        isSelected: highlightedTaskID == task.uuid,
                        onChange: onChange,
                        onSelect: { highlightedTaskID = task.uuid },
                        onEdit: { editingTask = task }
                    )
                }
                Spacer(minLength: 0)
            }

            Button {
                addTaskDay = DaySlot(day: day)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Add task")
                        .font(Theme.sans(12, weight: .medium))
                }
                .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dayColumnHeader(day: Date, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(columnHeaderTitle(day))
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Calendar.current.isDateInToday(day) ? Theme.primary : Theme.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text("\(count)")
                .font(Theme.sans(12))
                .foregroundStyle(Theme.faint)
        }
        .padding(.bottom, 4)
    }

    private func columnHeaderTitle(_ day: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let datePart = f.string(from: day)
        let relative = DueDateFormatting.label(for: day)
        if Calendar.current.isDateInToday(day) {
            return "\(datePart) · Today"
        }
        return "\(datePart) · \(relative)"
    }
}

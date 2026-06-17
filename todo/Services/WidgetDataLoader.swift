import Foundation
import SwiftData

struct WidgetTaskSummary: Identifiable {
    let id: UUID
    let title: String
    let category: String?
    let detail: String?
}

enum WidgetAgendaSection {
    case blocked
    case due
}

struct WidgetAgendaItem: Identifiable {
    let id: UUID
    let title: String
    let category: String?
    let timeLabel: String
    let section: WidgetAgendaSection
    let sortKey: Date
}

struct TodayAgendaWidgetData {
    let blocked: [WidgetAgendaItem]
    let dueToday: [WidgetAgendaItem]
    let blockedCount: Int
    let dueTodayCount: Int

    var isEmpty: Bool { blocked.isEmpty && dueToday.isEmpty }
    var totalCount: Int { blockedCount + dueTodayCount }
}

struct MenuBarTodayData {
    let blocked: [WidgetTaskSummary]
    let dueToday: [WidgetTaskSummary]
    let dueTomorrow: [WidgetTaskSummary]
    let blockedCount: Int
    let dueTodayCount: Int
    let dueTomorrowCount: Int

    var isEmpty: Bool { blocked.isEmpty && dueToday.isEmpty && dueTomorrow.isEmpty }
    var totalCount: Int { blockedCount + dueTodayCount + dueTomorrowCount }
}

enum WidgetDataLoader {
    private static let menuBarLimit = 8

    static func loadMenuBarToday() -> MenuBarTodayData {
        let context = ModelContext(PersistenceController.shared)
        let descriptor = FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.sortOrder)])
        guard let all = try? context.fetch(descriptor) else {
            return MenuBarTodayData(
                blocked: [], dueToday: [], dueTomorrow: [],
                blockedCount: 0, dueTodayCount: 0, dueTomorrowCount: 0
            )
        }

        let blockedTasks = TaskFilters.sortedByDueDate(TaskFilters.blockedToday(all))
        let dueTodayTasks = TaskFilters.sortedByDueDate(TaskFilters.dueTodayExcludingBlocked(all))
        let dueTomorrowTasks = TaskFilters.sortedByDueDate(TaskFilters.dueTomorrow(all))

        return MenuBarTodayData(
            blocked: blockedTasks.prefix(menuBarLimit).map(summary(for:)),
            dueToday: dueTodayTasks.prefix(menuBarLimit).map(summary(for:)),
            dueTomorrow: dueTomorrowTasks.prefix(menuBarLimit).map(summary(for:)),
            blockedCount: blockedTasks.count,
            dueTodayCount: dueTodayTasks.count,
            dueTomorrowCount: dueTomorrowTasks.count
        )
    }

    static func loadToday() -> (tasks: [WidgetTaskSummary], totalOpen: Int) {
        let data = loadMenuBarToday()
        let combined = data.blocked + data.dueToday
        return (Array(combined.prefix(menuBarLimit)), data.blockedCount + data.dueTodayCount)
    }

    static func loadTodayAgenda(blockedLimit: Int = 10, dueLimit: Int = 6) -> TodayAgendaWidgetData {
        let context = ModelContext(PersistenceController.shared)
        let descriptor = FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.sortOrder)])
        guard let all = try? context.fetch(descriptor) else {
            return TodayAgendaWidgetData(blocked: [], dueToday: [], blockedCount: 0, dueTodayCount: 0)
        }

        let blockedTasks = TaskFilters.sortedByDueDate(TaskFilters.blockedToday(all))
        let dueTasks = TaskFilters.sortedByDueDate(TaskFilters.dueTodayExcludingBlocked(all))

        let blockedItems = blockedTasks
            .map { agendaItem(for: $0, section: .blocked) }
            .sorted { $0.sortKey < $1.sortKey }

        let dueItems = dueTasks
            .map { agendaItem(for: $0, section: .due) }
            .sorted { $0.sortKey < $1.sortKey }

        return TodayAgendaWidgetData(
            blocked: Array(blockedItems.prefix(blockedLimit)),
            dueToday: Array(dueItems.prefix(dueLimit)),
            blockedCount: blockedTasks.count,
            dueTodayCount: dueTasks.count
        )
    }

    private static func agendaItem(for task: TaskItem, section: WidgetAgendaSection) -> WidgetAgendaItem {
        let calendar = Calendar.current
        let timeLabel: String
        let sortKey: Date

        switch section {
        case .blocked:
            if let block = task.todayBlockTimeLabel {
                timeLabel = block
                sortKey = task.calendarEventStart ?? calendar.startOfDay(for: .now)
            } else if task.planForToday {
                timeLabel = "Planned"
                sortKey = calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: .now)) ?? .distantFuture
            } else {
                timeLabel = "Today"
                sortKey = calendar.date(byAdding: .hour, value: 13, to: calendar.startOfDay(for: .now)) ?? .distantFuture
            }
        case .due:
            if let due = task.dueDate {
                sortKey = due
                if task.hasDueTime {
                    let f = DateFormatter()
                    f.timeStyle = .short
                    f.dateStyle = .none
                    timeLabel = "Due \(f.string(from: due))"
                } else {
                    timeLabel = "Due today"
                }
            } else {
                timeLabel = "Due today"
                sortKey = .distantFuture
            }
        }

        return WidgetAgendaItem(
            id: task.uuid,
            title: task.title.isEmpty ? "Untitled" : task.title,
            category: task.project?.isUserCategory == true ? task.project?.hashTag : nil,
            timeLabel: timeLabel,
            section: section,
            sortKey: sortKey
        )
    }

    private static func summary(for task: TaskItem) -> WidgetTaskSummary {
        let detail: String?
        if let block = task.todayBlockTimeLabel {
            detail = block
        } else if let dueLabel = DueDateFormatting.taskDueLabel(task) {
            detail = dueLabel
        } else {
            detail = nil
        }

        return WidgetTaskSummary(
            id: task.uuid,
            title: task.title.isEmpty ? "Untitled" : task.title,
            category: task.project?.isUserCategory == true ? task.project?.hashTag : nil,
            detail: detail
        )
    }

    static func loadInboxCount() -> Int {
        let context = ModelContext(PersistenceController.shared)
        guard let all = try? context.fetch(FetchDescriptor<TaskItem>()) else { return 0 }
        return TaskFilters.inbox(all).count
    }
}

import Foundation
import SwiftData

enum TodayListEmphasis {
    case focus
    case context
}

struct TaskDisplayRow: Identifiable {
    let task: TaskItem
    let depth: Int
    var todayEmphasis: TodayListEmphasis?
    var id: UUID { task.uuid }
}

struct GanttDependencyEdge: Identifiable {
    let id: UUID
    let from: UUID
    let to: UUID
    let kind: TaskLinkKind
}

enum TaskHierarchy {
    static func roots(in tasks: [TaskItem]) -> [TaskItem] {
        TaskFilters.sortedByDueDate(
            tasks.filter { $0.parent == nil }
        )
    }

    static func flatten(roots: [TaskItem], includeCompleted: Bool = true) -> [TaskDisplayRow] {
        var rows: [TaskDisplayRow] = []
        for root in roots {
            appendOrdered(task: root, depth: 0, into: &rows, includeCompleted: includeCompleted)
        }
        return rows
    }

    static func applyTodaySingleSubtaskEmphasis(rows: [TaskDisplayRow], roots: [TaskItem]) -> [TaskDisplayRow] {
        var emphasisByID: [UUID: TodayListEmphasis] = [:]

        for root in roots {
            let onAgenda = openOnTodayAgenda(in: root)
            guard onAgenda.count == 1, let focus = onAgenda.first, focus.parent != nil else { continue }

            for task in subtree(of: root) where !task.isComplete {
                emphasisByID[task.uuid] = task.uuid == focus.uuid ? .focus : .context
            }
        }

        return rows.map { row in
            var copy = row
            copy.todayEmphasis = emphasisByID[row.task.uuid]
            return copy
        }
    }

    private static func openOnTodayAgenda(in root: TaskItem) -> [TaskItem] {
        var result: [TaskItem] = []
        for task in subtree(of: root) where !task.isComplete && task.isOnTodayAgenda {
            result.append(task)
        }
        return result
    }

    private static func subtree(of root: TaskItem) -> [TaskItem] {
        var items = [root]
        for child in root.sortedSubtasks {
            items.append(contentsOf: subtree(of: child))
        }
        return items
    }

    private static func appendOrdered(
        task: TaskItem,
        depth: Int,
        into rows: inout [TaskDisplayRow],
        includeCompleted: Bool
    ) {
        if includeCompleted || !task.isComplete {
            rows.append(TaskDisplayRow(task: task, depth: depth))
        }
        let open = TaskFilters.sortedByDueDate(task.subtasks.filter { !$0.isComplete })
        let done = TaskFilters.sortedByDueDate(task.subtasks.filter { $0.isComplete })
        for child in open + done {
            appendOrdered(task: child, depth: depth + 1, into: &rows, includeCompleted: includeCompleted)
        }
    }

    static func rootsMatching(
        in all: [TaskItem],
        where matches: (TaskItem) -> Bool
    ) -> [TaskItem] {
        let matched = Set(all.filter(matches).map(\.uuid))
        guard !matched.isEmpty else { return [] }

        var rootIDs = Set<UUID>()
        for task in all where matched.contains(task.uuid) {
            rootIDs.insert(task.root.uuid)
        }

        return TaskFilters.sortedByDueDate(
            roots(in: all).filter { rootIDs.contains($0.uuid) }
        )
    }

    static func candidatePredecessors(
        for task: TaskItem?,
        in pool: [TaskItem],
        sameCategoryOnly: Bool = true
    ) -> [TaskItem] {
        guard let task else {
            let filtered = pool.filter { !$0.isComplete && $0.parent == nil }
            return filtered
        }

        let categoryID = effectiveProjectID(of: task)
        let excluded = Set(collectDescendants(of: task).map(\.uuid) + [task.uuid])
        var seen = Set<UUID>()
        var result: [TaskItem] = []

        func appendIfAllowed(_ candidate: TaskItem) {
            guard !candidate.isComplete else { return }
            guard !excluded.contains(candidate.uuid) else { return }
            guard candidate.persistentModelID != task.persistentModelID else { return }
            guard !wouldCreateDependencyCycle(from: candidate, to: task) else { return }
            if sameCategoryOnly, let categoryID {
                guard effectiveProjectID(of: candidate) == categoryID else { return }
            }
            guard seen.insert(candidate.uuid).inserted else { return }
            result.append(candidate)
        }

        if let parent = task.parent {
            appendIfAllowed(parent)
            for sibling in parent.sortedSubtasks {
                appendIfAllowed(sibling)
            }
        }

        for other in pool {
            appendIfAllowed(other)
        }

        return result
    }

    static func wouldCreateDependencyCycle(from predecessor: TaskItem, to task: TaskItem) -> Bool {
        var visited = Set<UUID>()
        func dependsOn(_ target: UUID, startingAt node: TaskItem) -> Bool {
            if node.uuid == target { return true }
            guard visited.insert(node.uuid).inserted else { return false }
            for link in node.outgoingLinks {
                guard let next = link.toTask else { continue }
                if dependsOn(target, startingAt: next) { return true }
            }
            return false
        }
        return dependsOn(predecessor.uuid, startingAt: task)
    }

    private static func effectiveProjectID(of task: TaskItem) -> PersistentIdentifier? {
        if let project = task.project { return project.persistentModelID }
        return task.parent?.project?.persistentModelID ?? task.root.project?.persistentModelID
    }

    private static func collectDescendants(of task: TaskItem) -> [TaskItem] {
        var result: [TaskItem] = []
        for child in task.subtasks {
            result.append(child)
            result.append(contentsOf: collectDescendants(of: child))
        }
        return result
    }

    static func dependencyEdges(for rows: [TaskDisplayRow]) -> [GanttDependencyEdge] {
        let indexByID = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.task.uuid, $0) })
        var edges: [GanttDependencyEdge] = []

        for row in rows {
            let links = row.task.incomingLinks
            if links.isEmpty, let pred = row.task.predecessor {
                guard indexByID[pred.uuid] != nil, indexByID[row.task.uuid] != nil else { continue }
                edges.append(GanttDependencyEdge(id: UUID(), from: pred.uuid, to: row.task.uuid, kind: .finishToStart))
                continue
            }
            for link in links {
                guard let from = link.fromTask?.uuid,
                      indexByID[from] != nil,
                      indexByID[row.task.uuid] != nil else { continue }
                edges.append(GanttDependencyEdge(id: link.uuid, from: from, to: row.task.uuid, kind: link.kind))
            }
        }
        return edges
    }
}

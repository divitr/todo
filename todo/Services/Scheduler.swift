import Foundation
import SwiftData

enum Scheduler {
    static func reschedule(tasks: [TaskItem]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let active = tasks.filter { !$0.isComplete }

        guard !active.isEmpty else {
            for task in tasks where task.isComplete {
                task.scheduledStart = today
                task.scheduledEnd = today
            }
            return
        }

        let schedulingSet = ganttSchedulingSet(from: active)
        scheduleDependencyOrdered(schedulingSet, all: active, calendar: calendar, today: today)

        let roots = TaskHierarchy.roots(in: active)
        for root in roots {
            scheduleSubtree(parent: root, calendar: calendar, today: today)
            rollup(parent: root, calendar: calendar)
        }

        stabilizeDependencyConstraints(active: active, calendar: calendar, today: today)

        for task in tasks where task.isComplete {
            task.scheduledStart = today
            task.scheduledEnd = today
        }

        let scheduledIDs = Set(schedulingSet.map(\.persistentModelID))
        for task in active where !task.isGanttEligible && !scheduledIDs.contains(task.persistentModelID) {
            task.scheduledStart = nil
            task.scheduledEnd = nil
        }
    }

    private static func incomingLinks(of task: TaskItem) -> [TaskLink] {
        var links = task.incomingLinks
        if links.isEmpty, let pred = task.predecessor, !pred.isComplete {
            let legacy = TaskLink(kind: .finishToStart, from: pred, to: task)
            links = [legacy]
        }
        return links.filter { $0.fromTask != nil && !($0.fromTask?.isComplete ?? true) }
    }

    private static func ganttSchedulingSet(from active: [TaskItem]) -> [TaskItem] {
        var ids = Set(active.filter(\.isGanttEligible).map(\.persistentModelID))
        var changed = true
        while changed {
            changed = false
            for task in active where ids.contains(task.persistentModelID) {
                for link in incomingLinks(of: task) {
                    guard let pred = link.fromTask, !pred.isComplete else { continue }
                    if !ids.contains(pred.persistentModelID) {
                        ids.insert(pred.persistentModelID)
                        changed = true
                    }
                }
            }
        }
        return active.filter { ids.contains($0.persistentModelID) }
    }

    private static func scheduleDependencyOrdered(
        _ schedulingSet: [TaskItem],
        all: [TaskItem],
        calendar: Calendar,
        today: Date
    ) {
        guard !schedulingSet.isEmpty else { return }

        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.persistentModelID, $0) })
        let setIDs = Set(schedulingSet.map(\.persistentModelID))
        var inDegree: [PersistentIdentifier: Int] = [:]
        var adjacency: [PersistentIdentifier: [PersistentIdentifier]] = [:]

        for task in schedulingSet {
            let id = task.persistentModelID
            inDegree[id] = 0
            adjacency[id] = []
        }

        for task in schedulingSet {
            for link in incomingLinks(of: task) {
                guard let pred = link.fromTask else { continue }
                let from = pred.persistentModelID
                let to = task.persistentModelID
                guard setIDs.contains(from), inDegree[to] != nil else { continue }
                adjacency[from, default: []].append(to)
                inDegree[to, default: 0] += 1
            }
        }

        var queue = schedulingSet
            .filter { inDegree[$0.persistentModelID] == 0 }
            .sorted { $0.sortOrder < $1.sortOrder }
        var ordered: [TaskItem] = []

        while let current = queue.first {
            queue.removeFirst()
            ordered.append(current)
            for nextID in adjacency[current.persistentModelID] ?? [] {
                inDegree[nextID, default: 0] -= 1
                if inDegree[nextID] == 0, let next = byID[nextID] {
                    queue.append(next)
                }
            }
            queue.sort { $0.sortOrder < $1.sortOrder }
        }

        let orderedIDs = Set(ordered.map(\.persistentModelID))
        ordered.append(
            contentsOf: schedulingSet
                .filter { !orderedIDs.contains($0.persistentModelID) }
                .sorted { $0.sortOrder < $1.sortOrder }
        )

        for task in ordered {
            for link in incomingLinks(of: task) {
                if let pred = link.fromTask {
                    ensureAnchorSchedule(for: pred, calendar: calendar, today: today)
                }
            }
            let minStart = constraintMinStart(for: task, calendar: calendar, today: today)
            applySchedule(to: task, calendar: calendar, today: today, minStart: minStart)
        }
    }

    private static func stabilizeDependencyConstraints(
        active: [TaskItem],
        calendar: Calendar,
        today: Date
    ) {
        let eligible = active.filter(\.isGanttEligible)
        guard !eligible.isEmpty else { return }

        let passes = min(eligible.count, 32)
        for _ in 0..<passes {
            var changed = false
            for task in eligible.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                for link in incomingLinks(of: task) {
                    if let pred = link.fromTask {
                        ensureAnchorSchedule(for: pred, calendar: calendar, today: today)
                    }
                }
                let before = task.scheduledStart
                let minStart = max(today, constraintMinStart(for: task, calendar: calendar, today: today))
                applySchedule(to: task, calendar: calendar, today: today, minStart: minStart)
                if task.scheduledStart != before { changed = true }
            }
            if !changed { break }
        }
    }

    private static func ensureAnchorSchedule(for pred: TaskItem, calendar: Calendar, today: Date) {
        guard !pred.isComplete else { return }
        if pred.scheduledStart != nil, pred.scheduledEnd != nil { return }

        if pred.isGanttEligible {
            applySchedule(to: pred, calendar: calendar, today: today, minStart: today)
            return
        }

        let duration = max(pred.durationDays, TaskItem.minDurationDays)
        let start: Date
        let end: Date
        if pred.useManualStart, let manual = pred.manualStart {
            start = calendar.startOfDay(for: manual)
            end = pred.dueDate.map { calendar.startOfDay(for: $0) }
                ?? GanttScheduleMath.inclusiveEnd(start: start, durationDays: duration, calendar: calendar)
        } else if let due = pred.dueDate {
            end = calendar.startOfDay(for: due)
            start = GanttScheduleMath.inclusiveStart(end: end, durationDays: duration, calendar: calendar)
        } else {
            start = today
            end = GanttScheduleMath.inclusiveEnd(start: start, durationDays: duration, calendar: calendar)
        }
        pred.scheduledStart = start
        pred.scheduledEnd = end
    }

    private static func scheduleSubtree(parent: TaskItem, calendar: Calendar, today: Date) {
        let children = dependencyOrderedSiblings(parent.sortedSubtasks.filter { !$0.isComplete })
        var previousEnd = parent.scheduledEnd ?? today

        for child in children {
            for link in incomingLinks(of: child) {
                if let pred = link.fromTask {
                    ensureAnchorSchedule(for: pred, calendar: calendar, today: today)
                }
            }

            var minStart = constraintMinStart(for: child, calendar: calendar, today: today)
            let childHasOwnSchedule = child.useManualStart || child.dueDate != nil
            if !childHasOwnSchedule {
                let parentStart = calendar.startOfDay(for: parent.scheduledStart ?? today)
                let afterSibling = GanttScheduleMath.dayAfterInclusiveEnd(previousEnd, calendar: calendar)
                minStart = max(minStart, parentStart, afterSibling)
            }

            applySchedule(to: child, calendar: calendar, today: today, minStart: minStart)
            scheduleSubtree(parent: child, calendar: calendar, today: today)
            previousEnd = child.scheduledEnd ?? previousEnd
        }
    }

    private static func dependencyOrderedSiblings(_ siblings: [TaskItem]) -> [TaskItem] {
        guard siblings.count > 1 else { return siblings }

        let ids = Set(siblings.map(\.uuid))
        var inDegree: [UUID: Int] = [:]
        var adjacency: [UUID: [UUID]] = [:]

        for task in siblings {
            inDegree[task.uuid] = 0
            adjacency[task.uuid] = []
        }

        for task in siblings {
            for link in incomingLinks(of: task) {
                guard let pred = link.fromTask, ids.contains(pred.uuid) else { continue }
                switch link.kind {
                case .finishToStart, .startToStart:
                    adjacency[pred.uuid, default: []].append(task.uuid)
                    inDegree[task.uuid, default: 0] += 1
                case .finishToFinish, .startToFinish:
                    break
                }
            }
        }

        var queue = siblings
            .filter { inDegree[$0.uuid] == 0 }
            .sorted { $0.sortOrder < $1.sortOrder }
        var ordered: [TaskItem] = []

        while let current = queue.first {
            queue.removeFirst()
            ordered.append(current)
            for nextID in adjacency[current.uuid] ?? [] {
                inDegree[nextID, default: 0] -= 1
                if inDegree[nextID] == 0, let next = siblings.first(where: { $0.uuid == nextID }) {
                    queue.append(next)
                }
            }
            queue.sort { $0.sortOrder < $1.sortOrder }
        }

        let orderedIDs = Set(ordered.map(\.uuid))
        ordered.append(contentsOf: siblings.filter { !orderedIDs.contains($0.uuid) }.sorted { $0.sortOrder < $1.sortOrder })
        return ordered
    }

    private static func constraintMinStart(for task: TaskItem, calendar: Calendar, today: Date) -> Date {
        var start = calendar.startOfDay(for: today)
        for link in incomingLinks(of: task) {
            guard let pred = link.fromTask else { continue }
            ensureAnchorSchedule(for: pred, calendar: calendar, today: today)
            let predStart = pred.scheduledStart ?? calendar.startOfDay(for: today)
            let predEnd = pred.scheduledEnd
                ?? GanttScheduleMath.inclusiveEnd(start: predStart, durationDays: pred.durationDays, calendar: calendar)
            switch link.kind {
            case .finishToStart:
                start = max(start, GanttScheduleMath.dayAfterInclusiveEnd(predEnd, calendar: calendar))
            case .startToStart:
                start = max(start, calendar.startOfDay(for: predStart))
            case .finishToFinish, .startToFinish:
                break
            }
        }
        return start
    }

    private static func shouldScheduleInSubtree(_ task: TaskItem) -> Bool {
        task.isGanttEligible || (task.parent != nil && task.durationDays >= 1)
    }

    private static func applySchedule(
        to task: TaskItem,
        calendar: Calendar,
        today: Date,
        minStart: Date
    ) {
        guard shouldScheduleInSubtree(task) else { return }

        let duration = max(task.durationDays, TaskItem.minDurationDays)
        let minStartDay = max(
            calendar.startOfDay(for: minStart),
            constraintMinStart(for: task, calendar: calendar, today: today)
        )

        var start: Date
        var end: Date

        if task.useManualStart, let manual = task.manualStart {
            start = max(calendar.startOfDay(for: manual), minStartDay)
            if let due = task.dueDate {
                end = calendar.startOfDay(for: due)
                let earliest = GanttScheduleMath.inclusiveStart(end: end, durationDays: duration, calendar: calendar)
                if earliest > start { start = max(earliest, minStartDay) }
                if start > end { start = end }
            } else {
                end = GanttScheduleMath.inclusiveEnd(start: start, durationDays: duration, calendar: calendar)
            }
        } else if let due = task.dueDate {
            end = calendar.startOfDay(for: due)
            start = GanttScheduleMath.inclusiveStart(end: end, durationDays: duration, calendar: calendar)
            start = max(start, minStartDay)
            if start > end { start = end }
        } else {
            start = minStartDay
            end = GanttScheduleMath.inclusiveEnd(start: start, durationDays: duration, calendar: calendar)
        }

        applyFinishConstraints(to: task, start: &start, end: &end, calendar: calendar, today: today, minStart: minStartDay)
        task.scheduledStart = calendar.startOfDay(for: start)
        task.scheduledEnd = calendar.startOfDay(for: end)
    }

    private static func applyFinishConstraints(
        to task: TaskItem,
        start: inout Date,
        end: inout Date,
        calendar: Calendar,
        today: Date,
        minStart: Date
    ) {
        let duration = max(task.durationDays, TaskItem.minDurationDays)
        for link in incomingLinks(of: task) {
            guard let pred = link.fromTask else { continue }
            ensureAnchorSchedule(for: pred, calendar: calendar, today: today)
            let predStart = calendar.startOfDay(for: pred.scheduledStart ?? today)
            let predEnd = calendar.startOfDay(for: pred.scheduledEnd
                ?? GanttScheduleMath.inclusiveEnd(start: predStart, durationDays: pred.durationDays, calendar: calendar))
            switch link.kind {
            case .finishToFinish:
                end = max(end, predEnd)
                start = max(
                    minStart,
                    GanttScheduleMath.inclusiveStart(end: end, durationDays: duration, calendar: calendar)
                )
            case .startToFinish:
                end = max(end, predStart)
                start = max(
                    minStart,
                    GanttScheduleMath.inclusiveStart(end: end, durationDays: duration, calendar: calendar)
                )
            case .finishToStart, .startToStart:
                break
            }
        }
    }

    private static func rollup(parent: TaskItem, calendar: Calendar) {
        let kids = parent.sortedSubtasks.filter { !$0.isComplete }
        guard !kids.isEmpty else { return }

        let starts = kids.compactMap(\.scheduledStart)
        let ends = kids.compactMap(\.scheduledEnd)
        guard let minStart = starts.min(), let maxEnd = ends.max() else { return }

        if parent.scheduledStart == nil || minStart < parent.scheduledStart! {
            parent.scheduledStart = minStart
        }
        if parent.scheduledEnd == nil || maxEnd > parent.scheduledEnd! {
            parent.scheduledEnd = maxEnd
        }
    }
}

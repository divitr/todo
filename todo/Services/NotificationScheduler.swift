import AppKit
import Foundation
import SwiftData
import UserNotifications

@MainActor
final class NotificationScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()

    @Published private(set) var authorizationDenied = false

    private override init() {
        super.init()
        center.delegate = self
    }

    func install() {
        center.delegate = self
        registerCategories()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await handleNotificationResponse(response)
    }

    @discardableResult
    func ensureAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorizationDenied = false
            return true
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                authorizationDenied = !granted
                return granted
            } catch {
                NSLog("todo: notification authorization failed: \(error.localizedDescription)")
                authorizationDenied = true
                return false
            }
        case .denied:
            authorizationDenied = true
            return false
        @unknown default:
            authorizationDenied = true
            return false
        }
    }

    func requestAccessIfNeeded() async {
        _ = await ensureAuthorization()
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func sendTestNotification() async {
        guard await ensureAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = "todo reminders work"
        content.body = "You’ll get alerts like this for tasks with reminders on."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(
            identifier: "todo.test.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    func syncAll(tasks: [TaskItem]) async {
        guard await ensureAuthorization() else { return }

        let pending = await center.pendingNotificationRequests()
        let keepIDs = retainedNotificationIdentifiers(for: tasks)

        for request in pending where !keepIDs.contains(request.identifier) {
            center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        }

        for task in tasks where task.shouldScheduleReminder {
            await schedule(task: task)
        }

        await syncScheduleWarnings(tasks: tasks)
        await syncMorningAgendas(tasks: tasks)
        await syncOverdueNudges(tasks: tasks)
    }

    private func retainedNotificationIdentifiers(for tasks: [TaskItem]) -> Set<String> {
        var ids = Set<String>()
        ids.formUnion(tasks.filter(\.shouldScheduleReminder).map(\.notificationIdentifier))
        ids.formUnion(tasks.map(\.scheduleWarningIdentifier))
        ids.formUnion(AgendaNotificationPlanner.plannedMorningAgendaIdentifiers())
        ids.formUnion(tasks.filter { !$0.isComplete && $0.dueDate != nil }.map(\.overdueNotificationIdentifier))
        return ids
    }

    private func syncMorningAgendas(tasks: [TaskItem]) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        for offset in 0..<NotificationPreferences.agendaHorizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            guard let fireDate = AgendaNotificationPlanner.morningAgendaFireDate(for: day, calendar: calendar),
                  fireDate > .now else { continue }

            let identifier = AgendaNotificationPlanner.morningAgendaIdentifier(for: day, calendar: calendar)
            let content = AgendaNotificationPlanner.buildMorningAgendaContent(for: day, tasks: tasks)
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            try? await center.add(request)
        }
    }

    private func syncOverdueNudges(tasks: [TaskItem]) async {
        let calendar = Calendar.current

        for task in tasks {
            let identifier = task.overdueNotificationIdentifier

            if task.isComplete || task.dueDate == nil {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                OverdueNudgeTracker.remove(for: task, calendar: calendar)
                continue
            }

            let dueDay = calendar.startOfDay(for: task.dueDate!)
            guard let endOfDueDay = AgendaNotificationPlanner.overdueFireDate(for: task, calendar: calendar) else {
                continue
            }

            let content = AgendaNotificationPlanner.buildOverdueContent(for: task)
            center.removePendingNotificationRequests(withIdentifiers: [identifier])

            if endOfDueDay > .now {
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: endOfDueDay)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                try? await center.add(request)
                continue
            }

            guard let key = OverdueNudgeTracker.notificationKey(for: task, calendar: calendar),
                  !OverdueNudgeTracker.contains(key) else { continue }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 90, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
                OverdueNudgeTracker.mark(key)
            } catch {
                NSLog("todo: overdue nudge failed: \(error.localizedDescription)")
            }
        }
    }

    func syncScheduleWarnings(tasks: [TaskItem]) async {
        guard await ensureAuthorization() else { return }

        for task in tasks {
            guard let conflict = task.scheduleConflict else {
                cancelScheduleWarning(task: task)
                task.scheduleWarningFingerprint = nil
                continue
            }

            let fp = conflict.fingerprint
            guard task.scheduleWarningFingerprint != fp else { continue }

            let content = UNMutableNotificationContent()
            content.title = conflict.title
            content.body = "\(task.title.isEmpty ? "Task" : task.title): \(conflict.message)"
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: task.scheduleWarningIdentifier,
                content: content,
                trigger: trigger
            )

            center.removePendingNotificationRequests(withIdentifiers: [task.scheduleWarningIdentifier])
            do {
                try await center.add(request)
                task.scheduleWarningFingerprint = fp
            } catch {
                NSLog("todo: schedule warning failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelScheduleWarning(task: TaskItem) {
        center.removePendingNotificationRequests(withIdentifiers: [task.scheduleWarningIdentifier])
    }

    func schedule(task: TaskItem) async {
        guard task.shouldScheduleReminder, let fireDate = task.reminderFireDate else {
            cancel(task: task)
            return
        }

        if fireDate <= .now {
            cancel(task: task)
            return
        }

        guard await ensureAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title.isEmpty ? "Task" : task.title
        if let tag = task.project?.hashTag, task.project?.isUserCategory == true {
            content.subtitle = tag
        }
        if !task.notes.isEmpty {
            content.body = task.notes
        } else if task.dueDate != nil {
            content.body = "Due \(DueDateFormatting.taskDueLabel(task) ?? "")"
        }
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.taskReminder
        content.userInfo = [NotificationUserInfoKey.taskID: task.uuid.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: task.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        center.removePendingNotificationRequests(withIdentifiers: [task.notificationIdentifier])
        do {
            try await center.add(request)
        } catch {
            NSLog("todo: failed to schedule reminder for “\(task.title)”: \(error.localizedDescription)")
        }
    }

    func cancel(task: TaskItem) {
        center.removePendingNotificationRequests(withIdentifiers: [
            task.notificationIdentifier,
            task.overdueNotificationIdentifier,
        ])
        OverdueNudgeTracker.remove(for: task)
    }

    private func registerCategories() {
        let complete = UNNotificationAction(
            identifier: NotificationAction.complete,
            title: "Mark done",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: NotificationAction.snoozeHour,
            title: "Snooze 1 hour",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: NotificationCategory.taskReminder,
            actions: [complete, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    private func handleNotificationResponse(_ response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == NotificationCategory.taskReminder,
              let idString = response.notification.request.content.userInfo[NotificationUserInfoKey.taskID] as? String,
              let uuid = UUID(uuidString: idString),
              let task = fetchTask(uuid: uuid) else { return }

        switch response.actionIdentifier {
        case NotificationAction.complete:
            task.isComplete = true
            task.reminderEnabled = false
            cancel(task: task)
            PersistenceController.save(PersistenceController.viewContext)
            NotificationCenter.default.post(name: .externalStoreChanged, object: nil)
        case NotificationAction.snoozeHour:
            task.reminderAt = Date().addingTimeInterval(3600)
            task.reminderEnabled = true
            PersistenceController.save(PersistenceController.viewContext)
            await schedule(task: task)
            NotificationCenter.default.post(name: .externalStoreChanged, object: nil)
        default:
            break
        }
    }

    private func fetchTask(uuid: UUID) -> TaskItem? {
        let context = PersistenceController.viewContext
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

private enum NotificationCategory {
    static let taskReminder = "todo.task.reminder"
}

private enum NotificationAction {
    static let complete = "todo.complete"
    static let snoozeHour = "todo.snooze.1h"
}

private enum NotificationUserInfoKey {
    static let taskID = "taskID"
}

extension TaskItem {
    var notificationIdentifier: String {
        "todo.task.\(uuid.uuidString)"
    }

    var scheduleWarningIdentifier: String {
        "todo.schedule.\(uuid.uuidString)"
    }

    var overdueNotificationIdentifier: String {
        "todo.overdue.\(uuid.uuidString)"
    }

    var shouldScheduleReminder: Bool {
        reminderEnabled && !isComplete && dueDate != nil
    }

    var reminderFireDate: Date? {
        guard shouldScheduleReminder else { return nil }
        if let reminderAt { return reminderAt }
        guard let dueDate else { return nil }
        let cal = Calendar.current
        if hasDueTime { return dueDate }
        let day = cal.startOfDay(for: dueDate)
        return cal.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: day
        )
    }
}

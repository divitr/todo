import Combine
import EventKit
import Foundation

@MainActor
final class CalendarSyncService: ObservableObject {
    static let shared = CalendarSyncService()

    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var isSyncing = false

    private let calendar = CalendarService.shared
    private var storeObserver: NSObjectProtocol?
    private var refreshTimer: Timer?
    private var pendingRefresh = false

    private init() {}

    func start() {
        guard storeObserver == nil else { return }
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pendingRefresh = true
        }
    }

    func stop() {
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
        storeObserver = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func beginActiveRefresh(every seconds: TimeInterval = 90) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pendingRefresh = true
            }
        }
    }

    func endActiveRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    var shouldRunPendingRefresh: Bool { pendingRefresh }

    func clearPendingRefresh() { pendingRefresh = false }

    @discardableResult
    func refreshLinkedTasks(_ tasks: [TaskItem]) async -> Bool {
        guard await calendar.requestAccess() else { return false }
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncAt = .now
            pendingRefresh = false
        }

        var anyChange = false
        for task in tasks where task.hasCalendarLink {
            if task.syncCalendarFromEventStore() {
                anyChange = true
            }
        }
        return anyChange
    }
}

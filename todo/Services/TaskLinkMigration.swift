import SwiftData

enum TaskLinkMigration {
    @MainActor
    static func migrateAll(context: ModelContext) {
        guard let tasks = try? context.fetch(FetchDescriptor<TaskItem>()) else { return }
        var changed = false
        for task in tasks {
            if task.predecessor != nil, task.incomingLinks.isEmpty {
                task.migrateLegacyPredecessorIfNeeded(in: context)
                changed = true
            }
        }
        if changed { PersistenceController.save(context) }
    }
}

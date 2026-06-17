import Foundation
import SwiftData

enum PersistenceController {
    static let storeName = "todo"
    static let appGroupID = "group.com.divitrawal.todo"

    static let shared: ModelContainer = {
        let schema = Schema([Project.self, TaskItem.self, TaskLink.self])

        if let container = tryOpen(schema: schema, useAppGroup: true) {
            return container
        }

        NSLog("todo: App Group store failed — trying Application Support fallback")
        if let container = tryOpen(schema: schema, useAppGroup: false) {
            return container
        }

        NSLog("todo: resetting App Group store after migration failure")
        resetPersistedStore(useAppGroup: true)
        if let container = tryOpen(schema: schema, useAppGroup: true) {
            return container
        }

        resetPersistedStore(useAppGroup: false)
        if let container = tryOpen(schema: schema, useAppGroup: false) {
            return container
        }

        NSLog("todo: using in-memory store — fix signing / App Group if you need persistence")
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [memory])
        } catch {
            fatalError("Could not create any ModelContainer: \(error)")
        }
    }()

    @MainActor
    static let viewContext: ModelContext = {
        let context = ModelContext(shared)
        context.autosaveEnabled = true
        return context
    }()

    @MainActor
    static func save(_ context: ModelContext) {
        do {
            if context.hasChanges {
                try context.save()
            }
        } catch {
            NSLog("todo save failed: \(error.localizedDescription)")
        }
    }

    static var storeDirectoryPath: String {
        if let url = storeDirectoryURL(useAppGroup: true) {
            return url.path
        }
        return storeDirectoryURL(useAppGroup: false)?.path ?? "(unknown)"
    }

    private static func tryOpen(schema: Schema, useAppGroup: Bool) -> ModelContainer? {
        let configuration = modelConfiguration(schema: schema, useAppGroup: useAppGroup)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            NSLog("todo: open failed (\(useAppGroup ? "group" : "local")): \(error.localizedDescription)")
            return nil
        }
    }

    private static func modelConfiguration(schema: Schema, useAppGroup: Bool) -> ModelConfiguration {
        if useAppGroup {
            return ModelConfiguration(
                storeName,
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .identifier(appGroupID)
            )
        }
        return ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: false)
    }

    private static func storeDirectoryURL(useAppGroup: Bool) -> URL? {
        let fm = FileManager.default
        if useAppGroup,
           let base = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return base.appendingPathComponent("Library/Application Support", isDirectory: true)
        }
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
    }

    private static func resetPersistedStore(useAppGroup: Bool) {
        guard let dir = storeDirectoryURL(useAppGroup: useAppGroup) else { return }
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")

        for suffix in ["", "-shm", "-wal"] {
            let file = dir.appendingPathComponent("\(storeName).store\(suffix)")
            guard fm.fileExists(atPath: file.path) else { continue }
            let backup = dir.appendingPathComponent("\(storeName).store\(suffix).backup-\(stamp)")
            try? fm.moveItem(at: file, to: backup)
        }
    }
}

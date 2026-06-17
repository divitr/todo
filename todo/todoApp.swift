import SwiftData
import SwiftUI

@main
struct todoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.modelContext, PersistenceController.viewContext)
        }
        .modelContainer(PersistenceController.shared)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    NotificationCenter.default.post(name: .newTask, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let newTask = Notification.Name("todo.newTask")
    static let showMainWindow = Notification.Name("todo.showMainWindow")
    static let externalStoreChanged = Notification.Name("todo.externalStoreChanged")
}

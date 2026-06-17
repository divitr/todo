import AppKit
import UserNotifications
import WidgetKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationScheduler.shared.install()
        MenuBarController.shared.install()
        Task { await NotificationScheduler.shared.ensureAuthorization() }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

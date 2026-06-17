import AppKit
import SwiftData
import SwiftUI
import WidgetKit

@MainActor
@Observable
final class MenuBarPopoverModel {
    var data = WidgetDataLoader.loadMenuBarToday()

    func reload() {
        data = WidgetDataLoader.loadMenuBarToday()
    }

    func toggleComplete(taskID: UUID) {
        _ = MenuBarTaskActions.toggleCompletion(id: taskID)
        reload()
    }

    func openMainApp(selecting taskID: UUID? = nil) {
        MenuBarController.shared.openMainApp(selecting: taskID)
    }
}

enum MenuBarTaskActions {
    @MainActor
    static func toggleCompletion(id: UUID) -> Bool {
        let context = PersistenceController.viewContext
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        guard let task = try? context.fetch(descriptor).first else { return false }

        task.isComplete.toggle()
        if task.isComplete {
            task.reminderEnabled = false
            NotificationScheduler.shared.cancel(task: task)
        }
        PersistenceController.save(context)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .externalStoreChanged, object: nil)
        return task.isComplete
    }
}

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var popoverModel = MenuBarPopoverModel()
    private var popoverHost: NSHostingController<MenuBarPopoverView>?
    private var outsideClickMonitor: Any?

    private override init() {
        super.init()
    }

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let icon = NSApp.applicationIconImage {
                let sized = icon.copy() as? NSImage ?? icon
                sized.size = NSSize(width: 18, height: 18)
                button.image = sized
            } else {
                button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "todo")
                button.image?.isTemplate = true
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 460)
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self

        let host = NSHostingController(rootView: MenuBarPopoverView(model: popoverModel))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        self.popover = popover
        popoverHost = host
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover else { return }
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, let popover else { return }
        popoverModel.reload()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installOutsideClickMonitor()
    }

    func closePopover() {
        popover?.performClose(nil)
        removeOutsideClickMonitor()
    }

    func openMainApp(selecting taskID: UUID? = nil) {
        closePopover()

        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }

        NotificationCenter.default.post(name: .showMainWindow, object: taskID)
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleOutsideClick(event)
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func handleOutsideClick(_ event: NSEvent) {
        guard let popover, popover.isShown,
              let popoverWindow = popover.contentViewController?.view.window else { return }

        if let clickWindow = event.window {
            if clickWindow === popoverWindow { return }
            if clickWindow === statusItem?.button?.window { return }
        }

        closePopover()
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitor()
    }
}

struct MenuBarPopoverView: View {
    @Bindable var model: MenuBarPopoverModel

    var body: some View {
        VStack(spacing: 0) {
            popoverHeader

            Divider().overlay(Theme.border)

            Group {
                if model.data.isEmpty {
                    menuBarEmptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            MenuBarSectionView(
                                title: "Blocked for today",
                                systemImage: "calendar.day.timeline.left",
                                count: model.data.blockedCount,
                                tasks: model.data.blocked,
                                onToggleComplete: model.toggleComplete(taskID:),
                                onOpenTask: { model.openMainApp(selecting: $0) }
                            )
                            MenuBarSectionView(
                                title: "Due today",
                                systemImage: "sun.max",
                                count: model.data.dueTodayCount,
                                tasks: model.data.dueToday,
                                onToggleComplete: model.toggleComplete(taskID:),
                                onOpenTask: { model.openMainApp(selecting: $0) }
                            )
                            MenuBarSectionView(
                                title: "Due tomorrow",
                                systemImage: "sunrise",
                                count: model.data.dueTomorrowCount,
                                tasks: model.data.dueTomorrow,
                                onToggleComplete: model.toggleComplete(taskID:),
                                onOpenTask: { model.openMainApp(selecting: $0) }
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider().overlay(Theme.border)

            Button {
                model.openMainApp()
            } label: {
                Label("Open todo", systemImage: "arrow.up.forward.app")
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .frame(width: 340, height: 460)
        .background(Theme.background)
    }

    private var popoverHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Agenda")
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text(headerSubtitle)
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if model.data.totalCount > 0 {
                Text("\(model.data.totalCount)")
                    .font(Theme.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var headerSubtitle: String {
        let data = model.data
        if data.isEmpty { return "All clear" }
        var parts: [String] = []
        if data.blockedCount > 0 { parts.append("\(data.blockedCount) blocked") }
        if data.dueTodayCount > 0 { parts.append("\(data.dueTodayCount) due") }
        if data.dueTomorrowCount > 0 { parts.append("\(data.dueTomorrowCount) tomorrow") }
        return parts.joined(separator: " · ")
    }

    private var menuBarEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.muted)
            Text("All clear")
                .font(Theme.sans(15, weight: .semibold))
                .foregroundStyle(Theme.primary)
            Text("Nothing blocked or due today or tomorrow.")
                .font(Theme.sans(12))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct MenuBarSectionView: View {
    let title: String
    let systemImage: String
    let count: Int
    let tasks: [WidgetTaskSummary]
    let onToggleComplete: (UUID) -> Void
    let onOpenTask: (UUID) -> Void

    var body: some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    Text(title)
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .textCase(.uppercase)
                        .tracking(0.4)
                    Spacer()
                    Text("\(count)")
                        .font(Theme.sans(11, weight: .medium))
                        .foregroundStyle(Theme.faint)
                }

                VStack(spacing: 0) {
                    ForEach(tasks) { task in
                        MenuBarTaskRow(
                            task: task,
                            onToggleComplete: { onToggleComplete(task.id) },
                            onOpenTask: { onOpenTask(task.id) }
                        )
                    }
                    if count > tasks.count {
                        Text("+\(count - tasks.count) more in app")
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.faint)
                            .padding(.leading, Theme.taskCheckboxSize + 20)
                            .padding(.top, 6)
                    }
                }
            }
        }
    }
}

private struct MenuBarTaskRow: View {
    let task: WidgetTaskSummary
    let onToggleComplete: () -> Void
    let onOpenTask: () -> Void

    @State private var isHovered = false

    private let checkboxSize = Theme.taskCheckboxSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleComplete) {
                Image(systemName: "circle")
                    .font(.system(size: checkboxSize, weight: .light))
                    .foregroundStyle(Theme.faint)
                    .frame(width: checkboxSize + 10, height: checkboxSize + 10)
            }
            .buttonStyle(.borderless)
            .help("Mark complete")
            .padding(.top, 1)

            Button(action: onOpenTask) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(Theme.sans(14, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let meta = metaLine {
                        Text(meta)
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Theme.hover : Color.clear)
        )
        .onHover { isHovered = $0 }
    }

    private var metaLine: String? {
        switch (task.category, task.detail) {
        case let (cat?, detail?):
            return "\(cat) · \(detail)"
        case let (cat?, nil):
            return cat
        case let (nil, detail?):
            return detail
        default:
            return nil
        }
    }
}

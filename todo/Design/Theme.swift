import AppKit
import SwiftUI

enum Theme {
    static var background: Color { Color(nsColor: .windowBackgroundColor) }
    static var surface: Color { Color(nsColor: .controlBackgroundColor) }
    static var elevated: Color { Color(nsColor: .underPageBackgroundColor) }

    static var primary: Color { Color.primary }
    static var secondary: Color { Color.secondary }
    static var muted: Color { Color(nsColor: .secondaryLabelColor) }
    static var faint: Color { Color(nsColor: .tertiaryLabelColor) }
    static var border: Color { Color(nsColor: .separatorColor) }

    static var barFill: Color { Color.primary.opacity(0.48) }
    static var barFillLight: Color { Color.primary.opacity(0.32) }
    static var barSubtask: Color { Color.primary.opacity(0.34) }
    static var todayLine: Color { Color.secondary }
    static var linkLine: Color { Color.secondary.opacity(0.85) }

    static var sidebarSelectionFill: Color { Color.primary.opacity(0.11) }
    static var sidebarSelectionStroke: Color { Color.primary.opacity(0.13) }
    static var hover: Color { Color.primary.opacity(0.06) }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func softAccentFill(_ color: Color, opacity: Double = 0.12) -> Color {
        color.opacity(opacity)
    }

    static func softAccentStroke(_ color: Color, opacity: Double = 0.35) -> Color {
        color.opacity(opacity)
    }

    static var defaultAccent: Color { Color.accentColor }

    static var dueAccent: Color { secondary }

    static let listContentMaxWidth: CGFloat = 760
    static let listHorizontalPadding: CGFloat = 36

    static let taskCheckboxSize: CGFloat = 22
    static let sidebarIconWidth: CGFloat = 18
    static let sidebarRowInset: CGFloat = 6
}

struct TaskCompletionButton: View {
    @Bindable var task: TaskItem
    var onChange: () -> Void
    var size: CGFloat = Theme.taskCheckboxSize

    var body: some View {
        Button {
            task.isComplete.toggle()
            if task.isComplete {
                task.reminderEnabled = false
                NotificationScheduler.shared.cancel(task: task)
            }
            onChange()
        } label: {
            Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: size, weight: .light))
                .foregroundStyle(task.isComplete ? Theme.muted : Theme.faint)
                .frame(width: size + 10, height: size + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TodayPlanToggle: View {
    @Bindable var task: TaskItem
    var onChange: () -> Void

    @State private var showBlockSheet = false

    private var active: Bool { task.isBlockedToday }
    private var tint: Color {
        if task.isCalendarBlockedToday, let c = task.calendarAccentColor { return c }
        return Theme.todayLine
    }

    var body: some View {
        Button {
            handleTap()
        } label: {
            Image(systemName: "calendar.day.timeline.left")
                .symbolVariant(active ? .fill : .none)
                .font(.system(size: 15, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? tint : Theme.faint)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(task.todayPlanHelp)
        .accessibilityLabel(task.todayPlanHelp)
        .sheet(isPresented: $showBlockSheet) {
            TodayBlockTimeSheet(
                task: task,
                onSaved: onChange,
                onDismiss: { showBlockSheet = false }
            )
        }
    }

    private func handleTap() {
        if task.isBlockedToday {
            task.planForToday = false
            onChange()
            return
        }

        if task.isCalendarEventToday, !task.planForToday {
            task.planForToday = true
            onChange()
            return
        }

        showBlockSheet = true
    }
}

struct ListAddTaskButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20, alignment: .leading)
                Text("Add task")
                    .font(Theme.sans(14, weight: .medium))
            }
            .foregroundStyle(Theme.muted)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompletedTasksSectionHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Completed")
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .textCase(.uppercase)
            Rectangle()
                .fill(Theme.border)
                .frame(height: 0.5)
        }
        .padding(.leading, 2)
    }
}

struct ListRowDivider: View {
    var leadingInset: CGFloat = 32

    var body: some View {
        Divider()
            .overlay(Theme.border)
            .padding(.leading, leadingInset)
    }
}

private struct AppAccentKey: EnvironmentKey {
    static let defaultValue: Color = Theme.defaultAccent
}

extension EnvironmentValues {
    var appAccent: Color {
        get { self[AppAccentKey.self] }
        set { self[AppAccentKey.self] = newValue }
    }
}

extension View {
    func appAccentColor(_ color: Color) -> some View {
        environment(\.appAccent, color).tint(color)
    }
}

struct AppBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Theme.background)
    }
}

struct ComposerChrome: ViewModifier {
    @Environment(\.appAccent) private var accent

    func body(content: Content) -> some View {
        content
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.softAccentStroke(accent, opacity: 0.25), lineWidth: 1)
            )
    }
}

struct MetaPillButtonStyle: ButtonStyle {
    var isActive: Bool = false
    @Environment(\.appAccent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(12))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Theme.softAccentFill(accent, opacity: 0.22) : Theme.hover)
            .foregroundStyle(isActive ? accent : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isActive ? Theme.softAccentStroke(accent) : Theme.border, lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct TogglePillButtonStyle: ButtonStyle {
    var isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(12, weight: isOn ? .semibold : .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? Color.white : Theme.secondary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? Theme.primary.opacity(configuration.isPressed ? 0.72 : 0.9) : Theme.hover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isOn ? Color.clear : Theme.border, lineWidth: 0.5)
            )
            .opacity(configuration.isPressed && !isOn ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

struct MonoProminentButtonStyle: ButtonStyle {
    @Environment(\.appAccent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(13, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(accent.opacity(configuration.isPressed ? 0.78 : 1))
            .foregroundStyle(contrastingLabel(on: accent))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func contrastingLabel(on color: Color) -> Color {
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.sRGB) else {
            return Color(nsColor: .windowBackgroundColor)
        }
        let l = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return l > 0.62 ? Color.black.opacity(0.85) : Color.white.opacity(0.95)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.appAccent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(13))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.softAccentFill(accent, opacity: configuration.isPressed ? 0.08 : 0.14))
            .foregroundStyle(accent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.softAccentStroke(accent, opacity: 0.3), lineWidth: 0.5)
            )
    }
}

extension View {
    func appBackground() -> some View { modifier(AppBackground()) }
    func composerChrome() -> some View { modifier(ComposerChrome()) }

    func centeredDetailColumn(alignment: Alignment = .leading) -> some View {
        frame(maxWidth: Theme.listContentMaxWidth, alignment: alignment)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    func detailContentWidth(fullWidth: Bool, alignment: Alignment = .leading) -> some View {
        if fullWidth {
            frame(maxWidth: .infinity, alignment: alignment)
                .padding(.horizontal, 16)
        } else {
            centeredDetailColumn(alignment: alignment)
        }
    }
}

struct SidebarSelectionCapsule: View {
    let isSelected: Bool
    var tint: Color
    var horizontalInset: CGFloat = 8
    var useNeutralFill: Bool = false

    var body: some View {
        Group {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fillColor)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(markerColor)
                            .frame(width: 3)
                            .padding(.leading, 6)
                            .padding(.vertical, 7)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(strokeColor, lineWidth: 1)
                    )
                    .padding(.horizontal, horizontalInset)
                    .padding(.vertical, 2)
            } else {
                Color.clear
            }
        }
    }

    private var fillColor: Color {
        if useNeutralFill { return Theme.sidebarSelectionFill }
        return Theme.softAccentFill(tint, opacity: 0.26)
    }

    private var strokeColor: Color {
        if useNeutralFill { return Theme.sidebarSelectionStroke }
        return Theme.softAccentStroke(tint, opacity: 0.62)
    }

    private var markerColor: Color {
        if useNeutralFill { return Theme.primary.opacity(0.72) }
        return tint.opacity(0.95)
    }
}

struct SidebarRowBackground: View {
    var isSelected: Bool
    var tint: Color?
    var horizontalInset: CGFloat = Theme.sidebarRowInset
    @Environment(\.appAccent) private var accent

    private var selectionTint: Color { tint ?? accent }

    var body: some View {
        ZStack {
            Theme.background
            SidebarSelectionCapsule(
                isSelected: isSelected,
                tint: selectionTint,
                horizontalInset: horizontalInset,
                useNeutralFill: true
            )
        }
    }
}

struct CategoryRowSelectionBackground: View {
    let isSelected: Bool
    let tint: Color
    var horizontalInset: CGFloat = Theme.sidebarRowInset

    var body: some View {
        ZStack {
            Theme.background
            SidebarSelectionCapsule(
                isSelected: isSelected,
                tint: tint,
                horizontalInset: horizontalInset
            )
        }
    }
}

enum CalendarStyle {
    static func readableText(on color: Color) -> Color {
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return .primary }
        let l = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return l > 0.72 ? Color.black.opacity(0.85) : Color.white.opacity(0.95)
    }
}

struct LabeledSegmentedPicker<Selection: Hashable, Content: View>: View {
    let label: String
    @Binding var selection: Selection
    @ViewBuilder var content: () -> Content
    var minControlWidth: CGFloat = 180

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Theme.sans(12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: true, vertical: false)

            Picker("", selection: $selection, content: content)
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(minWidth: minControlWidth)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct TaskNotesSection: View {
    @Binding var notes: String
    var minLines: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(Theme.sans(12, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField("Add notes…", text: $notes, axis: .vertical)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.secondary)
                .textFieldStyle(.plain)
                .lineLimit(minLines...8)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
        }
    }
}

struct CategoryTag: View {
    let project: Project
    var size: CGFloat = 11
    var weight: Font.Weight = .medium

    var body: some View {
        Text(project.hashTag)
            .font(Theme.sans(size, weight: weight))
            .foregroundStyle(project.categoryColor)
    }
}

struct DetailToolbar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading()
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(Theme.surface)
    }
}

extension View {
    func nativeGroupedSurface() -> some View {
        background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
    }
}

struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = layout(maxWidth: width, subviews: subviews)
        return CGSize(width: width.isFinite ? width : result.size.width, height: result.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(maxWidth: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() where index < subviews.count {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func layout(maxWidth: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
            maxX = max(maxX, x - horizontalSpacing)
        }

        return (frames, CGSize(width: maxX, height: y + rowHeight))
    }
}

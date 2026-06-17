import AppKit
import Observation
import SwiftUI

struct GanttChartView: View {
    @Bindable var viewport: GanttViewportState
    let tasks: [TaskItem]
    var colorByCategory: Bool = false
    var onEditTask: ((TaskItem) -> Void)?

    @State private var zoomSessionDayOffset: CGFloat?
    @State private var timelineViewportWidth: CGFloat = 600
    @State private var inspectedTask: TaskItem?

    private var roots: [TaskItem] {
        let active = tasks.filter { !$0.isComplete }
        let activeIDs = Set(active.map(\.uuid))
        return TaskFilters.sortedByDueDate(
            TaskHierarchy.roots(in: tasks).filter { root in
                subtreeContainsPlottable(root, activeIDs: activeIDs)
            }
        )
    }

    private var rows: [TaskDisplayRow] {
        TaskHierarchy.flatten(roots: roots, includeCompleted: false)
            .filter { hasPlottableSchedule($0.task) }
    }

    private func hasPlottableSchedule(_ task: TaskItem) -> Bool {
        task.hasGanttBar
    }

    private func subtreeContainsPlottable(_ task: TaskItem, activeIDs: Set<UUID>) -> Bool {
        if activeIDs.contains(task.uuid), hasPlottableSchedule(task) { return true }
        return task.sortedSubtasks.contains { subtreeContainsPlottable($0, activeIDs: activeIDs) }
    }

    private var openUnscheduledCount: Int {
        tasks.filter { !$0.isComplete && !hasPlottableSchedule($0) }.count
    }

    private var timelineLayout: GanttTimelineLayout {
        GanttTimelineLayout.make(
            tasks: rows.map(\.task),
            pixelsPerDay: viewport.pixelsPerDay,
            viewportWidth: max(timelineViewportWidth, 320)
        )
    }

    private var contentHeight: CGFloat {
        headerHeight + CGFloat(rows.count) * rowHeight
    }

    private let labelWidth: CGFloat = 220
    private let rowHeight: CGFloat = 56
    private let headerHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ganttToolbar
            Divider().overlay(Theme.border)

            if rows.isEmpty {
                ganttEmptyPanel
            } else {
                chartBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }

    private var chartBody: some View {
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                labelColumn
                timelinePane
            }
            .frame(minHeight: contentHeight, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    private var labelColumn: some View {
        VStack(spacing: 0) {
            Text("Task")
                .font(Theme.sans(11, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: labelWidth, height: headerHeight, alignment: .leading)
                .padding(.leading, 16)
                .background(Theme.surface)
                .overlay(alignment: .bottom) { Divider() }

            ForEach(rows) { row in
                GanttRowLabel(
                    row: row,
                    labelWidth: labelWidth,
                    rowHeight: rowHeight,
                    colorByCategory: colorByCategory,
                    onSelect: { inspectedTask = row.task }
                )
            }
        }
        .frame(width: labelWidth)
        .background(Theme.surface)
        .overlay(alignment: .trailing) {
            Divider().overlay(Theme.border)
        }
    }

    private var timelinePane: some View {
        GeometryReader { geometry in
            GanttHorizontalScrollView(
                scrollOffsetX: $viewport.scrollOffsetX,
                contentSize: CGSize(width: timelineLayout.timelineWidth, height: contentHeight),
                scrollApplyToken: viewport.scrollApplyToken,
                scrollTargetX: viewport.pendingScrollX,
                scrollToXOnLoad: restoredScrollX,
                isHorizontalScrollLocked: viewport.isZoomAnchoredToNow,
                lockedScrollX: nowMarkerScrollX(for: timelineLayout),
                suppressUserScroll: viewport.isPinching,
                onUserScroll: {
                    guard !viewport.isPinching, !viewport.isZoomAnchoredToNow else { return }
                    viewport.userHasPannedTimeline = true
                    viewport.isZoomAnchoredToNow = false
                }
            ) {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        GanttTimelineHeader(
                            layout: timelineLayout,
                            height: headerHeight
                        )

                        ForEach(rows) { row in
                            GanttTimelineRow(
                                row: row,
                                rangeStart: timelineLayout.rangeStart,
                                dayCount: timelineLayout.dayCount,
                                dayWidth: viewport.pixelsPerDay,
                                rowHeight: rowHeight,
                                colorByCategory: colorByCategory,
                                popoverPresented: Binding(
                                    get: { inspectedTask?.uuid == row.task.uuid },
                                    set: { if !$0 { inspectedTask = nil } }
                                ),
                                onSelect: { inspectedTask = row.task },
                                onEdit: {
                                    onEditTask?(row.task)
                                    inspectedTask = nil
                                }
                            )
                        }
                    }

                    GanttTodayMarker(
                        rangeStart: timelineLayout.rangeStart,
                        dayCount: timelineLayout.dayCount,
                        dayWidth: viewport.pixelsPerDay,
                        headerHeight: headerHeight,
                        rowHeight: rowHeight,
                        rowCount: rows.count
                    )

                    GanttDependencyOverlay(
                        rows: rows,
                        edges: TaskHierarchy.dependencyEdges(for: rows),
                        rangeStart: timelineLayout.rangeStart,
                        dayWidth: viewport.pixelsPerDay,
                        labelWidth: 0,
                        rowHeight: rowHeight,
                        headerHeight: headerHeight
                    )
                }
                .frame(width: timelineLayout.timelineWidth, height: contentHeight, alignment: .topLeading)
            }
            .gesture(zoomGesture)
            .onAppear {
                viewport.zoomBaseline = viewport.pixelsPerDay
                timelineViewportWidth = geometry.size.width
                if viewport.didSetInitialViewport {
                    viewport.requestScroll(to: viewport.scrollOffsetX)
                } else {
                    viewport.didSetInitialViewport = true
                }
            }
            .onChange(of: geometry.size.width) { _, w in
                timelineViewportWidth = w
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                viewport.isPinching = true
                if !viewport.isZoomAnchoredToNow, zoomSessionDayOffset == nil {
                    zoomSessionDayOffset = viewport.scrollOffsetX / max(viewport.pixelsPerDay, 1)
                }
                viewport.pixelsPerDay = min(max(viewport.zoomBaseline * value.magnification, 4), 120)
                let layout = timelineLayout
                let targetX = leftEdgeDayOffset(for: layout) * layout.pixelsPerDay
                viewport.requestScroll(to: targetX)
            }
            .onEnded { _ in
                viewport.zoomBaseline = viewport.pixelsPerDay
                viewport.isPinching = false
                zoomSessionDayOffset = nil
            }
    }

    private func leftEdgeDayOffset(for layout: GanttTimelineLayout) -> CGFloat {
        if viewport.isZoomAnchoredToNow {
            return nowMarkerDayOffset(in: layout)
        }
        return zoomSessionDayOffset ?? viewport.scrollOffsetX / max(viewport.pixelsPerDay, 1)
    }

    private func nowMarkerDayOffset(in layout: GanttTimelineLayout) -> CGFloat {
        CGFloat(GanttScheduleMath.dayOffset(from: layout.rangeStart, to: .now) ?? 0)
    }

    private func nowMarkerScrollX(for layout: GanttTimelineLayout) -> CGFloat {
        nowMarkerDayOffset(in: layout) * layout.pixelsPerDay
    }

    private var restoredScrollX: CGFloat {
        if viewport.didSetInitialViewport {
            return viewport.scrollOffsetX
        }
        return GanttTimelineLayout.todayScrollOffset(layout: timelineLayout)
    }

    private var visibleRangeLabel: String {
        let cal = Calendar.current
        let layout = timelineLayout
        let startOffset = max(0, Int(floor(viewport.scrollOffsetX / viewport.pixelsPerDay)))
        let endOffset = min(
            layout.dayCount - 1,
            max(startOffset, Int(ceil((viewport.scrollOffsetX + timelineViewportWidth) / viewport.pixelsPerDay)) - 1)
        )
        let visibleStart = layout.date(atDayOffset: startOffset, calendar: cal)
        let visibleEnd = layout.date(atDayOffset: endOffset, calendar: cal)
        let f = DateFormatter()
        f.dateFormat = layout.tickStepDays >= 14 ? "MMM d, yyyy" : "MMM d"
        if cal.isDate(visibleStart, inSameDayAs: visibleEnd) {
            return f.string(from: visibleStart)
        }
        return "\(f.string(from: visibleStart)) – \(f.string(from: visibleEnd))"
    }

    private var ganttEmptyPanel: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.muted)

            Text("No scheduled tasks")
                .font(Theme.sans(17, weight: .semibold))
                .foregroundStyle(Theme.primary)

            Text(ganttEmptyMessage)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            if colorByCategory, openUnscheduledCount > 0 {
                Text("\(openUnscheduledCount) open \(openUnscheduledCount == 1 ? "task" : "tasks") not on the timeline yet")
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(40)
        .background(Theme.background)
    }

    private var ganttEmptyMessage: String {
        if colorByCategory {
            return "Add tasks to categories, set a due date and duration, then they’ll appear here color-coded."
        }
        return "Set duration and a start or end date (or add a dependency) on a task — it will show up here."
    }

    private var ganttToolbar: some View {
        DetailToolbar {
            Text(visibleRangeLabel)
                .font(Theme.sans(13, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .animation(.easeOut(duration: 0.15), value: visibleRangeLabel)
        } trailing: {
            HStack(spacing: 10) {
                Button {
                    if viewport.isZoomAnchoredToNow {
                        viewport.releaseNowAnchor()
                    } else {
                        viewport.engageNowAnchor(layout: timelineLayout)
                    }
                } label: {
                    Label("Anchor", systemImage: viewport.isZoomAnchoredToNow ? "pin.fill" : "pin")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(TogglePillButtonStyle(isOn: viewport.isZoomAnchoredToNow))
                .help(
                    viewport.isZoomAnchoredToNow
                        ? "Anchored — horizontal scroll off, now line on the left. Click to unlock."
                        : "Lock the now line on the left and disable horizontal scrolling"
                )

                Text(rows.isEmpty ? "Nothing to plot" : "\(rows.count) \(rows.count == 1 ? "task" : "tasks")")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

}

private struct GanttTimelineHeader: View {
    let layout: GanttTimelineLayout
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(layout.tickOffsets, id: \.self) { offset in
                let date = layout.date(atDayOffset: offset)
                let span = layout.tickSpanDays(from: offset)
                VStack(alignment: .leading, spacing: 1) {
                    if showsMonthLabel(for: date) {
                        Text(monthLabel(for: date))
                            .font(Theme.sans(9, weight: .semibold))
                            .foregroundStyle(Theme.faint)
                    }
                    Text(tickLabel(for: date))
                        .font(Theme.sans(11, weight: Calendar.current.isDateInToday(date) ? .semibold : .regular))
                        .foregroundStyle(Calendar.current.isDateInToday(date) ? Theme.primary : Theme.secondary)
                }
                .frame(width: CGFloat(span) * layout.pixelsPerDay, height: height, alignment: .leading)
                .padding(.leading, 6)
            }
        }
        .frame(width: layout.timelineWidth, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
        .background(Theme.surface)
    }

    private func showsMonthLabel(for date: Date) -> Bool {
        layout.tickStepDays >= 7 || Calendar.current.component(.day, from: date) == 1
    }

    private func monthLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f.string(from: date).uppercased()
    }

    private func tickLabel(for date: Date) -> String {
        let f = DateFormatter()
        switch layout.tickStepDays {
        case 1:
            f.dateFormat = layout.pixelsPerDay >= 48 ? "EEE d" : "EEE d"
        case 2...6:
            f.dateFormat = "d EEE"
        case 7...13:
            f.dateFormat = "MMM d"
        default:
            f.dateFormat = "MMM d"
        }
        return f.string(from: date)
    }
}

private struct GanttTodayMarker: View {
    let rangeStart: Date
    let dayCount: Int
    let dayWidth: CGFloat
    let headerHeight: CGFloat
    let rowHeight: CGFloat
    let rowCount: Int

    var body: some View {
        GeometryReader { geo in
            if let offset = todayOffset {
                Rectangle()
                    .fill(Theme.todayLine.opacity(0.45))
                    .frame(width: 2, height: geo.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: CGFloat(offset) * dayWidth)
            }
        }
        .frame(width: CGFloat(dayCount) * dayWidth, height: headerHeight + CGFloat(rowCount) * rowHeight)
        .allowsHitTesting(false)
    }

    private var todayOffset: Int? {
        GanttScheduleMath.dayOffset(
            from: Calendar.current.startOfDay(for: rangeStart),
            to: Calendar.current.startOfDay(for: .now)
        )
    }
}

private struct GanttRowLabel: View {
    let row: TaskDisplayRow
    let labelWidth: CGFloat
    let rowHeight: CGFloat
    var colorByCategory: Bool
    var onSelect: () -> Void

    private var task: TaskItem { row.task }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                Color.clear.frame(width: CGFloat(row.depth) * 16 + 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .lineLimit(2)
                        .font(Theme.sans(row.depth > 0 ? 12 : 13, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .multilineTextAlignment(.leading)
                    if colorByCategory, let project = task.project, project.isUserCategory {
                        CategoryTag(project: project, size: 10, weight: .medium)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(width: labelWidth, height: rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.surface)
    }
}

private struct GanttTimelineRow: View {
    let row: TaskDisplayRow
    let rangeStart: Date
    let dayCount: Int
    let dayWidth: CGFloat
    let rowHeight: CGFloat
    var colorByCategory: Bool
    @Binding var popoverPresented: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void

    private var task: TaskItem { row.task }

    var body: some View {
        ZStack(alignment: .leading) {
            if let frame = barFrame {
                HStack(spacing: 0) {
                    Color.clear.frame(width: frame.x, height: 1)
                    GanttTaskBar(
                        task: task,
                        width: frame.width,
                        rowHeight: rowHeight,
                        depth: row.depth,
                        colorByCategory: colorByCategory,
                        popoverPresented: $popoverPresented,
                        onSelect: onSelect,
                        onEdit: onEdit
                    )
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: CGFloat(dayCount) * dayWidth, height: rowHeight, alignment: .leading)
    }

    private var barFrame: (x: CGFloat, width: CGFloat)? {
        guard let span = task.ganttBarSpan() else { return nil }
        let cal = Calendar.current
        let rangeDay = cal.startOfDay(for: rangeStart)

        guard let startOffset = GanttScheduleMath.dayOffset(from: rangeDay, to: span.start),
              let endOffset = GanttScheduleMath.dayOffset(from: rangeDay, to: span.end) else {
            return nil
        }

        let columnSpan = max(endOffset - startOffset + 1, 1)
        let x = CGFloat(startOffset) * dayWidth
        let width = max(CGFloat(columnSpan) * dayWidth - 4, dayWidth * 0.55)
        return (x, width)
    }
}

private struct GanttTaskBar: View {
    let task: TaskItem
    let width: CGFloat
    let rowHeight: CGFloat
    let depth: Int
    var colorByCategory: Bool
    @Binding var popoverPresented: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void

    @State private var isHovered = false

    private var barHeight: CGFloat { rowHeight - (depth > 0 ? 18 : 12) }

    var body: some View {
        Button(action: onSelect) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(barColor.opacity(isHovered || popoverPresented ? 1 : 0.9))
                .overlay {
                    if popoverPresented {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.35), lineWidth: 2)
                    }
                }
                .frame(width: width, height: barHeight)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $popoverPresented, arrowEdge: .top) {
            GanttBarDetailPopover(task: task, onEdit: onEdit)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onEdit() })
    }

    private var barColor: Color {
        if let project = task.project, project.isUserCategory {
            return project.ganttBarColor.opacity(depth > 0 ? 0.82 : 1)
        }
        return depth > 0 ? Theme.barSubtask : Theme.barFill
    }
}

private enum GanttBarDetailBuilder {
    static func scheduleLine(for task: TaskItem) -> String? {
        guard let span = task.ganttBarSpan() else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        return "On chart: \(f.string(from: span.start)) – \(f.string(from: span.end))"
    }

    static func dueLine(for task: TaskItem) -> String? {
        guard task.dueDate != nil else { return nil }
        return "Due: \(DueDateFormatting.taskDueLabel(task) ?? "")"
    }

    static func calendarLine(for task: TaskItem) -> String? {
        guard task.hasCalendarLink else { return nil }
        let title = task.calendarEventTitle ?? "Calendar event"
        if let block = task.todayBlockTimeLabel {
            return "Calendar: \(title) (\(block))"
        }
        return "Calendar: \(title)"
    }
}

private struct GanttBarDetailPopover: View {
    let task: TaskItem
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(Theme.sans(15, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                if let line = GanttBarDetailBuilder.scheduleLine(for: task) {
                    detailRow(icon: "calendar.badge.clock", text: line)
                }
                if let line = GanttBarDetailBuilder.dueLine(for: task) {
                    detailRow(icon: "flag", text: line)
                }
                detailRow(
                    icon: "hourglass",
                    text: "Duration: \(DurationFormatting.label(for: task.durationDays))"
                )
                if let line = GanttBarDetailBuilder.calendarLine(for: task) {
                    detailRow(icon: "calendar", text: line, accent: task.calendarAccentColor)
                }
            }

            HStack {
                Spacer()
                Button("Edit task…", action: onEdit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func detailRow(icon: String, text: String, accent: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accent ?? Theme.muted)
                .frame(width: 16)
            Text(text)
                .font(Theme.sans(12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GanttDependencyOverlay: View {
    let rows: [TaskDisplayRow]
    let edges: [GanttDependencyEdge]
    let rangeStart: Date
    let dayWidth: CGFloat
    let labelWidth: CGFloat
    let rowHeight: CGFloat
    let headerHeight: CGFloat

    var body: some View {
        Canvas { context, _ in
            let indexMap = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.task.uuid, $0) })

            for edge in edges {
                guard let fromIdx = indexMap[edge.from],
                      let toIdx = indexMap[edge.to],
                      let fromTask = rows.first(where: { $0.task.uuid == edge.from })?.task,
                      let toTask = rows.first(where: { $0.task.uuid == edge.to })?.task else { continue }

                guard let anchor = anchorPoints(
                    kind: edge.kind,
                    from: fromTask,
                    to: toTask,
                    fromRow: fromIdx,
                    toRow: toIdx
                ) else { continue }

                var path = Path()
                path.move(to: anchor.from)
                let midX = (anchor.from.x + anchor.to.x) / 2
                path.addCurve(
                    to: anchor.to,
                    control1: CGPoint(x: midX, y: anchor.from.y),
                    control2: CGPoint(x: midX, y: anchor.to.y)
                )
                context.stroke(path, with: .color(Theme.linkLine), style: StrokeStyle(lineWidth: 1.25, dash: [4, 3]))
            }
        }
        .allowsHitTesting(false)
    }

    private func anchorPoints(
        kind: TaskLinkKind,
        from: TaskItem,
        to: TaskItem,
        fromRow: Int,
        toRow: Int
    ) -> (from: CGPoint, to: CGPoint)? {
        let y1 = headerHeight + CGFloat(fromRow) * rowHeight + rowHeight / 2
        let y2 = headerHeight + CGFloat(toRow) * rowHeight + rowHeight / 2

        let fromSpan = from.ganttBarSpan()
        let toSpan = to.ganttBarSpan()
        let fromStart = fromSpan?.start ?? from.scheduledStart
        let fromEnd = fromSpan?.end ?? from.scheduledEnd ?? from.scheduledStart
        let toStart = toSpan?.start ?? to.scheduledStart
        let toEnd = toSpan?.end ?? to.scheduledEnd ?? to.scheduledStart

        switch kind {
        case .finishToStart:
            guard let fe = fromEnd, let ts = toStart else { return nil }
            return (
                CGPoint(x: labelWidth + xOffset(for: fe, atStart: false), y: y1),
                CGPoint(x: labelWidth + xOffset(for: ts, atStart: true), y: y2)
            )
        case .startToStart:
            guard let fs = fromStart, let ts = toStart else { return nil }
            return (
                CGPoint(x: labelWidth + xOffset(for: fs, atStart: true), y: y1),
                CGPoint(x: labelWidth + xOffset(for: ts, atStart: true), y: y2)
            )
        case .finishToFinish:
            guard let fe = fromEnd, let te = toEnd else { return nil }
            return (
                CGPoint(x: labelWidth + xOffset(for: fe, atStart: false), y: y1),
                CGPoint(x: labelWidth + xOffset(for: te, atStart: false), y: y2)
            )
        case .startToFinish:
            guard let fs = fromStart, let te = toEnd else { return nil }
            return (
                CGPoint(x: labelWidth + xOffset(for: fs, atStart: true), y: y1),
                CGPoint(x: labelWidth + xOffset(for: te, atStart: false), y: y2)
            )
        }
    }

    private func xOffset(for date: Date, atStart: Bool) -> CGFloat {
        let cal = Calendar.current
        let rangeDay = cal.startOfDay(for: rangeStart)
        let d = cal.startOfDay(for: date)
        guard let offset = GanttScheduleMath.dayOffset(from: rangeDay, to: d) else { return 0 }
        return CGFloat(offset) * dayWidth + (atStart ? 2 : dayWidth - 2)
    }
}

@Observable
final class GanttViewportState {
    var pixelsPerDay: CGFloat = 44
    var zoomBaseline: CGFloat = 44
    var scrollOffsetX: CGFloat = 0
    var scrollApplyToken: UInt = 0
    var pendingScrollX: CGFloat = 0
    var userHasPannedTimeline = false
    var isZoomAnchoredToNow = false
    var isPinching = false
    var didSetInitialViewport = false

    func requestScroll(to x: CGFloat) {
        pendingScrollX = x
        scrollApplyToken &+= 1
    }

    func engageNowAnchor(layout: GanttTimelineLayout) {
        isZoomAnchoredToNow = true
        userHasPannedTimeline = false
        let dayOffset = CGFloat(GanttScheduleMath.dayOffset(from: layout.rangeStart, to: .now) ?? 0)
        requestScroll(to: dayOffset * layout.pixelsPerDay)
    }

    func releaseNowAnchor() {
        isZoomAnchoredToNow = false
        userHasPannedTimeline = true
    }
}

final class GanttViewportStore {
    private var states: [String: GanttViewportState] = [:]

    func state(for destination: MainDestination) -> GanttViewportState {
        let key = Self.key(for: destination)
        if let existing = states[key] { return existing }
        let created = GanttViewportState()
        states[key] = created
        return created
    }

    static func key(for destination: MainDestination) -> String {
        switch destination {
        case .inbox: return "inbox"
        case .today: return "today"
        case .upcoming: return "upcoming"
        case .category(let id): return "category:\(id.hashValue)"
        }
    }
}

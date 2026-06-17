import SwiftUI

struct TodayTimeBlockGridView: View {
    let day: Date
    let events: [CalendarEventSummary]
    @Binding var selectionStart: Date?
    @Binding var selectionEnd: Date?
    var draftTitle: String? = nil

    var dayStartHour: Int = 6
    var dayEndHour: Int = 23
    var snapMinutes: Int = 15
    var hourHeight: CGFloat = 32

    private let calendar = Calendar.current

    private var hourCount: Int { max(dayEndHour - dayStartHour, 1) }
    private var gridHeight: CGFloat { CGFloat(hourCount) * hourHeight }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    timeGutter
                    dayColumn
                        .frame(maxWidth: .infinity)
                }
                .frame(height: gridHeight)
                .id("grid")
            }
            .onAppear {
                scrollToNow(proxy: proxy)
            }
        }
        .background(Theme.background)
    }

    private var timeGutter: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: gridHeight)
            ForEach(dayStartHour..<dayEndHour, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(Theme.sans(9))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 40, height: hourHeight, alignment: .topTrailing)
                    .padding(.trailing, 6)
                    .offset(y: CGFloat(hour - dayStartHour) * hourHeight + 2)
            }
        }
        .frame(width: 46)
    }

    private var dayColumn: some View {
        let placed = layoutTimedEvents()
        let isToday = calendar.isDateInToday(day)

        return ZStack(alignment: .topLeading) {
            hourGrid
            if isToday {
                nowLine
            }
            ForEach(placed) { item in
                existingEventBlock(item)
            }
            if let start = selectionStart, let end = selectionEnd {
                selectionBlock(start: start, end: end)
            }
            Color.clear
                .contentShape(Rectangle())
                .gesture(dragGesture)
        }
        .frame(height: gridHeight)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.border.opacity(0.5))
                .frame(width: 0.5)
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(dayStartHour..<dayEndHour, id: \.self) { hour in
                Rectangle()
                    .fill(hour == dayStartHour ? Color.clear : Theme.border.opacity(0.28))
                    .frame(height: 0.5)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .frame(height: hourHeight)
            }
        }
    }

    @ViewBuilder
    private var nowLine: some View {
        let y = yOffset(for: .now)
        if y >= 0, y <= gridHeight {
            HStack(spacing: 0) {
                Circle()
                    .fill(Color.red.opacity(0.85))
                    .frame(width: 6, height: 6)
                Rectangle()
                    .fill(Color.red.opacity(0.85))
                    .frame(height: 1)
            }
            .offset(y: y)
        }
    }

    private func existingEventBlock(_ placed: TodayPlacedEvent) -> some View {
        let frame = blockFrame(start: placed.event.start, end: placed.event.end, column: placed.column, totalColumns: placed.totalColumns)
        let fill = placed.event.calendarColor.opacity(0.55)
        let textColor = CalendarStyle.readableText(on: placed.event.calendarColor)

        return VStack(alignment: .leading, spacing: 1) {
            Text(placed.event.title)
                .font(Theme.sans(10, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
    }

    private func selectionBlock(start: Date, end: Date) -> some View {
        let frame = blockFrame(start: start, end: end, column: 0, totalColumns: 1)
        return VStack(alignment: .leading, spacing: 2) {
            Text(draftTitle ?? "New block")
                .font(Theme.sans(10, weight: .semibold))
                .lineLimit(2)
            Text(rangeLabel(start: start, end: end))
                .font(Theme.sans(9))
        }
        .foregroundStyle(Color.white.opacity(0.95))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: max(frame.width - 8, 60), height: max(frame.height, 22), alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Theme.primary.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .offset(x: frame.minX + 4, y: frame.minY)
        .allowsHitTesting(false)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let startY = value.startLocation.y
                let currentY = value.location.y
                let t0 = date(atY: startY)
                let t1 = date(atY: currentY)
                let ordered = orderedRange(t0, t1, minimumMinutes: snapMinutes)
                selectionStart = ordered.start
                selectionEnd = ordered.end
            }
            .onEnded { value in
                if selectionStart == nil {
                    let t = date(atY: value.location.y)
                    selectionStart = t
                    selectionEnd = calendar.date(byAdding: .hour, value: 1, to: t) ?? t.addingTimeInterval(3600)
                }
                if let s = selectionStart, let e = selectionEnd {
                    let ordered = orderedRange(s, e, minimumMinutes: snapMinutes)
                    selectionStart = ordered.start
                    selectionEnd = ordered.end
                }
            }
    }

    private func layoutTimedEvents() -> [TodayPlacedEvent] {
        let dayEvents = events.filter { !$0.isAllDay && eventOverlaps(day: day, event: $0) }
        let sorted = dayEvents.sorted { $0.start < $1.start }
        var columns: [[CalendarEventSummary]] = []

        for event in sorted {
            var placed = false
            for index in columns.indices {
                if let last = columns[index].last, !overlaps(last, event) {
                    columns[index].append(event)
                    placed = true
                    break
                }
            }
            if !placed { columns.append([event]) }
        }

        var result: [TodayPlacedEvent] = []
        let totalColumns = max(columns.count, 1)
        for (columnIndex, column) in columns.enumerated() {
            for event in column {
                result.append(TodayPlacedEvent(event: event, column: columnIndex, totalColumns: totalColumns))
            }
        }
        return result
    }

    private func blockFrame(start: Date, end: Date, column: Int, totalColumns: Int) -> CGRect {
        let dayStart = calendar.startOfDay(for: day)
        let visibleStart = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: dayStart) ?? dayStart
        let visibleEnd = calendar.date(bySettingHour: dayEndHour, minute: 0, second: 0, of: dayStart) ?? dayStart

        let clipStart = max(start, visibleStart)
        let clipEnd = min(end, visibleEnd)
        let duration = max(clipEnd.timeIntervalSince(clipStart), Double(snapMinutes) * 60)

        let yMinutes = clipStart.timeIntervalSince(visibleStart) / 60
        let y = CGFloat(yMinutes / 60) * hourHeight
        let h = max(CGFloat(duration / 3600) * hourHeight, 20)

        let columnWidth: CGFloat = 280
        let inset: CGFloat = 4
        let usable = columnWidth - inset * 2
        let slotWidth = usable / CGFloat(max(totalColumns, 1))
        let w = max(slotWidth - 4, 40)
        let x = inset + CGFloat(column) * slotWidth

        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func date(atY y: CGFloat) -> Date {
        let clampedY = min(max(y, 0), gridHeight - 1)
        let minutesFromStart = Double(clampedY / hourHeight) * 60
        let snapped = (Int(minutesFromStart) / snapMinutes) * snapMinutes
        let dayStart = calendar.startOfDay(for: day)
        let base = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: dayStart) ?? dayStart
        return calendar.date(byAdding: .minute, value: snapped, to: base) ?? base
    }

    private func yOffset(for date: Date) -> CGFloat {
        let dayStart = calendar.startOfDay(for: day)
        let visibleStart = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: dayStart) ?? dayStart
        let minutes = date.timeIntervalSince(visibleStart) / 60
        return CGFloat(minutes / 60) * hourHeight
    }

    private func orderedRange(_ a: Date, _ b: Date, minimumMinutes: Int) -> (start: Date, end: Date) {
        let minDuration = TimeInterval(minimumMinutes * 60)
        if a <= b {
            let end = b.timeIntervalSince(a) < minDuration ? a.addingTimeInterval(minDuration) : b
            return (a, end)
        }
        let end = a.timeIntervalSince(b) < minDuration ? b.addingTimeInterval(minDuration) : a
        return (b, end)
    }

    private func eventOverlaps(day: Date, event: CalendarEventSummary) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return event.start < dayEnd && event.end > dayStart
    }

    private func overlaps(_ a: CalendarEventSummary, _ b: CalendarEventSummary) -> Bool {
        a.start < b.end && b.start < a.end
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12a" }
        if hour < 12 { return "\(hour)a" }
        if hour == 12 { return "12p" }
        return "\(hour - 12)p"
    }

    private func rangeLabel(start: Date, end: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    private func scrollToNow(proxy: ScrollViewProxy) {
        guard calendar.isDateInToday(day) else { return }
        let y = yOffset(for: .now)
        let anchorY = min(max((y - 120) / max(gridHeight, 1), 0), 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            proxy.scrollTo("grid", anchor: UnitPoint(x: 0.5, y: anchorY))
        }
    }
}

private struct TodayPlacedEvent: Identifiable {
    let event: CalendarEventSummary
    let column: Int
    let totalColumns: Int

    var id: String { event.id }
}

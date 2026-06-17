import SwiftUI

struct CalendarWeekPickerView: View {
    let weekDays: [Date]
    let events: [CalendarEventSummary]
    var searchQuery: String = ""
    var onSelect: (CalendarEventSummary) -> Void

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 28
    private let gutterWidth: CGFloat = 44
    private let dayStartHour = 0
    private let dayEndHour = 24
    private let minEventHeight: CGFloat = 18

    @State private var hoveredID: String?

    private var hourCount: Int { dayEndHour - dayStartHour }
    private var gridHeight: CGFloat { CGFloat(hourCount) * hourHeight }

    private var filteredEvents: [CalendarEventSummary] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return events }
        return events.filter {
            $0.title.lowercased().contains(q) || $0.calendarTitle.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            dayHeaderRow
            Divider().overlay(Theme.border)

            allDayStrip

            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    timeGutter
                    ForEach(weekDays, id: \.self) { day in
                        dayColumn(day)
                            .frame(minWidth: 100, maxWidth: .infinity)
                    }
                }
                .frame(minWidth: gutterWidth + CGFloat(weekDays.count) * 100)
                .frame(height: gridHeight, alignment: .top)
            }
            .frame(maxHeight: .infinity)
        }
        .background(Theme.background)
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutterWidth)
            ForEach(weekDays, id: \.self) { day in
                dayHeaderCell(day)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .background(Theme.background)
    }

    private func dayHeaderCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        return VStack(spacing: 3) {
            Text(dayName(day))
                .font(Theme.sans(10, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text(dayNumber(day))
                .font(Theme.sans(15, weight: isToday ? .bold : .semibold))
                .foregroundStyle(isToday ? Color.white : Theme.primary)
                .frame(width: 30, height: 30)
                .background {
                    if isToday {
                        Circle().fill(Theme.defaultAccent)
                    }
                }
        }
    }

    @ViewBuilder
    private var allDayStrip: some View {
        let hasAllDay = weekDays.contains { !allDayEvents(on: $0).isEmpty }
        if hasAllDay {
            HStack(alignment: .top, spacing: 0) {
                Text("all-day")
                    .font(Theme.sans(9))
                    .foregroundStyle(Theme.faint)
                    .frame(width: gutterWidth, alignment: .trailing)
                    .padding(.trailing, 6)
                ForEach(weekDays, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(allDayEvents(on: day)) { event in
                            eventChip(event)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .topLeading)
                    .padding(.horizontal, 3)
                }
            }
            .padding(.vertical, 8)
            .background(Theme.surface.opacity(0.5))
            Divider().overlay(Theme.border)
        }
    }

    private var timeGutter: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: gridHeight)
            ForEach(dayStartHour..<dayEndHour, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(Theme.sans(9))
                    .foregroundStyle(Theme.faint)
                    .frame(width: gutterWidth - 6, height: hourHeight, alignment: .topTrailing)
                    .offset(y: CGFloat(hour - dayStartHour) * hourHeight + 2)
            }
        }
        .frame(width: gutterWidth)
    }

    private func dayColumn(_ day: Date) -> some View {
        let placed = layoutTimedEvents(on: day)
        let isToday = calendar.isDateInToday(day)

        return ZStack(alignment: .topLeading) {
            hourGrid
            if isToday {
                Rectangle()
                    .fill(Theme.softAccentFill(Theme.defaultAccent, opacity: 0.06))
                    .frame(height: gridHeight)
            }
            GeometryReader { geo in
                ForEach(placed) { item in
                    eventBlock(item, day: day, columnWidth: geo.size.width)
                }
            }
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
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(hour == dayStartHour ? Color.clear : Theme.border.opacity(0.28))
                        .frame(height: 0.5)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(height: hourHeight)
            }
        }
    }

    private func eventBlock(_ placed: PlacedCalendarEvent, day: Date, columnWidth: CGFloat) -> some View {
        let frame = placed.frame(
            in: day,
            calendar: calendar,
            dayStartHour: dayStartHour,
            dayEndHour: dayEndHour,
            hourHeight: hourHeight,
            minHeight: minEventHeight,
            columnWidth: columnWidth
        )
        let isHovered = hoveredID == placed.event.id
        let dimmed = !matchesSearch(placed.event)
        let fill = placed.event.calendarColor.opacity(dimmed ? 0.35 : 0.92)
        let textColor = CalendarStyle.readableText(on: placed.event.calendarColor)

        return Button {
            onSelect(placed.event)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(placed.event.title)
                    .font(Theme.sans(10, weight: .semibold))
                    .lineLimit(frame.height > 32 ? 2 : 1)
                    .foregroundStyle(textColor)
                if frame.height > 26 {
                    Text(shortTime(placed.event.start))
                        .font(Theme.sans(8))
                        .foregroundStyle(textColor.opacity(0.9))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isHovered ? Theme.primary : Color.white.opacity(0.25), lineWidth: isHovered ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .opacity(dimmed ? 0.45 : 1)
        .onHover { inside in
            hoveredID = inside ? placed.event.id : (hoveredID == placed.event.id ? nil : hoveredID)
        }
        .help("\(placed.event.title)\n\(CalendarEventFormatting.rangeLabel(start: placed.event.start, end: placed.event.end, isAllDay: placed.event.isAllDay))")
    }

    private func eventChip(_ event: CalendarEventSummary) -> some View {
        let textColor = CalendarStyle.readableText(on: event.calendarColor)
        return Button {
            onSelect(event)
        } label: {
            Text(event.title)
                .font(Theme.sans(9, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(textColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(event.calendarColor.opacity(matchesSearch(event) ? 0.9 : 0.35))
                )
        }
        .buttonStyle(.plain)
    }

    private func allDayEvents(on day: Date) -> [CalendarEventSummary] {
        filteredEvents.filter { $0.isAllDay && eventOverlaps(day: day, event: $0) }
    }

    private func layoutTimedEvents(on day: Date) -> [PlacedCalendarEvent] {
        let dayEvents = filteredEvents.filter { !$0.isAllDay && eventOverlaps(day: day, event: $0) }
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
            if !placed {
                columns.append([event])
            }
        }

        var result: [PlacedCalendarEvent] = []
        let totalColumns = max(columns.count, 1)
        for (columnIndex, column) in columns.enumerated() {
            for event in column {
                result.append(
                    PlacedCalendarEvent(event: event, column: columnIndex, totalColumns: totalColumns)
                )
            }
        }
        return result
    }

    private func eventOverlaps(day: Date, event: CalendarEventSummary) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return event.start < dayEnd && event.end > dayStart
    }

    private func overlaps(_ a: CalendarEventSummary, _ b: CalendarEventSummary) -> Bool {
        a.start < b.end && b.start < a.end
    }

    private func matchesSearch(_ event: CalendarEventSummary) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return event.title.lowercased().contains(q) || event.calendarTitle.lowercased().contains(q)
    }

    private func dayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private func dayNumber(_ date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

private struct PlacedCalendarEvent: Identifiable {
    let event: CalendarEventSummary
    let column: Int
    let totalColumns: Int

    var id: String { event.id }

    func frame(
        in day: Date,
        calendar: Calendar,
        dayStartHour: Int,
        dayEndHour: Int,
        hourHeight: CGFloat,
        minHeight: CGFloat,
        columnWidth: CGFloat
    ) -> CGRect {
        let dayStart = calendar.startOfDay(for: day)
        let visibleStart = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: dayStart) ?? dayStart
        let visibleEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let clipStart = max(event.start, visibleStart)
        let clipEnd = min(event.end, visibleEnd)
        let duration = max(clipEnd.timeIntervalSince(clipStart), 15 * 60)

        let yMinutes = clipStart.timeIntervalSince(visibleStart) / 60
        let y = CGFloat(yMinutes / 60) * hourHeight
        let h = max(CGFloat(duration / 3600) * hourHeight, minHeight)

        let inset: CGFloat = 2
        let usable = columnWidth - inset * 2
        let slotWidth = usable / CGFloat(max(totalColumns, 1))
        let w = max(slotWidth - 2, 16)
        let x = inset + CGFloat(column) * slotWidth

        return CGRect(x: x, y: y, width: w, height: h)
    }
}

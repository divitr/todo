import Foundation

enum GanttScheduleMath {
    static func wholeDays(for durationDays: Double) -> Int {
        max(Int(ceil(durationDays)), 1)
    }

    static func inclusiveEnd(start: Date, durationDays: Double, calendar: Calendar = .current) -> Date {
        TaskItem.inclusiveScheduleEnd(start: start, durationDays: durationDays, calendar: calendar)
    }

    static func inclusiveStart(end: Date, durationDays: Double, calendar: Calendar = .current) -> Date {
        TaskItem.inclusiveScheduleStart(end: end, durationDays: durationDays, calendar: calendar)
    }

    static func dayAfterInclusiveEnd(_ end: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!
    }

    static func inclusiveDayCount(from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: start)
        let b = calendar.startOfDay(for: end)
        let diff = calendar.dateComponents([.day], from: a, to: b).day ?? 0
        return max(diff + 1, 1)
    }

    static func dayOffset(from rangeStart: Date, to date: Date, calendar: Calendar = .current) -> Int? {
        let rangeDay = calendar.startOfDay(for: rangeStart)
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: rangeDay, to: target).day
    }
}

struct GanttTimelineLayout {
    let rangeStart: Date
    let rangeEnd: Date
    let dayCount: Int
    let pixelsPerDay: CGFloat
    let tickStepDays: Int

    var timelineWidth: CGFloat { CGFloat(dayCount) * pixelsPerDay }

    var tickOffsets: [Int] {
        var offsets: [Int] = []
        var i = 0
        while i < dayCount {
            offsets.append(i)
            i += tickStepDays
        }
        return offsets
    }

    func tickSpanDays(from offset: Int) -> Int {
        guard let idx = tickOffsets.firstIndex(of: offset) else { return tickStepDays }
        let next = idx + 1 < tickOffsets.count ? tickOffsets[idx + 1] : dayCount
        return max(next - offset, 1)
    }

    func date(atDayOffset offset: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset, to: rangeStart)!
    }

    static func make(
        tasks: [TaskItem],
        pixelsPerDay: CGFloat,
        viewportWidth: CGFloat,
        calendar: Calendar = .current
    ) -> GanttTimelineLayout {
        let today = calendar.startOfDay(for: .now)
        var dataStart = today
        var dataEnd = calendar.date(byAdding: .day, value: 14, to: today)!

        for task in tasks {
            if let span = task.ganttBarSpan(calendar: calendar) {
                dataStart = min(dataStart, span.start)
                dataEnd = max(dataEnd, span.end)
            }
        }

        let tickStep = tickStepDays(for: pixelsPerDay)
        let dataSpan = GanttScheduleMath.inclusiveDayCount(from: dataStart, to: dataEnd, calendar: calendar)

        let leadIn = 14
        let start = calendar.date(byAdding: .day, value: -leadIn, to: min(dataStart, today))!

        let viewportDays = max(Int(ceil(viewportWidth / pixelsPerDay)), 14)
        let zoomMultiplier = max(1.0, 44.0 / pixelsPerDay)
        let extendedDays = Int(ceil(Double(viewportDays) * zoomMultiplier)) + 21
        let totalDays = max(dataSpan + leadIn + 14, extendedDays, 42)

        var end = calendar.date(byAdding: .day, value: totalDays - 1, to: start)!
        if end < dataEnd {
            end = dataEnd
        }

        let dayCount = GanttScheduleMath.inclusiveDayCount(from: start, to: end, calendar: calendar)

        return GanttTimelineLayout(
            rangeStart: start,
            rangeEnd: end,
            dayCount: dayCount,
            pixelsPerDay: pixelsPerDay,
            tickStepDays: tickStep
        )
    }

    static func tickStepDays(for pixelsPerDay: CGFloat) -> Int {
        if pixelsPerDay >= 40 { return 1 }
        if pixelsPerDay >= 28 { return 2 }
        if pixelsPerDay >= 18 { return 7 }
        if pixelsPerDay >= 10 { return 14 }
        if pixelsPerDay >= 6 { return 28 }
        return 30
    }

    static func todayScrollOffset(layout: GanttTimelineLayout, calendar: Calendar = .current) -> CGFloat {
        guard let offset = GanttScheduleMath.dayOffset(from: layout.rangeStart, to: .now, calendar: calendar) else {
            return 0
        }
        return max(0, CGFloat(offset) * layout.pixelsPerDay)
    }
}

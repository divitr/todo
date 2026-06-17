import SwiftUI

struct CalendarEventPickerSheet: View {
    var anchorDate: Date = .now
    var onSelect: (CalendarEventSummary) -> Void
    var onDismiss: () -> Void

    @StateObject private var calendar = CalendarService.shared
    @State private var events: [CalendarEventSummary] = []
    @State private var search = ""
    @State private var focusDate: Date = .now
    @State private var accessDenied = false
    @State private var isLoading = true

    private let cal = Calendar.current

    private var weekDays: [Date] {
        guard let interval = cal.dateInterval(of: .weekOfYear, for: focusDate) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var weekTitle: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let year = cal.component(.year, from: first)
        let endYear = cal.component(.year, from: last)
        if year == endYear {
            return "\(f.string(from: first)) – \(f.string(from: last)), \(year)"
        }
        return "\(f.string(from: first)), \(year) – \(f.string(from: last)), \(endYear)"
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if accessDenied {
                ContentUnavailableView {
                    Label("Calendar Access Required", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Allow todo in System Settings → Privacy & Security → Calendars.")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxHeight: .infinity)
            } else {
                searchBar

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if events.isEmpty {
                    ContentUnavailableView(
                        "No Events",
                        systemImage: "calendar",
                        description: Text("No events this week. Try another week or create one in Calendar.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    CalendarWeekPickerView(
                        weekDays: weekDays,
                        events: events,
                        searchQuery: search,
                        onSelect: onSelect
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(width: 780, height: 640)
        .onAppear { focusDate = anchorDate }
        .task(id: focusDate) { await loadEvents() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Pick Event")
                .font(.headline)

            HStack(spacing: 6) {
                Button {
                    shiftWeek(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous week")

                Text(weekTitle)
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(minWidth: 180)

                Button {
                    shiftWeek(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next week")

                Button("Today") {
                    focusDate = .now
                }
                .controlSize(.small)
            }

            Spacer()

            Text("Click an event block")
                .font(Theme.sans(11))
                .foregroundStyle(Theme.faint)

            Button("Cancel", action: onDismiss)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)
            TextField("Search events", text: $search)
                .textFieldStyle(.plain)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func shiftWeek(by weeks: Int) {
        if let next = cal.date(byAdding: .weekOfYear, value: weeks, to: focusDate) {
            focusDate = next
        }
    }

    private func loadEvents() async {
        isLoading = true
        let granted = await calendar.requestAccess()
        accessDenied = !granted
        guard granted else {
            isLoading = false
            return
        }
        guard let interval = cal.dateInterval(of: .weekOfYear, for: focusDate) else {
            isLoading = false
            return
        }
        let start = cal.date(byAdding: .day, value: -1, to: interval.start) ?? interval.start
        let end = cal.date(byAdding: .day, value: 2, to: interval.end) ?? interval.end
        events = calendar.fetchEvents(from: start, to: end)
        isLoading = false
    }
}

enum CalendarEventFormatting {
    static func rangeLabel(start: Date, end: Date, isAllDay: Bool) -> String {
        let f = DateFormatter()
        if isAllDay {
            f.dateStyle = .medium
            f.timeStyle = .none
            if Calendar.current.isDate(start, inSameDayAs: end) {
                return f.string(from: start)
            }
            return "\(f.string(from: start)) – \(f.string(from: end))"
        }
        f.dateStyle = .medium
        f.timeStyle = .short
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    static func durationLabel(days: Double) -> String {
        let hours = days * 24
        if hours < 1 { return "\(Int(max(hours * 60, 15)))m" }
        if hours < 24 { return hours == floor(hours) ? "\(Int(hours))h" : String(format: "%.1fh", hours) }
        return days == floor(days) ? "\(Int(days))d" : String(format: "%.2gd", days)
    }
}

import AppKit
import Combine
import EventKit
import Foundation
import SwiftUI

enum CalendarEventNotes {
    static let footerLine = "(added by todo)"

    static func formatted(description: String) -> String {
        let body = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            return footerLine
        }
        if body.hasSuffix(footerLine) { return body }
        return "\(body)\n\n\(footerLine)"
    }
}

struct CalendarPickerCalendar: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color
}

enum CalendarCreateEventError: LocalizedError {
    case notAuthorized
    case noWritableCalendar
    case missingEventIdentifier
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar access is required to create events."
        case .noWritableCalendar:
            return "No calendar on this Mac allows new events."
        case .missingEventIdentifier:
            return "The event was saved but could not be linked."
        case .saveFailed(let detail):
            return detail
        }
    }
}

struct CalendarCreateEventRequest {
    var title: String
    var description: String
    var start: Date
    var end: Date
    var isAllDay: Bool = false
    var calendarIdentifier: String?
}

struct CalendarEventSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
    let calendarColorRed: Double
    let calendarColorGreen: Double
    let calendarColorBlue: Double

    var calendarColor: Color {
        Color(red: calendarColorRed, green: calendarColorGreen, blue: calendarColorBlue)
    }

    var durationMinutes: Int {
        max(Int(end.timeIntervalSince(start) / 60), 15)
    }

    var durationDays: Double {
        max(Double(durationMinutes) / (60 * 24), TaskItem.minDurationDays)
    }
}

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    private let store = EKEventStore()

    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private init() {
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    var isAuthorized: Bool {
        if #available(macOS 14.0, *) {
            return authorizationStatus == .fullAccess || authorizationStatus == .writeOnly
        }
        return authorizationStatus == .authorized
    }

    func requestAccess() async -> Bool {
        refreshAuthorizationStatus()
        if isAuthorized { return true }

        do {
            if #available(macOS 14.0, *) {
                let granted = try await store.requestFullAccessToEvents()
                refreshAuthorizationStatus()
                return granted
            } else {
                return await withCheckedContinuation { continuation in
                    store.requestAccess(to: .event) { granted, _ in
                        Task { @MainActor in
                            self.refreshAuthorizationStatus()
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
        } catch {
            refreshAuthorizationStatus()
            return false
        }
    }

    func fetchEvents(from start: Date, to end: Date) -> [CalendarEventSummary] {
        guard isAuthorized else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        return events.compactMap { event in
            guard let id = event.eventIdentifier else { return nil }
            let rgb = CalendarRGB.from(event.calendar)
            return CalendarEventSummary(
                id: id,
                title: event.title?.isEmpty == false ? event.title! : "Untitled event",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendarTitle: event.calendar.title,
                calendarColorRed: rgb.red,
                calendarColorGreen: rgb.green,
                calendarColorBlue: rgb.blue
            )
        }
    }

    func resolveEvent(identifier: String) -> CalendarEventSummary? {
        guard isAuthorized, let event = store.event(withIdentifier: identifier) else { return nil }
        let rgb = CalendarRGB.from(event.calendar)
        return CalendarEventSummary(
            id: identifier,
            title: event.title?.isEmpty == false ? event.title! : "Untitled event",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar.title,
            calendarColorRed: rgb.red,
            calendarColorGreen: rgb.green,
            calendarColorBlue: rgb.blue
        )
    }

    func openLinkedEvent(identifier: String?, around date: Date) {
        let target: Date
        if let identifier, isAuthorized, let event = store.event(withIdentifier: identifier) {
            target = event.startDate
        } else {
            target = date
        }
        focusCalendar(on: target)
    }

    func openInCalendar(at date: Date) {
        focusCalendar(on: date)
    }

    private func focusCalendar(on date: Date) {
        activateCalendarApp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.showDayInCalendarApp(date)
        }
    }

    private func activateCalendarApp() {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in }
    }

    private func showDayInCalendarApp(_ date: Date) {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }

        let script = """
        tell application "Calendar"
            activate
            try
                tell calendar window 1
                    switch view to day view
                    set targetDate to current date
                    set year of targetDate to \(year)
                    set month of targetDate to \(month)
                    set day of targetDate to \(day)
                    set current date to targetDate
                end tell
            end try
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error != nil {
                NSLog("todo: Calendar day script failed — opened app only")
            }
        }
    }

    func writableCalendars() -> [CalendarPickerCalendar] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { cal in
                let rgb = CalendarRGB.from(cal)
                return CalendarPickerCalendar(
                    id: cal.calendarIdentifier,
                    title: cal.title,
                    color: Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
                )
            }
    }

    func defaultWritableCalendarIdentifier() -> String? {
        guard isAuthorized else { return nil }
        if let defaultCal = store.defaultCalendarForNewEvents,
           defaultCal.allowsContentModifications {
            return defaultCal.calendarIdentifier
        }
        return writableCalendars().first?.id
    }

    func createEvent(_ request: CalendarCreateEventRequest) throws -> CalendarEventSummary {
        guard isAuthorized else { throw CalendarCreateEventError.notAuthorized }

        let event = EKEvent(eventStore: store)
        let trimmedTitle = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.title = trimmedTitle.isEmpty ? "Untitled" : trimmedTitle
        event.notes = CalendarEventNotes.formatted(description: request.description)
        event.url = nil
        event.startDate = request.start
        event.endDate = max(request.end, request.start.addingTimeInterval(15 * 60))
        event.isAllDay = request.isAllDay

        let calendar: EKCalendar?
        if let id = request.calendarIdentifier {
            calendar = store.calendar(withIdentifier: id)
        } else {
            calendar = nil
        }

        if let calendar, calendar.allowsContentModifications {
            event.calendar = calendar
        } else if let defaultCal = store.defaultCalendarForNewEvents,
                  defaultCal.allowsContentModifications {
            event.calendar = defaultCal
        } else if let first = store.calendars(for: .event).first(where: \.allowsContentModifications) {
            event.calendar = first
        } else {
            throw CalendarCreateEventError.noWritableCalendar
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw CalendarCreateEventError.saveFailed(error.localizedDescription)
        }

        if let saved = event.eventIdentifier.flatMap({ store.event(withIdentifier: $0) }),
           saved.url != nil {
            saved.url = nil
            try? store.save(saved, span: .thisEvent, commit: true)
        }

        guard let id = event.eventIdentifier,
              let summary = resolveEvent(identifier: id) else {
            throw CalendarCreateEventError.missingEventIdentifier
        }
        return summary
    }

    static func defaultEventWindow(
        suggestedStart: Date?,
        suggestedEnd: Date?,
        durationDays: Double = 1
    ) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()

        let start: Date = {
            if let suggestedStart { return suggestedStart }
            if let hour = cal.dateInterval(of: .hour, for: now)?.end {
                return hour
            }
            return now
        }()

        let end: Date = {
            if let suggestedEnd, suggestedEnd > start { return suggestedEnd }
            let hours = max(durationDays * 24, 1)
            if hours <= 24 {
                return start.addingTimeInterval(max(hours, 1) * 3600)
            }
            return cal.date(byAdding: .day, value: Int(ceil(hours / 24)), to: start)
                ?? start.addingTimeInterval(3600)
        }()

        return (start, end)
    }
}

import SwiftUI

struct CalendarLinkEditor: View {
    @Binding var eventID: String?
    @Binding var eventTitle: String?
    @Binding var eventStart: Date?
    @Binding var eventEnd: Date?
    @Binding var lastSyncedAt: Date?

    var calendarColor: Color?
    var calendarTitle: String?
    var scheduleConflict: ScheduleConflict?
    var taskTitle: String = ""
    var taskNotes: String = ""
    var suggestedStart: Date?
    var suggestedEnd: Date?
    var durationDays: Double = 1
    var onLink: (CalendarEventSummary) -> Void

    @State private var showPicker = false
    @State private var showCreate = false
    @ObservedObject private var sync = CalendarSyncService.shared
    @ObservedObject private var calendar = CalendarService.shared

    @Environment(\.appAccent) private var appAccent

    private var isLinked: Bool { eventID != nil }
    private var eventAccent: Color {
        calendarColor ?? appAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let conflict = scheduleConflict {
                conflictBanner(conflict)
                    .padding(.bottom, 10)
            }

            if isLinked, let title = eventTitle, let start = eventStart, let end = eventEnd {
                linkedRow(title: title, start: start, end: end)
            } else {
                emptyRow
            }

            Divider().padding(.vertical, 10)

            HStack(spacing: 10) {
                Button {
                    showCreate = true
                } label: {
                    Label(isLinked ? "New Event" : "Create Event", systemImage: "calendar.badge.plus")
                }
                .controlSize(.regular)

                Button {
                    showPicker = true
                } label: {
                    Label(isLinked ? "Link Other" : "Link Event", systemImage: "link")
                }
                .controlSize(.regular)

                if isLinked {
                    Button("Open Calendar") {
                        calendar.openLinkedEvent(identifier: eventID, around: eventStart ?? .now)
                    }
                    .controlSize(.regular)

                    Button("Unlink", role: .destructive) {
                        unlink()
                    }
                    .controlSize(.regular)
                }

                Spacer(minLength: 0)

                syncStatus
            }
        }
        .padding(12)
        .background(Theme.softAccentFill(eventAccent))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isLinked ? eventAccent.opacity(0.45) : Theme.border, lineWidth: isLinked ? 1.25 : 0.5)
        )
        .sheet(isPresented: $showPicker) {
            CalendarEventPickerSheet(anchorDate: eventStart ?? .now) { summary in
                link(summary)
                showPicker = false
            } onDismiss: {
                showPicker = false
            }
        }
        .sheet(isPresented: $showCreate) {
            CalendarEventComposerSheet(
                taskTitle: taskTitle,
                taskNotes: taskNotes,
                anchorDay: suggestedStart ?? eventStart ?? .now,
                suggestedStart: suggestedStart ?? eventStart,
                suggestedEnd: suggestedEnd ?? eventEnd,
                durationDays: durationDays,
                onConfirm: { summary in
                    link(summary)
                    showCreate = false
                },
                onDismiss: {
                    showCreate = false
                }
            )
        }
        .task {
            await calendar.requestAccess()
            refreshFromStore()
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 22))
                .foregroundStyle(Theme.muted)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("No event linked")
                    .font(Theme.sans(13, weight: .medium))
                Text("Link time you’ve blocked in Calendar. This stays separate from your due date.")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func linkedRow(title: String, start: Date, end: Date) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(eventAccent)
                .frame(width: 4)
                .padding(.vertical, 2)

            Image(systemName: "calendar.circle.fill")
                .font(.system(size: 28))
                .symbolRenderingMode(.palette)
                .foregroundStyle(eventAccent, eventAccent.opacity(0.35))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.sans(14, weight: .semibold))
                    .lineLimit(2)

                Text(CalendarEventFormatting.rangeLabel(start: start, end: end, isAllDay: false))
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.secondary)

                HStack(spacing: 6) {
                    if let calendarTitle {
                        Text(calendarTitle)
                            .font(Theme.sans(10, weight: .medium))
                            .foregroundStyle(eventAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(eventAccent.opacity(0.14))
                            .clipShape(Capsule())
                    }
                    Text("Work time · updates from Calendar")
                        .font(Theme.sans(10))
                        .foregroundStyle(Theme.faint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func conflictBanner(_ conflict: ScheduleConflict) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(conflict.title)
                    .font(Theme.sans(12, weight: .semibold))
                Text(conflict.message)
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var syncStatus: some View {
        if sync.isSyncing {
            ProgressView()
                .controlSize(.small)
        } else if let synced = lastSyncedAt ?? sync.lastSyncAt {
            Text(relativeSync(synced))
                .font(Theme.sans(10))
                .foregroundStyle(Theme.faint)
        }
    }

    private func relativeSync(_ date: Date) -> String {
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return "Synced \(rel.localizedString(for: date, relativeTo: .now))"
    }

    private func link(_ summary: CalendarEventSummary) {
        eventID = summary.id
        eventTitle = summary.title
        eventStart = summary.start
        eventEnd = summary.end
        lastSyncedAt = .now
        onLink(summary)
    }

    private func unlink() {
        eventID = nil
        eventTitle = nil
        eventStart = nil
        eventEnd = nil
        lastSyncedAt = nil
    }

    private func refreshFromStore() {
        guard let id = eventID else { return }
        guard let fresh = calendar.resolveEvent(identifier: id) else { return }
        eventTitle = fresh.title
        eventStart = fresh.start
        eventEnd = fresh.end
        lastSyncedAt = .now
    }
}

enum CalendarScheduleApplier {
    static func applyDurationOnly(_ summary: CalendarEventSummary, durationDays: inout Double) {
        durationDays = DurationFormatting.clamp(summary.durationDays)
    }
}

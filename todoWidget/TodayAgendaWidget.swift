import SwiftUI
import WidgetKit

struct TodayAgendaEntry: TimelineEntry {
    let date: Date
    let agenda: TodayAgendaWidgetData
}

struct TodayAgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayAgendaEntry {
        TodayAgendaEntry(
            date: .now,
            agenda: TodayAgendaWidgetData(
                blocked: [
                    WidgetAgendaItem(
                        id: UUID(),
                        title: "Deep work",
                        category: "#school",
                        timeLabel: "9:00 AM–11:00 AM",
                        section: .blocked,
                        sortKey: .now
                    ),
                ],
                dueToday: [
                    WidgetAgendaItem(
                        id: UUID(),
                        title: "Submit draft",
                        category: nil,
                        timeLabel: "Due 5:00 PM",
                        section: .due,
                        sortKey: .now
                    ),
                ],
                blockedCount: 1,
                dueTodayCount: 1
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayAgendaEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayAgendaEntry>) -> Void) {
        let entry = makeEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> TodayAgendaEntry {
        TodayAgendaEntry(date: .now, agenda: WidgetDataLoader.loadTodayAgenda())
    }
}

struct TodayAgendaWidget: Widget {
    let kind = "TodayAgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayAgendaProvider()) { entry in
            TodayAgendaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today schedule")
        .description("What you’ve blocked for today and when, plus due tasks.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        if #available(macOS 15.0, iOS 15.0, *) {
            return [.systemLarge, .systemExtraLarge]
        }
        return [.systemLarge]
    }
}

struct TodayAgendaWidgetView: View {
    let entry: TodayAgendaEntry
    @Environment(\.widgetFamily) private var family

    private var agenda: TodayAgendaWidgetData { entry.agenda }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)

            if agenda.isEmpty {
                emptyState
            } else {
                agendaContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(family == .systemExtraLarge ? 18 : 14)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.system(size: 20, weight: .bold))
                Text(subtitleDate)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if agenda.blockedCount > 0 {
                    Text("\(agenda.blockedCount) blocked")
                        .font(.system(size: 11, weight: .semibold))
                }
                if agenda.dueTodayCount > 0 {
                    Text("\(agenda.dueTodayCount) due")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitleDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: entry.date)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("All clear")
                .font(.system(size: 16, weight: .semibold))
            Text("Nothing blocked or due today.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private var agendaContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !agenda.blocked.isEmpty {
                agendaSection(
                    title: "Blocked",
                    icon: "calendar.day.timeline.left",
                    items: agenda.blocked,
                    moreCount: max(0, agenda.blockedCount - agenda.blocked.count),
                    emphasizeTime: true
                )
            }

            if !agenda.dueToday.isEmpty {
                agendaSection(
                    title: "Due today",
                    icon: "clock",
                    items: agenda.dueToday,
                    moreCount: max(0, agenda.dueTodayCount - agenda.dueToday.count),
                    emphasizeTime: false
                )
            }

            Spacer(minLength: 0)
        }
    }

    private func agendaSection(
        title: String,
        icon: String,
        items: [WidgetAgendaItem],
        moreCount: Int,
        emphasizeTime: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    agendaRow(item, emphasizeTime: emphasizeTime)
                    if index < items.count - 1 {
                        Divider().opacity(0.35).padding(.leading, 72)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if moreCount > 0 {
                Text("+\(moreCount) more in todo")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
        }
    }

    private func agendaRow(_ item: WidgetAgendaItem, emphasizeTime: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(item.timeLabel)
                .font(.system(size: emphasizeTime ? 11 : 10, weight: emphasizeTime ? .semibold : .medium, design: .rounded))
                .foregroundStyle(emphasizeTime ? .primary : .secondary)
                .frame(width: 68, alignment: .leading)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(family == .systemExtraLarge ? 2 : 1)

                if let cat = item.category {
                    Text(cat)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

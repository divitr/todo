import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTaskSummary]
    let totalCount: Int
}

struct TodayTasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(
            date: .now,
            tasks: [
                WidgetTaskSummary(id: UUID(), title: "Example task", category: "#school", detail: "Today"),
            ],
            totalCount: 1
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = makeEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> TodayEntry {
        let data = WidgetDataLoader.loadToday()
        return TodayEntry(date: .now, tasks: data.tasks, totalCount: data.totalOpen)
    }
}

struct TodayTasksWidget: Widget {
    let kind = "TodayTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayTasksProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Tasks due today from todo.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallBody
        case .systemMedium:
            mediumBody
        default:
            largeBody
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today", systemImage: "calendar")
                .font(.headline)
            Text("\(entry.totalCount)")
                .font(.system(size: 36, weight: .semibold, design: .rounded))
            Text(entry.totalCount == 1 ? "task" : "tasks")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Today", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Text("\(entry.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if entry.tasks.isEmpty {
                Text("Nothing due today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.tasks.prefix(3)) { task in
                    taskRow(task)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Today", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Text("\(entry.totalCount) open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if entry.tasks.isEmpty {
                ContentUnavailableView("All clear", systemImage: "checkmark.circle")
            } else {
                ForEach(entry.tasks.prefix(6)) { task in
                    taskRow(task)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func taskRow(_ task: WidgetTaskSummary) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .lineLimit(1)
                if let cat = task.category {
                    Text(cat)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct InboxEntry: TimelineEntry {
    let date: Date
    let count: Int
}

struct InboxProvider: TimelineProvider {
    func placeholder(in context: Context) -> InboxEntry {
        InboxEntry(date: .now, count: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (InboxEntry) -> Void) {
        completion(InboxEntry(date: .now, count: WidgetDataLoader.loadInboxCount()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InboxEntry>) -> Void) {
        let entry = InboxEntry(date: .now, count: WidgetDataLoader.loadInboxCount())
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct InboxCountWidget: Widget {
    let kind = "InboxCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: InboxProvider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Label("Open", systemImage: "tray.full")
                    .font(.headline)
                Text("\(entry.count)")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text("no date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Open tasks")
        .description("Count of all open tasks.")
        .supportedFamilies([.systemSmall])
    }
}

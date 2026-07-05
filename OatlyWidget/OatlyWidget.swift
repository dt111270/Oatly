import WidgetKit
import SwiftUI

struct TaskEntry: TimelineEntry {
    let date: Date
    let tasks: [OTTaskJSON]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: Date(), tasks: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(TaskEntry(date: Date(), tasks: loadTasks()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let tasks = loadTasks()
        let entry = TaskEntry(date: Date(), tasks: tasks)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadTasks() -> [OTTaskJSON] {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.davidturnbull.oatly"
        ) else { return [] }

        let fileURL = groupURL.appendingPathComponent("tasks.json")

        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(OTTasksPayload.self, from: data)
        else { return [] }

        // Simplified 5 July 2026 (David): widget now mirrors the phone's
        // Today filter — due today or overdue, excluding done/dropped —
        // rather than everything marked "hot". No calendar section; this is
        // just the task-list half of what the phone's Today tab shows.
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        return payload.tasks
            .filter { ($0.due ?? "9999") <= today && !["done", "dropped"].contains($0.status) }
            .sorted {
                let d0 = $0.due ?? "9999", d1 = $1.due ?? "9999"
                return d0 == d1 ? $0.name < $1.name : d0 < d1
            }
    }
}

struct OatlyWidgetEntryView: View {
    var entry: TaskEntry
    private let brandBlue = Color(red: 48/255, green: 95/255, blue: 188/255)

    var sections: [(role: String, tasks: [OTTaskJSON])] {
        let roles = Array(Set(entry.tasks.map { $0.role })).sorted()
        return roles.compactMap { role in
            let roleTasks = entry.tasks.filter { $0.role == role }
            return roleTasks.isEmpty ? nil : (role: role, tasks: roleTasks)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("📅 Today")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(brandBlue)
                Spacer()
                Text("\(entry.tasks.count)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            Divider()
            if entry.tasks.isEmpty {
                Spacer()
                Text("Nothing due today")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ForEach(sections, id: \.role) { section in
                    Text(section.role)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(brandBlue)
                        .padding(.top, 2)
                    ForEach(section.tasks.prefix(4), id: \.name) { task in
                        HStack {
                            taskTitle(task)
                                .font(.system(size: 14))
                                .lineLimit(1)
                            Spacer()
                            if let due = task.due {
                                Text(due)
                                    .font(.system(size: 13))
                                    .foregroundColor(dueColour(due))
                            }
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(12)
    }

    /// Task name, prefixed with an alarm clock when `nag_time` is set —
    /// same visual cue as the phone app's `TaskRowView`.
    private func taskTitle(_ task: OTTaskJSON) -> Text {
        if let nagTime = task.nagTime, !nagTime.isEmpty {
            return Text("⏰ \(task.name)")
        }
        return Text(task.name)
    }

    private func dueColour(_ due: String) -> Color {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        if due < today { return .red }
        if due == today { return .orange }
        return .secondary
    }
}

@main
struct OatlyWidget: Widget {
    let kind: String = "OatlyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            OatlyWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Oatly Today")
        .description("Tasks due today or overdue, at a glance.")
        .supportedFamilies([.systemLarge])
    }
}

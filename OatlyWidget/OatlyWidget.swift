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

        return payload.tasks
            .filter { $0.status == "hot" }
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
                Text("🔥 Hot")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(brandBlue)
                Spacer()
                Text("\(entry.tasks.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            Divider()
            if entry.tasks.isEmpty {
                Spacer()
                Text("No hot tasks")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ForEach(sections, id: \.role) { section in
                    Text(section.role)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(brandBlue)
                        .padding(.top, 2)
                    ForEach(section.tasks.prefix(4), id: \.name) { task in
                        HStack {
                            Text(task.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer()
                            if let due = task.due {
                                Text(due)
                                    .font(.system(size: 11))
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
        .configurationDisplayName("Oatly Hot Tasks")
        .description("Your hot tasks at a glance.")
        .supportedFamilies([.systemLarge])
    }
}

import SwiftUI

struct TaskSection {
    let header: String
    let tasks: [OTTask]
}

private let brandBlue = Color(red: 48/255, green: 95/255, blue: 188/255)

struct SectionHeaderView: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer().frame(height: 10)
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(brandBlue)
            Rectangle()
                .frame(height: 1)
                .foregroundColor(brandBlue.opacity(0.3))
        }
        .textCase(nil)
    }
}

struct TaskListView: View {
    let tasks: [OTTask]
    let sidebarSelection: SidebarSelection?
    @Binding var selectedTask: OTTask?
    let refreshToken: UUID
    @EnvironmentObject var store: TaskStore

    var sections: [TaskSection] {
        guard let sel = sidebarSelection else { return [] }
        switch sel {
        case .smart:
            let roles = Array(Set(tasks.map { $0.role })).sorted()
            return roles.compactMap { role in
                let roleTasks = tasks
                    .filter { $0.role == role }
                    .sorted {
                        let d0 = $0.due ?? "9999", d1 = $1.due ?? "9999"
                        return d0 == d1 ? $0.name < $1.name : d0 < d1
                    }
                return roleTasks.isEmpty ? nil : TaskSection(header: role, tasks: roleTasks)
            }
        case .role:
            let statusOrder = ["hot", "warm", "cool", "done", "dropped"]
            let statusEmojis = ["hot": "🔥", "warm": "⛅", "cool": "❄️", "done": "✅", "dropped": "💧"]
            return statusOrder.compactMap { status in
                let statusTasks = tasks
                    .filter { $0.status == status }
                    .sorted {
                        let d0 = $0.due ?? "9999", d1 = $1.due ?? "9999"
                        return d0 == d1 ? $0.name < $1.name : d0 < d1
                    }
                guard !statusTasks.isEmpty else { return nil }
                let emoji = statusEmojis[status] ?? ""
                return TaskSection(header: "\(emoji) \(status.capitalized)", tasks: statusTasks)
            }
        case .recurring:
            // .recurring is handled by RecurringListView, never reaches here.
            return []
        }
    }

    var body: some View {
        List(selection: $selectedTask) {
            ForEach(sections, id: \.header) { section in
                Section {
                    ForEach(section.tasks) { task in
                        TaskRowView(task: task, today: store.todayString)
                            .tag(task)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    SectionHeaderView(title: section.header)
                }
            }
        }
        .id(refreshToken)
        .listStyle(.plain)
        .onChange(of: sidebarSelection) { _, _ in selectedTask = nil }
    }
}

struct TaskRowView: View {
    let task: OTTask
    /// Today's date in `YYYY-MM-DD`, Europe/London. Passed in (rather than
    /// computed inside `body`) so the row's `Equatable` diff considers
    /// `(task, today)` — making the row re-render at the day boundary
    /// even when the task itself is unchanged.
    let today: String

    var body: some View {
        HStack {
            Text(task.name)
                .font(.system(size: 14))
            Spacer()
            if let due = task.due {
                Text(due)
                    .font(.caption)
                    .foregroundColor(dueColour(due))
            }
        }
        .frame(minHeight: 17)
    }

    private func dueColour(_ due: String) -> Color {
        if due < today { return .red }
        if due == today { return .orange }
        return .secondary
    }
}

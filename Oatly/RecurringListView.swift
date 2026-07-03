//
//  RecurringListView.swift
//  Oatly
//
//  Middle pane for the Recurring sidebar selection. Lists the recurring
//  tasks from `03.02 repeating tasks/`, sorted by next computed due date.
//  Toolbar `+` button opens the Add Recurring Task modal.
//

import SwiftUI

private let brandBlue = Color(red: 48/255, green: 95/255, blue: 188/255)

struct RecurringSection: Identifiable {
    let role: String
    let tasks: [OTRecurringTask]
    var id: String { role }
}

struct RecurringListView: View {
    @ObservedObject var store: TaskStore
    @Binding var selectedTask: OTRecurringTask?
    @State private var showingAdd = false

    var sections: [RecurringSection] {
        // Group by role, then sort within group by next due date.
        let grouped = Dictionary(grouping: store.recurringTasks) { task in
            task.role.isEmpty ? "—" : task.role
        }
        return grouped.keys.sorted().map { role in
            let sorted = (grouped[role] ?? []).sorted { a, b in
                (a.nextDue ?? .distantFuture) < (b.nextDue ?? .distantFuture)
            }
            return RecurringSection(role: role, tasks: sorted)
        }
    }

    var body: some View {
        List(selection: $selectedTask) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.tasks) { task in
                        RecurringRowView(task: task)
                            .tag(task)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    SectionHeaderView(title: section.role)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Recurring")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add recurring task")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddRecurringTaskView(store: store) { newTask in
                // After save, reload and select the new task if it was created.
                store.loadRecurring()
                if let new = store.recurringTasks.first(where: { $0.name == newTask }) {
                    selectedTask = new
                }
            }
        }
    }
}

struct RecurringRowView: View {
    let task: OTRecurringTask

    var body: some View {
        HStack(spacing: 8) {
            Text(task.name)
                .font(.system(size: 14))
                .lineLimit(1)
            if task.status == "paused" {
                Text("paused")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            Spacer()
            Text(task.nextDueString)
                .font(.caption)
                .foregroundColor(dueColour(task.nextDueString))
        }
        .frame(minHeight: 17)
    }

    private func dueColour(_ due: String) -> Color {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        if due == "—" { return .secondary }
        if due < today { return .red }
        if due == today { return .orange }
        return .secondary
    }
}

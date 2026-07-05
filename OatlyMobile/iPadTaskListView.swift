//
//  iPadTaskListView.swift
//  OatlyMobile (iPad)
//
//  Middle pane of the iPad three-pane layout. Behaviour:
//    Smart filter selection → group by role, sorted by due date then name.
//    Role selection        → group by status (Hot → Warm → Cool → Log),
//                            sorted by due date then name within status.
//
//  Tapping a row sets the detail-pane selection. Tapping the checkbox
//  marks the task done via the existing iOSTaskStore.markDone (Advanced URI).
//

import SwiftUI

struct iPadTaskSection: Identifiable {
    let title: String
    let tasks: [OTTaskJSON]
    var id: String { title }
}

struct iPadTaskListView: View {
    @ObservedObject var store: iOSTaskStore
    @Binding var selection: iPadSidebarSelection?
    @Binding var selectedTask: OTTaskJSON?

    var body: some View {
        Group {
            if sections.isEmpty {
                ContentUnavailableView("No tasks", systemImage: "checkmark.circle")
            } else {
                List(selection: $selectedTask) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.tasks, id: \.name) { task in
                                TaskRowView(
                                    task: task,
                                    isChecked: store.checkedNames.contains(task.name),
                                    onCheck: { store.markDone(task) },
                                    showDivider: false  // List already draws its own row separator
                                )
                                .tag(task)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                .listRowBackground(OTPalette.cardSurface)
                            }
                        } header: {
                            Text(section.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(OTPalette.accent)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(OTPalette.background)
                .environment(\.defaultMinListRowHeight, 0)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Menu {
                    ForEach(SmartFilter.allCases, id: \.self) { f in
                        Button(f.label) { selection = .filter(f) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(paneTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .refreshable { store.load() }
    }

    // MARK: - Title

    private var paneTitle: String {
        guard let selection = selection else { return "Tasks" }
        switch selection {
        case .filter(let f): return f.label
        case .role(let r):   return displayRole(r)
        }
    }

    // MARK: - Grouping

    private var sections: [iPadTaskSection] {
        guard let selection = selection else { return [] }
        switch selection {
        case .filter(let f):
            return groupByRole(filtered(by: f))
        case .role(let role):
            return groupByStatus(store.tasks.filter { $0.role == role })
        }
    }

    private func filtered(by f: SmartFilter) -> [OTTaskJSON] {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        switch f {
        case .today:   return store.tasks.filter { ($0.due ?? "9999") <= today && !["done", "dropped"].contains($0.status) }
        case .hot:     return store.tasks.filter { $0.status == "hot" }
        case .overdue: return store.tasks.filter { ($0.due ?? "9999") < today && !["done", "dropped"].contains($0.status) }
        case .warm:    return store.tasks.filter { $0.status == "warm" }
        case .cool:    return store.tasks.filter { $0.status == "cool" }
        case .log:     return store.tasks.filter { ["done", "dropped"].contains($0.status) }
        }
    }

    private func groupByRole(_ tasks: [OTTaskJSON]) -> [iPadTaskSection] {
        let roles = Array(Set(tasks.map { $0.role })).sorted { displayRole($0) < displayRole($1) }
        return roles.compactMap { role in
            let roleTasks = tasks
                .filter { $0.role == role }
                .sorted { sortByDueThenName($0, $1) }
            return roleTasks.isEmpty ? nil : iPadTaskSection(title: displayRole(role), tasks: roleTasks)
        }
    }

    private func groupByStatus(_ tasks: [OTTaskJSON]) -> [iPadTaskSection] {
        // Match Mac order: Hot, Warm, Cool, Done/Dropped (grouped as "Log").
        let order: [(label: String, predicate: (OTTaskJSON) -> Bool)] = [
            ("🔥 Hot",  { $0.status == "hot" }),
            ("⛅ Warm", { $0.status == "warm" }),
            ("❄️ Cool", { $0.status == "cool" }),
            ("✅ Log",  { ["done", "dropped"].contains($0.status) }),
        ]
        return order.compactMap { entry in
            let filtered = tasks
                .filter(entry.predicate)
                .sorted { sortByDueThenName($0, $1) }
            return filtered.isEmpty ? nil : iPadTaskSection(title: entry.label, tasks: filtered)
        }
    }

    private func sortByDueThenName(_ a: OTTaskJSON, _ b: OTTaskJSON) -> Bool {
        let d0 = a.due ?? "9999"
        let d1 = b.due ?? "9999"
        return d0 == d1 ? a.name < b.name : d0 < d1
    }

    private func displayRole(_ role: String) -> String {
        var r = role
        if r.hasPrefix("[[") { r.removeFirst(2) }
        if r.hasSuffix("]]") { r.removeLast(2) }
        return r
    }
}

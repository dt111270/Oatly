import SwiftUI

struct ContentView: View {
    @StateObject private var store = TaskStore()
    @State private var sidebarSelection: SidebarSelection? = .smart(.hot)
    @State private var selectedTask: OTTask?
    @State private var selectedRecurringTask: OTRecurringTask?
    @State private var listRefreshToken = UUID()

    var filteredTasks: [OTTask] {
        let today = store.todayString
        guard let sel = sidebarSelection else { return [] }
        switch sel {
        case .smart(let filter):
            switch filter {
            case .hot:     return store.tasks.filter { $0.status == "hot" }
            case .overdue: return store.tasks.filter { ($0.due ?? "9999") < today && !["done", "dropped"].contains($0.status) }
            case .warm:    return store.tasks.filter { $0.status == "warm" }
            case .cool:    return store.tasks.filter { $0.status == "cool" }
            case .log:     return store.tasks.filter { ["done", "dropped"].contains($0.status) }
            }
        case .role(let r):
            return store.tasks.filter { $0.role == r }
        case .recurring:
            return []
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 240)
        } content: {
            Group {
                if sidebarSelection == .recurring {
                    RecurringListView(store: store, selectedTask: $selectedRecurringTask)
                } else {
                    TaskListView(
                        tasks: filteredTasks,
                        sidebarSelection: sidebarSelection,
                        selectedTask: $selectedTask,
                        refreshToken: listRefreshToken
                    )
                    .environmentObject(store)
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 400)
        } detail: {
            if sidebarSelection == .recurring {
                RecurringDetailView(task: currentRecurringTask)
            } else {
                TaskDetailView(task: selectedTask, onStatusChange: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        store.load()
                        if let current = selectedTask {
                            selectedTask = store.tasks.first { $0.id == current.id }
                        }
                        listRefreshToken = UUID()
                    }
                })
                .environmentObject(store)
            }
        }
        .frame(minWidth: 900, minHeight: 500)
    }

    /// Re-resolve the selected recurring task from the freshly-polled store so
    /// edits made in Obsidian (typo fixes, frequency changes, etc.) flow
    /// through to the detail pane within one 3-second poll cycle. Falls back
    /// to the original snapshot if the file has been deleted or renamed.
    private var currentRecurringTask: OTRecurringTask? {
        guard let stale = selectedRecurringTask else { return nil }
        if let byId = store.recurringTasks.first(where: { $0.id == stale.id }) {
            return byId
        }
        if let byName = store.recurringTasks.first(where: { $0.name == stale.name }) {
            return byName
        }
        return stale
    }
}

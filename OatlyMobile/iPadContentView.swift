//
//  iPadContentView.swift
//  OatlyMobile (iPad)
//
//  Root view for iPad. Three-pane NavigationSplitView (sidebar | task list | detail).
//  In portrait, the system collapses to two columns + a toggle to reveal the sidebar,
//  which is the desired behaviour per design discussion (May 2026).
//

import SwiftUI

struct iPadContentView: View {
    @StateObject private var store: iOSTaskStore = iOSTaskStore()
    @State private var sidebarSelection: iPadSidebarSelection? = .filter(.today)
    @State private var selectedTask: OTTaskJSON?
    @State private var showingAddTask = false

    var body: some View {
        NavigationSplitView {
            iPadSidebarView(tasks: store.tasks, selection: $sidebarSelection)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingAddTask = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
        } content: {
            iPadTaskListView(
                store: store,
                selection: $sidebarSelection,
                selectedTask: $selectedTask
            )
            .id(sidebarSelection)
        } detail: {
            if let task = currentDetailTask {
                iPadTaskDetailView(task: task)
            } else {
                ContentUnavailableView("Select a task", systemImage: "checklist")
            }
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskView()
        }
        .onChange(of: sidebarSelection) { _, _ in
            // Clear detail selection when changing sidebar selection so we
            // don't show a stale task that's no longer in the list.
            selectedTask = nil
        }
    }

    /// Use the freshest copy of the task from `store.tasks` (matched by name)
    /// rather than the snapshot held in `selectedTask` — this way the detail
    /// pane re-renders with current status/body after each iCloud reload.
    private var currentDetailTask: OTTaskJSON? {
        guard let stale = selectedTask else { return nil }
        return store.tasks.first { $0.name == stale.name } ?? stale
    }
}

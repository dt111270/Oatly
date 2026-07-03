//
//  ContentView.swift
//  OatlyWatch Watch App
//
//  Scrollable list of hot tasks, grouped by role, received from the
//  paired iPhone via WatchConnectivity.
//

import SwiftUI

private let brandBlue = Color(red: 48/255, green: 95/255, blue: 188/255)

struct ContentView: View {
    @EnvironmentObject private var store: WatchTaskStore

    var body: some View {
        Group {
            if store.hotSections.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .navigationTitle("🔥 Hot")
    }

    private var taskList: some View {
        List {
            ForEach(store.hotSections) { section in
                Section {
                    ForEach(section.tasks, id: \.name) { task in
                        WatchTaskRow(task: task)
                    }
                } header: {
                    Text(section.role)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(brandBlue)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.carousel)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No hot tasks")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            if store.lastUpdated == nil {
                Text("Open Oatly on iPhone")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

struct WatchTaskRow: View {
    let task: OTTaskJSON

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.name)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .lineLimit(2)
            if let due = task.due {
                Text(due)
                    .font(.system(size: 11))
                    .foregroundColor(dueColour(due))
            }
        }
        .padding(.vertical, 2)
    }

    private func dueColour(_ due: String) -> Color {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        if due < today { return .red }
        if due == today { return .orange }
        return .secondary
    }
}

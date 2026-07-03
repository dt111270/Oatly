//
//  iPadSidebarView.swift
//  OatlyMobile (iPad)
//
//  Sidebar pane of the iPad three-pane layout. Lists smart filters
//  (Hot / Overdue / Warm / Cool / Log) and the set of roles drawn
//  from active tasks. Each row shows a count badge.
//

import SwiftUI

private let brandBlue = Color(red: 48/255, green: 95/255, blue: 188/255)

struct iPadSidebarView: View {
    let tasks: [OTTaskJSON]
    @Binding var selection: iPadSidebarSelection?

    var body: some View {
        List(selection: $selection) {
            Section("Smart Filters") {
                ForEach(SmartFilter.allCases, id: \.self) { f in
                    HStack {
                        Text(f.label)
                        Spacer()
                        if smartFilterCount(f) > 0 {
                            Text("\(smartFilterCount(f))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .tag(iPadSidebarSelection.filter(f))
                }
            }

            Section("Roles") {
                ForEach(roles, id: \.self) { role in
                    HStack {
                        Text(displayRole(role))
                        Spacer()
                        let count = roleActiveCount(role)
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .tag(iPadSidebarSelection.role(role))
                }
            }
        }
        .navigationTitle("Oatly")
    }

    // MARK: - Derived data

    /// Distinct list of roles drawn from active (non-done/dropped) tasks, A→Z.
    private var roles: [String] {
        let active = tasks.filter { !["done", "dropped"].contains($0.status) }
        let set = Set(active.map { $0.role })
        return set.sorted { displayRole($0) < displayRole($1) }
    }

    /// Tasks live with role as a wikilink like "[[Role Name]]". Strip
    /// the brackets for display, but keep the raw form as the selection
    /// value so equality with filter logic stays exact.
    private func displayRole(_ role: String) -> String {
        var r = role
        if r.hasPrefix("[[") { r.removeFirst(2) }
        if r.hasSuffix("]]") { r.removeLast(2) }
        return r
    }

    private func smartFilterCount(_ f: SmartFilter) -> Int {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        switch f {
        case .hot:     return tasks.filter { $0.status == "hot" }.count
        case .overdue: return tasks.filter { ($0.due ?? "9999") < today && !["done", "dropped"].contains($0.status) }.count
        case .warm:    return tasks.filter { $0.status == "warm" }.count
        case .cool:    return tasks.filter { $0.status == "cool" }.count
        case .log:     return tasks.filter { ["done", "dropped"].contains($0.status) }.count
        }
    }

    private func roleActiveCount(_ role: String) -> Int {
        tasks.filter { $0.role == role && !["done", "dropped"].contains($0.status) }.count
    }
}

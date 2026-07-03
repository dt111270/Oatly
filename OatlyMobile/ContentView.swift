import SwiftUI

private let brandBlue = Color(red: 48/255, green: 95/255, blue: 188/255)

struct iOSTaskSection {
    let role: String
    let tasks: [OTTaskJSON]
}

struct ContentView: View {
    @StateObject private var store: iOSTaskStore = iOSTaskStore()
    @StateObject private var calendarStore: CalendarStore = CalendarStore()
    @State private var filter: SmartFilter = .hot
    @State private var showingAddTask = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $filter) {
            ForEach(SmartFilter.allCases, id: \.self) { f in
                NavigationStack {
                    filterView(for: f)
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Menu {
                                    ForEach(SmartFilter.allCases, id: \.self) { f in
                                        Button(f.label) { filter = f }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(filter.label)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button {
                                    showingAddTask = true
                                } label: {
                                    Image(systemName: "plus")
                                }
                            }
                        }
                }
                .tag(f)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .sheet(isPresented: $showingAddTask) {
            AddTaskView()
        }
        .task {
            await calendarStore.requestAccessAndLoad()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                calendarStore.load()
            }
        }
    }

    func filteredSections(for f: SmartFilter) -> [iOSTaskSection] {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let filtered: [OTTaskJSON]
        switch f {
        case .hot:     filtered = store.tasks.filter { $0.status == "hot" }
        case .overdue: filtered = store.tasks.filter { ($0.due ?? "9999") < today && !["done", "dropped"].contains($0.status) }
        case .warm:    filtered = store.tasks.filter { $0.status == "warm" }
        case .cool:    filtered = store.tasks.filter { $0.status == "cool" }
        case .log:     filtered = store.tasks.filter { ["done", "dropped"].contains($0.status) }
        }
        let roles = Array(Set(filtered.map { $0.role })).sorted()
        return roles.compactMap { role in
            let roleTasks = filtered
                .filter { $0.role == role }
                .sorted {
                    let d0 = $0.due ?? "9999", d1 = $1.due ?? "9999"
                    return d0 == d1 ? $0.name < $1.name : d0 < d1
                }
            return roleTasks.isEmpty ? nil : iOSTaskSection(role: role, tasks: roleTasks)
        }
    }

    @ViewBuilder
    func filterView(for f: SmartFilter) -> some View {
        let sections = filteredSections(for: f)
        let showCalendar = (f == .hot && !calendarStore.events.isEmpty)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                if showCalendar {
                    Section {
                        ForEach(calendarStore.events) { event in
                            CalendarEventRow(event: event)
                        }
                    } header: {
                        iOSSectionHeaderView(title: "Today")
                    }
                }
                ForEach(sections, id: \.role) { section in
                    Section {
                        ForEach(section.tasks, id: \.name) { task in
                            TaskRowView(
                                task: task,
                                isChecked: store.checkedNames.contains(task.name),
                                onCheck: { store.markDone(task) }
                            )
                        }
                    } header: {
                        iOSSectionHeaderView(title: section.role)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .refreshable {
            store.load()
            if f == .hot { calendarStore.load() }
        }
        .overlay {
            if sections.isEmpty && !showCalendar {
                ContentUnavailableView("No tasks", systemImage: "checkmark.circle")
            }
        }
    }
}

struct CalendarEventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 12) {
            Text(event.timeLabel)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(event.title)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 6)
        .opacity(event.isPast ? 0.4 : 1.0)
    }
}

struct iOSSectionHeaderView: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(brandBlue)
            Rectangle()
                .frame(height: 1)
                .foregroundColor(brandBlue.opacity(0.3))
        }
        .textCase(nil)
        .padding(.top, 6)
    }
}

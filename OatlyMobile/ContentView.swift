import SwiftUI

struct iOSTaskSection {
    let role: String
    let tasks: [OTTaskJSON]
}

/// One extra swipe page beyond the `SmartFilter` carousel — Routines isn't
/// a status filter over one-off tasks, it's the 03.02 recurring templates
/// themselves, so it deliberately isn't a `SmartFilter` case (that enum is
/// also switched over exhaustively on iPad, which Routines doesn't touch).
enum ContentPage: Hashable {
    case filter(SmartFilter)
    case routines
}

struct ContentView: View {
    @StateObject private var store: iOSTaskStore = iOSTaskStore()
    @StateObject private var calendarStore: CalendarStore = CalendarStore()
    @State private var page: ContentPage = .filter(.today)
    @State private var showingAddTask = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $page) {
            ForEach(SmartFilter.allCases, id: \.self) { f in
                NavigationStack {
                    filterView(for: f)
                        .toolbar { pageToolbar(current: .filter(f)) }
                        .toolbarBackground(OTPalette.background, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                }
                .tag(ContentPage.filter(f))
            }
            NavigationStack {
                RoutinesListView(store: store)
                    .toolbar { pageToolbar(current: .routines) }
                    .toolbarBackground(OTPalette.background, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }
            .tag(ContentPage.routines)
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

    @ToolbarContentBuilder
    private func pageToolbar(current: ContentPage) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Menu {
                ForEach(SmartFilter.allCases, id: \.self) { f in
                    Button(f.label) { page = .filter(f) }
                }
                Button("⏰ Routines") { page = .routines }
            } label: {
                HStack(spacing: 6) {
                    Text(pageTitle(for: current))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(OTPalette.textPrimary)
                    Text("▾")
                        .font(.system(size: 13))
                        .foregroundColor(OTPalette.textSecondary)
                }
            }
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showingAddTask = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(OTPalette.accent))
                    .shadow(color: OTPalette.accent.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
    }

    private func pageTitle(for page: ContentPage) -> String {
        switch page {
        case .filter(let f): return f.label
        case .routines:      return "⏰ Routines"
        }
    }

    func filteredSections(for f: SmartFilter) -> [iOSTaskSection] {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let filtered: [OTTaskJSON]
        switch f {
        case .today:   filtered = store.tasks.filter { ($0.due ?? "9999") <= today && !["done", "dropped"].contains($0.status) }
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
        let showCalendar = (f == .today && !calendarStore.events.isEmpty)
        ScrollView {
            // Plain VStack of cards, not a pinned-header Section list — each
            // card floats independently with its own shadow, so a header
            // pinned above it while the card scrolls underneath would look
            // broken. Headers live inside their card and scroll with it.
            VStack(alignment: .leading, spacing: 10) {
                if showCalendar {
                    OTCard {
                        iOSSectionHeaderView(title: "Today")
                        ForEach(Array(calendarStore.events.enumerated()), id: \.element.id) { index, event in
                            CalendarEventRow(
                                event: event,
                                showDivider: index < calendarStore.events.count - 1
                            )
                        }
                    }
                }
                ForEach(sections, id: \.role) { section in
                    OTCard {
                        iOSSectionHeaderView(title: section.role)
                        ForEach(Array(section.tasks.enumerated()), id: \.element.name) { index, task in
                            TaskRowView(
                                task: task,
                                isChecked: store.checkedNames.contains(task.name),
                                onCheck: { store.markDone(task) },
                                showDivider: index < section.tasks.count - 1
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(OTPalette.background)
        .refreshable {
            store.load()
            if f == .today { calendarStore.load() }
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
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(event.timeLabel)
                    .font(.system(size: 11.5))
                    .foregroundColor(OTPalette.textSecondary)
                    .frame(width: 48, alignment: .leading)
                    .lineLimit(1)
                Text(event.title)
                    .font(.system(size: 14))
                    .foregroundColor(OTPalette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6.5)
            .opacity(event.isPast ? 0.4 : 1.0)

            if showDivider {
                Rectangle()
                    .fill(OTPalette.divider)
                    .frame(height: 0.5)
            }
        }
    }
}

struct iOSSectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(OTPalette.accent)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

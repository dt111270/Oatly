import Foundation
import Combine

class TaskStore: ObservableObject {
    @Published var tasks: [OTTask] = []
    @Published var recurringTasks: [OTRecurringTask] = []
    @Published var lastMaintenanceRun: Date?
    @Published var iCloudSyncOverride: Bool = UserDefaults.standard.bool(forKey: "iCloudSyncOverride") {
        didSet { UserDefaults.standard.set(iCloudSyncOverride, forKey: "iCloudSyncOverride") }
    }

    /// Today's date in `YYYY-MM-DD`, Europe/London. Refreshed at the top of
    /// every `load()` call, so the 3s polling self-corrects within 3s of
    /// midnight without needing a separate daily timer. Publishes only when
    /// the day actually changes, so views downstream re-render exactly once
    /// per day boundary. Used by `TaskRowView` (date colour) and
    /// `ContentView.filteredTasks` (overdue smart filter).
    @Published var todayString: String = TaskStore.computeTodayString()

    var iCloudSyncEnabled: Bool {
        ProcessInfo.processInfo.hostName == "Leonai.local" || iCloudSyncOverride
    }

    let tasksFolder: URL
    let recurringFolder: URL
    let rolesFolder: URL
    private var timer: Timer?
    private var lastWrittenSnapshot: String = ""

    init() {
        let vault = URL(fileURLWithPath: "/Users/davidturnbull/Documents/DTObs")
        let working = vault
            .appendingPathComponent("00-09 DTOS")
            .appendingPathComponent("03 Working Folders")
        tasksFolder     = working.appendingPathComponent("03.01 tasks")
        recurringFolder = working.appendingPathComponent("03.02 repeating tasks")
        rolesFolder     = working.appendingPathComponent("03.09 roles")
        load()
        loadRecurring()
        startPolling()
        startMaintenance()
    }

    func load() {
        refreshTodayString()

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tasksFolder,
            includingPropertiesForKeys: nil
        ) else { return }

        let all = files
            .filter { $0.pathExtension == "md" }
            .compactMap { TaskParser.parse(fileURL: $0) }

        var seen: [String: OTTask] = [:]
        var deduped: [OTTask] = []

        for task in all {
            if task.source == "recurring-task" {
                let key = "\(task.name)|\(task.status)"
                if let existing = seen[key] {
                    if (task.due ?? "9999") < (existing.due ?? "9999") {
                        seen[key] = task
                    }
                } else {
                    seen[key] = task
                }
            } else {
                deduped.append(task)
            }
        }

        deduped.append(contentsOf: seen.values)

        let updated = deduped.sorted {
            let d0 = $0.due ?? "9999", d1 = $1.due ?? "9999"
            return d0 == d1 ? $0.name < $1.name : d0 < d1
        }

        tasks = updated
        writeToiCloud()
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.load()
            self?.loadRecurring()
        }
    }

    /// Load all recurring task notes from `03.02 repeating tasks/`.
    /// Sorted by computed next-due date (sooner first); tasks whose
    /// frequency can't be parsed sink to the bottom.
    func loadRecurring() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: recurringFolder,
            includingPropertiesForKeys: nil
        ) else { return }

        let all = files
            .filter { $0.pathExtension == "md" }
            .compactMap { TaskParser.parseRecurring(fileURL: $0) }

        recurringTasks = all.sorted { a, b in
            (a.nextDue ?? .distantFuture) < (b.nextDue ?? .distantFuture)
        }
    }

    /// Definitive list of role names, read from `03.09 roles/` (file stems).
    /// Used by the Add Recurring Task modal.
    func loadRoles() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: rolesFolder,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "md" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    private func writeToiCloud() {
        guard iCloudSyncEnabled else { return }
        // Recurring tasks factor into the change-detection snapshot too —
        // otherwise editing a routine's frequency/time (with the task list
        // itself unchanged) wouldn't trigger a re-write, and mobile would
        // sit on stale routine data until something else happened to touch
        // a one-off task.
        let recurringSnapshot = recurringTasks
            .map { "\($0.id)|\($0.status)|\($0.name)|\($0.frequency)|\($0.rootDate)|\($0.nagTime ?? "")" }
            .joined(separator: ",")
        let snapshot = tasks.map { "\($0.id)|\($0.status)|\($0.name)" }.joined(separator: ",") + "||" + recurringSnapshot
        guard snapshot != lastWrittenSnapshot else { return }
        lastWrittenSnapshot = snapshot

        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.com.davidturnbull.oatly"
        ) else { return }

        let docsURL = containerURL.appendingPathComponent("Documents")
        try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)

        let payload = OTTasksPayload(
            updated: ISO8601DateFormatter().string(from: Date()),
            tasks: tasks.map {
                OTTaskJSON(
                    name: $0.name,
                    status: $0.status,
                    role: $0.role,
                    due: $0.due,
                    nonNegotiable: $0.nonNnegotiable,
                    body: $0.body
                        .components(separatedBy: "\n")
                        .filter { !$0.contains("BUTTON[") }
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    source: $0.source,
                    filepath: $0.fileURL.path.replacingOccurrences(
                        of: "/Users/davidturnbull/Documents/DTObs/", with: ""
                    ),
                    nagTime: $0.nagTime,
                    url: $0.url
                )
            },
            recurringTasks: recurringTasks.map {
                OTRecurringTaskJSON(
                    name: $0.name,
                    role: $0.role,
                    frequency: $0.frequency,
                    status: $0.status,
                    rootDate: $0.rootDate,
                    nagTime: $0.nagTime,
                    url: $0.url,
                    filepath: $0.fileURL.path.replacingOccurrences(
                        of: "/Users/davidturnbull/Documents/DTObs/", with: ""
                    ),
                    nextDue: $0.nextDueString == "—" ? nil : $0.nextDueString
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: docsURL.appendingPathComponent("tasks.json"))
    }

    // MARK: - Today

    /// Single date formatter for `todayString`. Configured once; thread-safe
    /// for read after configuration.
    private static let londonDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/London")
        return f
    }()

    private static func computeTodayString() -> String {
        return londonDayFormatter.string(from: Date())
    }

    /// Refresh `todayString` from the wall clock. Only assigns when the
    /// value actually changes, so this is safe to call on every poll —
    /// at most one publish per day, exactly at the day boundary.
    private func refreshTodayString() {
        let new = TaskStore.computeTodayString()
        if new != todayString {
            todayString = new
        }
    }

    deinit {
        timer?.invalidate()
    }
}

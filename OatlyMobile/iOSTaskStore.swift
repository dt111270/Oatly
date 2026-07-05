import Foundation
import Combine
import UIKit
import WatchConnectivity
import UserNotifications

class iOSTaskStore: NSObject, ObservableObject {
    @Published var tasks: [OTTaskJSON] = []
    @Published var checkedNames: Set<String> = []
    /// All synced 03.02 recurring templates, not just the nag-eligible
    /// ones — "Routines" (RoutinesListView) filters to `nagTime`-set ones
    /// itself, same pattern as `tasks`/`SmartFilter` filtering locally
    /// rather than the store pre-filtering for one specific screen.
    @Published var routines: [OTRecurringTaskJSON] = []

    /// Raw JSON bytes of the most recent load — kept so we can push the
    /// same payload to the watch whenever the WC session becomes active
    /// or the user opens the iPhone app.
    private var lastPayloadData: Data?

    /// Keys (filepath, or name if no filepath) marked done locally more
    /// recently than the vault write-back has had time to round-trip back
    /// into `tasks.json`. Obsidian's write happens via a URL scheme, then
    /// Leonai has to notice the file change, rewrite iCloud, and only then
    /// does the phone's next `load()` see the real status — a few seconds
    /// at least. Without this, tapping Done on a nag notification could
    /// immediately trigger another `load()` (the app launching/foregrounding
    /// to handle the notification), which would still see the task as hot
    /// in the stale payload and re-book the very nag Done just cancelled.
    /// Entries are cleared once the synced payload confirms the status
    /// really has changed, or after `recentlyDoneTimeout` as a safety net.
    private var recentlyDoneKeys: [String: Date] = [:]
    private let recentlyDoneTimeout: TimeInterval = 120

    override init() {
        super.init()
        TaskNotificationScheduler.requestAuthorizationIfNeeded()
        NaggingNotificationScheduler.purgeLegacyIdentifiers()
        // One combined call — setNotificationCategories replaces the whole
        // registered set rather than merging, so every scheduler's
        // category has to be registered together here, never individually.
        UNUserNotificationCenter.current().setNotificationCategories([
            TaskNotificationScheduler.category,
            NaggingNotificationScheduler.category
        ])
        UNUserNotificationCenter.current().delegate = self
        activateWatchSession()
        load()
    }

    // MARK: - iCloud load

    func load() {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.com.davidturnbull.oatly"
        ) else { return }

        let fileURL = containerURL
            .appendingPathComponent("Documents")
            .appendingPathComponent("tasks.json")

        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(OTTasksPayload.self, from: data)
        else { return }

        // Write to App Group so the widget can read it without iCloud access
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.davidturnbull.oatly"
        ) {
            try? data.write(to: groupURL.appendingPathComponent("tasks.json"))
        }

        lastPayloadData = data
        pushToWatch(data)

        pruneRecentlyDoneKeys(against: payload.tasks)
        let excludeKeys = Set(recentlyDoneKeys.keys)

        TaskNotificationScheduler.sync(tasks: payload.tasks, excludingKeys: excludeKeys)
        NaggingNotificationScheduler.sync(tasks: payload.tasks, excludingKeys: excludeKeys)

        DispatchQueue.main.async {
            self.tasks = payload.tasks
            self.routines = payload.recurringTasks
            let taskNames = Set(payload.tasks.map { $0.name })
            self.checkedNames = self.checkedNames.intersection(taskNames)
        }
    }

    func markDone(_ task: OTTaskJSON) {
        checkedNames.insert(task.name)
        markRecentlyDone(key: task.filepath ?? task.name)
        guard let filepath = task.filepath else {
            print("No filepath for task: \(task.name)")
            return
        }
        markDoneByFilepath(filepath)
    }

    /// Same Obsidian write-back as `markDone(_:)`, usable from contexts —
    /// like a nag notification's Done action — that only have the
    /// filepath, not the full `OTTaskJSON`.
    ///
    /// `UNUserNotificationCenterDelegate` callbacks aren't guaranteed to
    /// run on the main thread, and `UIApplication.shared.open` silently
    /// no-ops off it — that was the bug behind tapping "Done" clearing the
    /// notification without actually writing `status: done` back to the
    /// vault. Dispatching explicitly to main fixes it regardless of which
    /// thread called this. `completion` fires once the open has actually
    /// gone through (or failed to), not just once it's been requested —
    /// see `NaggingNotificationScheduler.cancelNagging`'s doc comment for
    /// why callers handling a notification action should wait for it.
    private func markDoneByFilepath(_ filepath: String, completion: @escaping () -> Void = {}) {
        writeFrontmatterField(filepath: filepath, key: "status", value: "done", completion: completion)
    }

    /// Edit a Routine's name/frequency/nag_time from `RoutinesListView`.
    /// `fields` is an ordered list (not a dictionary) so writes happen
    /// strictly one after another rather than firing several
    /// `obsidian://` opens at once — Obsidian is a single foreground app
    /// switching between URL invocations, so firing multiple in parallel
    /// risks one getting dropped mid-switch. Only pass the fields that
    /// actually changed.
    func updateRoutine(filepath: String,
                        fields: [(key: String, value: String)],
                        completion: @escaping () -> Void = {}) {
        writeFieldsSequentially(filepath: filepath, fields: fields, completion: completion)
    }

    private func writeFieldsSequentially(filepath: String,
                                          fields: [(key: String, value: String)],
                                          completion: @escaping () -> Void) {
        guard let first = fields.first else {
            completion()
            return
        }
        let remaining = Array(fields.dropFirst())
        writeFrontmatterField(filepath: filepath, key: first.key, value: first.value) { [weak self] in
            self?.writeFieldsSequentially(filepath: filepath, fields: remaining, completion: completion)
        }
    }

    /// Single `obsidian://adv-uri` frontmatter write — one key/value pair
    /// per call, since adv-uri doesn't support setting multiple fields in
    /// one URL. Shared by `markDoneByFilepath` and `updateRoutine`.
    ///
    /// `UIApplication.shared.open` must run on the main thread (see
    /// `markDoneByFilepath`'s original doc comment — this was the bug
    /// behind Done silently not writing back from a background thread),
    /// and `completion` only fires once the open has actually gone
    /// through, not just once it's been requested.
    private func writeFrontmatterField(filepath: String,
                                        key: String,
                                        value: String,
                                        completion: @escaping () -> Void) {
        guard !filepath.isEmpty else {
            print("No filepath for frontmatter write (\(key))")
            completion()
            return
        }
        let encodedPath = filepath
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filepath
        let encodedValue = value
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        let urlString = "obsidian://adv-uri?vault=DTObs&filepath=\(encodedPath)&frontmatterkey=\(key)&data=\(encodedValue)"
        guard let url = URL(string: urlString) else {
            completion()
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { _ in
                completion()
            }
        }
    }

    /// Record that `key` was just marked done locally, so an imminent
    /// `load()` (e.g. the app launching to handle the very notification
    /// action that triggered this) doesn't re-book its nag off stale data
    /// while the vault write-back is still in flight. See the property's
    /// doc comment for the full race this closes.
    private func markRecentlyDone(key: String) {
        guard !key.isEmpty else { return }
        // May be called from the notification delegate, which isn't
        // guaranteed to run on the main thread — dispatch explicitly since
        // `recentlyDoneKeys` is otherwise only ever touched from `load()`
        // and `markDone(_:)`, both effectively main-thread callers.
        DispatchQueue.main.async {
            self.recentlyDoneKeys[key] = Date()
        }
    }

    /// Drop overrides once the fresh payload confirms the task really is
    /// no longer hot (the write-back caught up), or once they've been
    /// around longer than `recentlyDoneTimeout` regardless — a safety net
    /// so a failed write-back can't permanently silence a task's nag.
    private func pruneRecentlyDoneKeys(against freshTasks: [OTTaskJSON]) {
        guard !recentlyDoneKeys.isEmpty else { return }
        let now = Date()
        let stillHotByKey = Dictionary(uniqueKeysWithValues: freshTasks.map { ($0.filepath ?? $0.name, $0.status == "hot") })
        recentlyDoneKeys = recentlyDoneKeys.filter { key, markedAt in
            guard now.timeIntervalSince(markedAt) < recentlyDoneTimeout else { return false }
            return stillHotByKey[key] ?? false
        }
    }

    // MARK: - Watch push

    private func activateWatchSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func pushToWatch(_ data: Data) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        // Filter to hot tasks before sending — the watch only displays hot
        // tasks, and keeping the payload small keeps us comfortably under
        // WC's ~65 KB application context size limit.
        guard let full = try? JSONDecoder().decode(OTTasksPayload.self, from: data) else { return }
        // Recurring tasks/routines don't need to go to the watch — it only
        // ever displays hot one-off tasks, and keeping this payload small
        // matters for the WC size limit (see comment above).
        let hotOnly = OTTasksPayload(
            updated: full.updated,
            tasks: full.tasks.filter { $0.status == "hot" },
            recurringTasks: []
        )
        guard let hotData = try? JSONEncoder().encode(hotOnly) else { return }

        // updateApplicationContext coalesces — only the latest snapshot
        // is delivered to the watch, which is what we want for "current
        // task list". Safe to call on every load.
        do {
            try session.updateApplicationContext(["payload": hotData])
        } catch {
            print("WCSession updateApplicationContext failed: \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension iOSTaskStore: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error = error {
            print("WCSession activation error: \(error)")
            return
        }
        // If we already loaded tasks before the session activated, push now.
        if let data = lastPayloadData, activationState == .activated {
            pushToWatch(data)
        }
    }

    // Required stubs — iPhone may pair with a different watch during runtime.
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate to support pairing with a new watch.
        WCSession.default.activate()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension iOSTaskStore: UNUserNotificationCenterDelegate {
    /// Show nag/due alerts even while the app is in the foreground —
    /// otherwise iOS suppresses local notifications silently in that case.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// Handles the Done button on a plain 07:00 due reminder, and the
    /// Done / Snooze 1hr / Snooze 3hr actions on a nag notification. A
    /// plain tap with no action identifier falls through untouched.
    ///
    /// Deliberately does *not* call `completionHandler` until every bit of
    /// async work for the chosen action has actually finished. Cancelling
    /// or snoozing a nag takes a couple of round trips to the notification
    /// centre, and iOS can suspend the app shortly after the completion
    /// handler fires — calling it early (an earlier version used `defer`
    /// to fire it immediately) meant the app could be frozen mid-work,
    /// leaving later occurrences to fire anyway even though "Done" had
    /// been tapped.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse,
                                 withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        guard let key = NaggingNotificationScheduler.key(fromUserInfo: userInfo) else {
            completionHandler()
            return
        }

        switch response.notification.request.content.categoryIdentifier {
        case TaskNotificationScheduler.categoryIdentifier:
            switch response.actionIdentifier {
            case TaskNotificationScheduler.doneActionIdentifier:
                handleDone(key: key, userInfo: userInfo) {
                    TaskNotificationScheduler.cancelReminder(forKey: key, completion: $0)
                } completion: {
                    completionHandler()
                }
            default:
                completionHandler()
            }

        case NaggingNotificationScheduler.categoryIdentifier:
            switch response.actionIdentifier {
            case NaggingNotificationScheduler.doneActionIdentifier:
                handleDone(key: key, userInfo: userInfo) {
                    NaggingNotificationScheduler.cancelNagging(key: key, completion: $0)
                } completion: {
                    completionHandler()
                }

            case NaggingNotificationScheduler.snooze1hActionIdentifier:
                if let task = task(forKey: key) {
                    NaggingNotificationScheduler.snooze(task, duration: 60 * 60) { completionHandler() }
                } else {
                    completionHandler()
                }

            case NaggingNotificationScheduler.snooze3hActionIdentifier:
                if let task = task(forKey: key) {
                    NaggingNotificationScheduler.snooze(task, duration: 3 * 60 * 60) { completionHandler() }
                } else {
                    completionHandler()
                }

            default:
                // Default tap (no action button pressed) — leave the nag
                // running exactly as it was.
                completionHandler()
            }

        default:
            completionHandler()
        }
    }

    /// Shared "Done was tapped" handling for both notification types:
    /// record the local override, tick the in-app checkbox, cancel
    /// whatever notification(s) belong to this task, and write the
    /// Obsidian status change — waiting for both async pieces before
    /// calling back.
    private func handleDone(key: String,
                             userInfo: [AnyHashable: Any],
                             cancel: (@escaping () -> Void) -> Void,
                             completion: @escaping () -> Void) {
        markRecentlyDone(key: key)
        // The in-app checkbox tap (`markDone(_:)`) inserts into
        // `checkedNames` for an immediate tick in the UI; this
        // notification-driven path bypasses that function entirely, so
        // without this the task wouldn't visibly tick even once the
        // write-back succeeds.
        if let task = task(forKey: key) {
            DispatchQueue.main.async { self.checkedNames.insert(task.name) }
        }
        let group = DispatchGroup()
        group.enter()
        cancel { group.leave() }
        if let filepath = userInfo[NaggingNotificationScheduler.userInfoFilepathKey] as? String {
            group.enter()
            markDoneByFilepath(filepath) { group.leave() }
        }
        group.notify(queue: .main, execute: completion)
    }

    /// Look up a task by the same key used for its notification
    /// identifiers (filepath, falling back to name).
    private func task(forKey key: String) -> OTTaskJSON? {
        tasks.first { ($0.filepath ?? $0.name) == key }
    }
}

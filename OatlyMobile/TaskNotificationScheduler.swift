//
//  TaskNotificationScheduler.swift
//  OatlyMobile
//
//  Local reminder notifications for hot tasks that are due today or
//  overdue. Fires daily at 07:00 and keeps firing (a repeating trigger)
//  until the task drops out of that set — most commonly because it's been
//  marked done, but also covers dropped/un-hot edge cases.
//
//  Deliberately local, not push: no server, no APNs. That means this only
//  re-syncs against the current task list when `iOSTaskStore.load()` runs,
//  i.e. on app launch/foreground — same launch-only limitation already
//  noted for widget/watch freshness in Oatly Context.md's pending work.
//  A task that becomes due while the phone hasn't opened the app won't get
//  its first 07:00 ping scheduled until the app is next opened.
//
//  This is "use case 1" from the notifications discussion (2026-07-04) —
//  the simpler, standard-task reminder. The "nag every 5 minutes until
//  dismissed" Due-style reminder for recurring/one-off events is a
//  separate, more involved piece of plumbing, deferred for now.
//

import Foundation
import UserNotifications

enum TaskNotificationScheduler {

    private static let reminderHour = 7
    private static let reminderMinute = 0
    private static let identifierPrefix = "oatly.due."

    static let categoryIdentifier = "OATLY_DUE"
    static let doneActionIdentifier = "OATLY_DUE_DONE"

    /// Call once at launch (from `iOSTaskStore.init()`).
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }

    /// This scheduler's `UNNotificationCategory` — collected alongside
    /// `NaggingNotificationScheduler.category` and registered together in
    /// one `setNotificationCategories` call from `iOSTaskStore.init()`.
    /// That call *replaces* the entire registered set rather than merging,
    /// so each scheduler must never call it independently — only ever
    /// build its category and hand it off to be registered as a batch.
    ///
    /// `.foreground` on the action matters, not just cosmetically: without
    /// it, Done is handled purely in the background, and the `obsidian://`
    /// URL that actually writes `status: done` silently fails to hand off
    /// to Obsidian unless Oatly itself is foregrounded first (the exact
    /// bug this caused for the nagging notifications' Done button).
    static var category: UNNotificationCategory {
        let done = UNNotificationAction(
            identifier: doneActionIdentifier,
            title: "Done",
            options: [.authenticationRequired, .foreground]
        )
        return UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [done],
            intentIdentifiers: [],
            options: []
        )
    }

    /// Call after every successful `load()`. Diffs the qualifying task set
    /// (hot, due today or earlier, not a nagging task) against
    /// currently-scheduled notifications and adds/removes requests to match.
    /// Tasks with `nagTime` set are excluded — they get the every-5-minute
    /// treatment from `NaggingNotificationScheduler` instead, not this one.
    ///
    /// `excludingKeys` — see the equivalent parameter on
    /// `NaggingNotificationScheduler.sync` — guards against re-scheduling a
    /// reminder for a task marked done moments ago locally, whose done-ness
    /// the synced payload might not reflect yet.
    static func sync(tasks: [OTTaskJSON], excludingKeys: Set<String> = []) {
        let today = todayString()
        let qualifying = tasks.filter { task in
            guard let due = task.due, !due.isEmpty else { return false }
            guard task.nagTime == nil || task.nagTime!.isEmpty else { return false }
            guard !excludingKeys.contains(task.filepath ?? task.name) else { return false }
            return task.status == "hot" && due <= today
        }

        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let scheduledIDs = Set(
                pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
            )
            let qualifyingByID = Dictionary(
                uniqueKeysWithValues: qualifying.map { (identifier(for: $0), $0) }
            )

            let toRemove = scheduledIDs.subtracting(qualifyingByID.keys)
            if !toRemove.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: Array(toRemove))
            }

            let toAdd = qualifyingByID.filter { !scheduledIDs.contains($0.key) }
            for (_, task) in toAdd {
                schedule(task)
            }
        }
    }

    /// Cancel the daily reminder for one task immediately — used by the
    /// notification-action delegate when its Done button is tapped, so it
    /// doesn't have to wait for the next `sync()` to stop reappearing.
    /// Removes both the pending (repeating) request and anything already
    /// delivered/stacked in Notification Center — same two-store lesson
    /// learned the hard way with the nagging scheduler.
    static func cancelReminder(forKey key: String, completion: @escaping () -> Void = {}) {
        let id = identifierPrefix + key
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
        completion()
    }

    // MARK: - Private

    private static func identifier(for task: OTTaskJSON) -> String {
        identifierPrefix + (task.filepath ?? task.name)
    }

    private static func schedule(_ task: OTTaskJSON) {
        let content = UNMutableNotificationContent()
        content.title = task.name
        content.body = "Due — \(displayRole(task.role))"
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [
            NaggingNotificationScheduler.userInfoFilepathKey: task.filepath ?? "",
            NaggingNotificationScheduler.userInfoNameKey: task.name
        ]

        var components = DateComponents()
        components.hour = reminderHour
        components.minute = reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: identifier(for: task),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification for \(task.name): \(error)")
            }
        }
    }

    private static func displayRole(_ role: String) -> String {
        role.replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
    }

    /// `YYYY-MM-DD` in Europe/London, matching the Mac's `due:` format —
    /// string comparison is enough since ISO dates sort lexicographically.
    private static func todayString() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

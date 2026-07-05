//
//  NaggingNotificationScheduler.swift
//  OatlyMobile
//
//  "Use case 2" from the notifications discussion (2026-07-04) — the
//  Due-app-style nag: once a task's `due` date + `nagTime` time-of-day has
//  passed, fire an immediate local notification and then repeat every
//  5 minutes, forever, until the task is marked done.
//
//  Design note (revised 2026-07-04, after the first version turned out to
//  require the app to be open at the exact moment a task became due):
//  local notifications are scheduled and delivered entirely by iOS once
//  requested — the app doesn't need to be running when they fire, only
//  when they're *booked*. So instead of only scheduling a nag once it's
//  already overdue, `sync()` books ahead of time, the moment the phone
//  learns about a task:
//
//    - More than `activeWindow` before its nag moment: nothing gets
//      booked yet at all. A recurring nag can have many future
//      occurrences queued up (11 days' worth, matching Maintenance's
//      generation window) and reserving even one notification slot for
//      each would burn through iOS's 64-pending-notification-per-app cap
//      for no benefit — there's nothing to say yet.
//    - Inside `activeWindow` (or already overdue): book a full rolling
//      batch of `batchSize` individual one-shot notifications
//      `repeatInterval` apart, anchored to the *real* due moment
//      regardless of when this `sync()` happened to run, topped up on
//      every further `sync()`.
//
//  Revised again (2026-07-05), twice, after a real overnight miss:
//  `activeWindow` was originally only 30 minutes, on the assumption a
//  `sync()` would naturally land in that window shortly before a task
//  became due. That doesn't hold overnight — if the last sync before a
//  07:30 nag happens the evening before, nothing was there to promote it
//  from a placeholder to the real batch, so it fired once and went
//  silent. Since the batch's times are anchored to the real due moment
//  regardless of how far in advance it's booked, there's no reason to
//  wait until shortly before — `activeWindow` is now 24h, so any sync
//  from the day before reliably books tomorrow's nag properly. That in
//  turn meant a *daily* nag's next occurrence is always within 24h by
//  definition, so it'd sit in full-batch mode permanently — fine on its
//  own, but combined with the old design's one-placeholder-per-future-
//  occurrence habit (up to ~10 wasted slots per recurring nag), two daily
//  nags could together approach the 64 cap, which iOS enforces by
//  silently keeping some undocumented-in-practice subset and dropping
//  the rest with no error at all. Dropping the placeholder tier entirely
//  (nothing booked beyond `activeWindow`, no exceptions) removes that
//  waste — each nag now only ever costs `batchSize` slots, only once it's
//  actually within a day of mattering.
//
//  Applies to both genuine one-off tasks and individual generated
//  occurrences of a recurring nag (each occurrence is its own 03.01 note
//  with its own filepath, so they're scheduled/cancelled/snoozed entirely
//  independently of each other and of the 03.02 template that generated
//  them).
//

import Foundation
import UserNotifications

enum NaggingNotificationScheduler {

    static let categoryIdentifier = "OATLY_NAG"
    static let doneActionIdentifier = "OATLY_NAG_DONE"
    static let snooze1hActionIdentifier = "OATLY_NAG_SNOOZE_1H"
    static let snooze3hActionIdentifier = "OATLY_NAG_SNOOZE_3H"

    /// Regular booked occurrences — one of the rolling active-window batch.
    private static let nagPrefix = "oatly.nag."
    /// The one notification that marks "snoozed until this moment" — its
    /// mere presence in the pending list tells `sync()` to leave this task
    /// alone until it fires (see `sync`).
    private static let snoozePrefix = "oatly.nagsnooze."

    private static let activeWindow: TimeInterval = 24 * 60 * 60 // 24 hours — see file header
    private static let repeatInterval: TimeInterval = 5 * 60     // 5 min
    private static let batchSize = 12                            // ~1 hour of runway once active

    /// `userInfo` keys carried on every nag notification, so the delegate
    /// can act on Done/Snooze without re-reading the task list.
    static let userInfoFilepathKey = "oatlyFilepath"
    static let userInfoNameKey = "oatlyName"

    static func key(fromUserInfo userInfo: [AnyHashable: Any]) -> String? {
        if let filepath = userInfo[userInfoFilepathKey] as? String, !filepath.isEmpty {
            return filepath
        }
        if let name = userInfo[userInfoNameKey] as? String, !name.isEmpty {
            return name
        }
        return nil
    }

    // MARK: - Setup

    /// One-time cleanup for notifications booked by the pre-rewrite version
    /// of this scheduler, back when identifiers looked like
    /// `oatly.nag.first.<key>` / `oatly.nag.repeat.<key>` — no `|`
    /// delimiter, so the current `parseIdentifier` can't recognise them.
    /// That means every cancel/sync path here is completely blind to them,
    /// and since the old "repeat" notification used a genuinely
    /// `repeats: true` trigger, an orphaned one fires every 5 minutes
    /// forever with nothing able to stop it — reinstalling the app doesn't
    /// clear it either, since scheduled local notifications are OS state,
    /// not part of the app bundle. Safe to call unconditionally: anything
    /// in the current format always contains `|` and is left alone.
    static func purgeLegacyIdentifiers() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let legacy = pending.map(\.identifier).filter(isLegacyIdentifier)
            if !legacy.isEmpty { center.removePendingNotificationRequests(withIdentifiers: legacy) }
        }
        center.getDeliveredNotifications { delivered in
            let legacy = delivered.map { $0.request.identifier }.filter(isLegacyIdentifier)
            if !legacy.isEmpty { center.removeDeliveredNotifications(withIdentifiers: legacy) }
        }
    }

    private static func isLegacyIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(nagPrefix) && !identifier.contains("|")
    }

    /// This scheduler's `UNNotificationCategory` — see
    /// `TaskNotificationScheduler.category`'s doc comment for why this is
    /// a plain property rather than a `setNotificationCategories` call of
    /// its own: that call replaces the whole registered set, so every
    /// scheduler's category needs registering together in one batch from
    /// `iOSTaskStore.init()`, never independently.
    ///
    /// .foreground matters here, not just cosmetically: without it, iOS
    /// handles the tap purely in the background, and
    /// `UIApplication.shared.open(_:)` to hand off to Obsidian via its
    /// URL scheme silently fails to actually switch apps unless Oatly
    /// itself is active/foregrounded first. That was the bug behind
    /// Done clearing notifications but never writing `status: done`.
    static var category: UNNotificationCategory {
        let done = UNNotificationAction(
            identifier: doneActionIdentifier,
            title: "Done",
            options: [.authenticationRequired, .foreground]
        )
        let snooze1h = UNNotificationAction(
            identifier: snooze1hActionIdentifier,
            title: "Snooze 1hr",
            options: []
        )
        let snooze3h = UNNotificationAction(
            identifier: snooze3hActionIdentifier,
            title: "Snooze 3hr",
            options: []
        )
        return UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [done, snooze1h, snooze3h],
            intentIdentifiers: [],
            options: []
        )
    }

    // MARK: - Sync

    /// Call after every successful `load()`. For every qualifying task,
    /// books its next notification(s) ahead of time (see file header);
    /// cancels nagging entirely for tasks that no longer qualify (done,
    /// un-hot, nag_time removed, or the task gone).
    ///
    /// `excludingKeys` lets the caller veto tasks that were just marked
    /// done locally but whose done-ness the synced `tasks` payload might
    /// not reflect yet (the vault write-back is asynchronous) — without
    /// this, a `load()` that runs moments after cancelling a nag could see
    /// stale "still hot" data and immediately re-book the nag it just
    /// cancelled. See `iOSTaskStore.recentlyDoneKeys`.
    static func sync(tasks: [OTTaskJSON], excludingKeys: Set<String> = []) {
        let now = Date()
        let qualifying = tasks.filter { isNagCandidate($0) && !excludingKeys.contains(key(for: $0)) }
        let qualifyingByKey = Dictionary(uniqueKeysWithValues: qualifying.map { (key(for: $0), $0) })

        let center = UNUserNotificationCenter.current()
        let group = DispatchGroup()
        var pendingRequests: [UNNotificationRequest] = []
        // Keys with any already-*delivered* nag/snooze notification —
        // tracked separately from `pendingRequests` (a different store)
        // purely so a task whose last pending occurrence already fired
        // still gets its stale, stacked notifications cleared away below.
        var deliveredKeys: Set<String> = []

        group.enter()
        center.getPendingNotificationRequests { pending in
            pendingRequests = pending
            group.leave()
        }
        group.enter()
        center.getDeliveredNotifications { delivered in
            deliveredKeys = Set(delivered.compactMap { note -> String? in
                if let parsed = parseIdentifier(note.request.identifier, prefix: nagPrefix) { return parsed.key }
                if let parsed = parseIdentifier(note.request.identifier, prefix: snoozePrefix) { return parsed.key }
                return nil
            })
            group.leave()
        }

        group.notify(queue: .main) {
            var nagDatesByKey: [String: [Date]] = [:]
            var snoozeDateByKey: [String: Date] = [:]
            for request in pendingRequests {
                if let (key, date) = parseIdentifier(request.identifier, prefix: nagPrefix) {
                    nagDatesByKey[key, default: []].append(date)
                } else if let (key, date) = parseIdentifier(request.identifier, prefix: snoozePrefix) {
                    snoozeDateByKey[key] = date
                }
            }

            // Cancel everything for tasks that no longer qualify.
            let allKeys = Set(nagDatesByKey.keys).union(snoozeDateByKey.keys).union(deliveredKeys)
            let toCancel = allKeys.subtracting(qualifyingByKey.keys)
            if !toCancel.isEmpty {
                removeAll(forKeys: Array(toCancel), center: center)
            }

            // Book/top-up for qualifying tasks.
            for (key, task) in qualifyingByKey {
                guard let startMoment = startMoment(for: task) else { continue }

                // A pending snooze marker means "leave this alone until it
                // fires" — don't let the normal due-time logic override it.
                if let snoozeDate = snoozeDateByKey[key], snoozeDate > now {
                    continue
                }

                let existingFuture = (nagDatesByKey[key] ?? []).filter { $0 > now }
                bookOccurrences(task: task, key: key, startMoment: startMoment, now: now, existingFuture: existingFuture)
            }
        }
    }

    /// A task is a nag candidate if it's hot and has a parseable `nagTime`
    /// + `due`, regardless of how far in the future that is — whether
    /// anything actually gets *booked* for it yet is decided separately in
    /// `bookOccurrences`, since reserving a notification slot for every
    /// future occurrence of a recurring nag (some of them a week or more
    /// out) would burn through the 64-notification budget for no benefit;
    /// far-out ones just wait to be picked up once a later `sync()` brings
    /// them inside `activeWindow`.
    private static func isNagCandidate(_ task: OTTaskJSON) -> Bool {
        guard task.status == "hot" else { return false }
        guard let nagTime = task.nagTime, !nagTime.isEmpty else { return false }
        guard let due = task.due, !due.isEmpty else { return false }
        return startMoment(due: due, nagTime: nagTime) != nil
    }

    private static func startMoment(for task: OTTaskJSON) -> Date? {
        guard let nagTime = task.nagTime, let due = task.due else { return nil }
        return startMoment(due: due, nagTime: nagTime)
    }

    /// Combine `due` (`yyyy-MM-dd`) and `nagTime` (`HH:mm`) into a single
    /// Date in Europe/London.
    private static func startMoment(due: String, nagTime: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(due) \(nagTime)")
    }

    // MARK: - Booking

    /// Book whatever's missing for this task. Anything more than
    /// `activeWindow` away gets nothing booked yet at all — no placeholder
    /// — since a recurring nag can have many future occurrences and
    /// reserving even one slot each would eat into the shared 64-slot
    /// budget for no real benefit; a later `sync()` will book it properly
    /// once it's actually close. Inside the window (or already overdue),
    /// keeps a topped-up rolling batch of `batchSize` occurrences
    /// `repeatInterval` apart, anchored to the real due moment regardless
    /// of when this particular `sync()` happened to run.
    private static func bookOccurrences(task: OTTaskJSON, key: String, startMoment: Date, now: Date, existingFuture: [Date]) {
        guard startMoment <= now.addingTimeInterval(activeWindow) else { return }

        // Active window: if overdue, the first occurrence should fire
        // immediately rather than waiting for the next 5-minute mark.
        let firstOccurrence = startMoment > now ? startMoment : now.addingTimeInterval(1)
        let target = (0..<batchSize).map { firstOccurrence.addingTimeInterval(Double($0) * repeatInterval) }
        let missing = target.filter { wanted in
            !existingFuture.contains { abs($0.timeIntervalSince(wanted)) < 30 }
        }
        for date in missing {
            scheduleOccurrence(task: task, key: key, at: date)
        }
    }

    private static func scheduleOccurrence(task: OTTaskJSON, key: String, at date: Date) {
        let content = makeContent(for: task)
        let interval = max(date.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(prefix: nagPrefix, key: key, date: date),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Nag schedule failed for \(task.name) at \(date): \(error)") }
        }
    }

    // MARK: - Cancel

    /// Cancel nagging for a task entirely — used when a task drops out of
    /// the qualifying set, and by the notification-action delegate when
    /// "Done" is tapped, so it doesn't have to wait for the next `sync()`.
    ///
    /// Takes a completion closure because this matters more here than it
    /// looks: `UNUserNotificationCenterDelegate` callbacks are expected to
    /// call their own completion handler once *actually* done, and iOS is
    /// free to suspend the app shortly after that's called. This does two
    /// rounds of async notification-center lookups before it can remove
    /// anything — if the caller signals "done" before this finishes, the
    /// app can be suspended mid-cancellation, leaving later occurrences in
    /// the batch to fire anyway. Callers handling a notification action
    /// should wait for this completion before calling their own.
    static func cancelNagging(key: String, completion: @escaping () -> Void = {}) {
        let center = UNUserNotificationCenter.current()
        allMatchingIdentifiers(keys: [key], center: center) { ids in
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
            completion()
        }
    }

    private static func removeAll(forKeys keys: [String], center: UNUserNotificationCenter) {
        allMatchingIdentifiers(keys: Set(keys), center: center) { ids in
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    /// Gathers every notification identifier matching any of the given
    /// keys, checking *both* pending requests and already-delivered
    /// notifications — separate stores in `UNUserNotificationCenter`.
    /// Only checking pending was the bug behind old, already-fired nag
    /// notifications staying stacked in Notification Center after the
    /// task they belonged to was cancelled or marked done.
    private static func allMatchingIdentifiers(keys: Set<String>, center: UNUserNotificationCenter, completion: @escaping ([String]) -> Void) {
        let group = DispatchGroup()
        var pendingIDs: [String] = []
        var deliveredIDs: [String] = []

        group.enter()
        center.getPendingNotificationRequests { pending in
            pendingIDs = pending.map(\.identifier).filter { id in keys.contains { matchesKey(id, key: $0) } }
            group.leave()
        }
        group.enter()
        center.getDeliveredNotifications { delivered in
            deliveredIDs = delivered.map { $0.request.identifier }.filter { id in keys.contains { matchesKey(id, key: $0) } }
            group.leave()
        }
        group.notify(queue: .main) {
            completion(Array(Set(pendingIDs + deliveredIDs)))
        }
    }

    // MARK: - Snooze

    /// Silence a nagging task for the given duration, then resume. Only
    /// affects this one task/occurrence — never the 03.02 template or any
    /// other occurrence.
    ///
    /// Cancels every currently-booked occurrence for this task, then books
    /// a single "snooze marker" notification at `now + duration` — same
    /// far-future mechanism as a brand new task's first ping, so it fires
    /// on the dot with no app involvement needed. While that marker is
    /// still pending, `sync()` leaves this task alone (see `sync`). Once
    /// it fires, it naturally drops out of the pending list, and the next
    /// `sync()` finds the task's real due moment long overdue and resumes
    /// full 5-minute nagging — which happens automatically if David
    /// interacts with the snooze-expiry notification (that reopens the
    /// app), or the next time the app is opened normally either way.
    /// See `cancelNagging`'s doc comment re: the completion closure — same
    /// reasoning applies here (two async lookups plus a schedule call
    /// before there's nothing left to interrupt).
    static func snooze(_ task: OTTaskJSON, duration: TimeInterval, completion: @escaping () -> Void = {}) {
        let key = key(for: task)
        let now = Date()
        let resumeAt = now.addingTimeInterval(duration)
        let center = UNUserNotificationCenter.current()

        allMatchingIdentifiers(keys: [key], center: center) { ids in
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }

            let content = makeContent(for: task)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: duration, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier(prefix: snoozePrefix, key: key, date: resumeAt),
                content: content,
                trigger: trigger
            )
            center.add(request) { error in
                if let error = error { print("Nag snooze failed for \(task.name): \(error)") }
                completion()
            }
        }
    }

    // MARK: - Identifier helpers

    /// `<prefix><epochSeconds>|<key>` — the key (a vault filepath) comes
    /// last so it can contain almost anything without upsetting parsing;
    /// only the leading epoch segment needs to be delimited cleanly.
    private static func identifier(prefix: String, key: String, date: Date) -> String {
        "\(prefix)\(Int(date.timeIntervalSince1970))|\(key)"
    }

    private static func parseIdentifier(_ identifier: String, prefix: String) -> (key: String, date: Date)? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let rest = identifier.dropFirst(prefix.count)
        guard let barIndex = rest.firstIndex(of: "|") else { return nil }
        guard let epoch = TimeInterval(rest[rest.startIndex..<barIndex]) else { return nil }
        let key = String(rest[rest.index(after: barIndex)...])
        return (key, Date(timeIntervalSince1970: epoch))
    }

    private static func matchesKey(_ identifier: String, key: String) -> Bool {
        if let parsed = parseIdentifier(identifier, prefix: nagPrefix), parsed.key == key { return true }
        if let parsed = parseIdentifier(identifier, prefix: snoozePrefix), parsed.key == key { return true }
        return false
    }

    // MARK: - Content

    private static func makeContent(for task: OTTaskJSON) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = task.name
        content.body = "Due — \(displayRole(task.role))"
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [
            userInfoFilepathKey: task.filepath ?? "",
            userInfoNameKey: task.name
        ]
        return content
    }

    private static func key(for task: OTTaskJSON) -> String {
        task.filepath ?? task.name
    }

    private static func displayRole(_ role: String) -> String {
        role.replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
    }
}

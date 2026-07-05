//
//  ReminderImportScheduler.swift
//  Oatly
//
//  Native replacement (2026-07-05) for the old `OT-R2O.scpt` (AppleScript)
//  + `OT-R2O.py` + Keyboard Maestro pipeline. Reads open Apple Reminders
//  via EventKit and imports them into 03.01 tasks, same one-way,
//  at-most-once behaviour as before: create the note, mark the source
//  reminder complete, never touch it again.
//
//  Called from `Maintenance.runMaintenance()` on the same 10-minute timer
//  as recurring-task generation and status promotion — see
//  `Maintenance.swift`'s file header for why the interval was tightened
//  from hourly alongside this change.
//
//  Behavioural change from OT-R2O: a reminder with a specific time
//  attached (not just a date) used to be skipped outright — instead it's
//  now imported the same as any other reminder, with that time captured
//  as `nag_time`, so it gets the Due-app-style repeat-every-5-minutes
//  treatment from `NaggingNotificationScheduler` on mobile once it's hot.
//  `OT-R2Due.scpt`/`.py`, which used to catch exactly these and route them
//  into the Due app via a Shortcut instead, is retired as of this same
//  change — see `Task Management Context.md`.
//
//  "Has a time" is detected via EventKit's own `dueDateComponents.hour`/
//  `.minute` being non-nil, rather than the AppleScript version's
//  hour == 0 && minute == 0 heuristic — this is strictly more correct
//  (a reminder genuinely, deliberately set for exactly midnight would
//  have been misread as "no time" by the old approach; EventKit just
//  tells us directly whether a time component was set at all).
//

import Foundation
import EventKit

/// Reminders lists we never import from — deliveries and shopping have
/// their own pipelines, and "Obsidian" is the one-way *output* list used
/// elsewhere (OT-O2R-AM etc.), not an input source.
private let kExcludedReminderLists: Set<String> = ["Deliveries", "Shopping", "Obsidian"]

extension TaskStore {

    /// Entry point, called once per `runMaintenance()` tick. Requests
    /// Reminders access (a no-op prompt after the first grant) and, if
    /// granted, fetches every incomplete reminder from every non-excluded
    /// list and imports each one. Silently does nothing if access hasn't
    /// been granted — same "no error surfaced to the user" approach used
    /// elsewhere in this codebase (e.g. URL-open failures on mobile).
    func runReminderImport() {
        let eventStore = EKEventStore()
        eventStore.requestFullAccessToReminders { [weak self] granted, error in
            guard granted else {
                if let error = error {
                    print("ReminderImport: Reminders access not granted: \(error)")
                }
                return
            }
            guard let self = self else { return }

            let calendars = eventStore.calendars(for: .reminder)
                .filter { !kExcludedReminderLists.contains($0.title) }
            guard !calendars.isEmpty else { return }

            // `withDueDateStarting: nil, ending: nil` deliberately includes
            // reminders with no due date at all — those default to today,
            // same as the old script.
            let predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: calendars
            )
            eventStore.fetchReminders(matching: predicate) { reminders in
                guard let reminders = reminders, !reminders.isEmpty else { return }
                for reminder in reminders {
                    self.importReminder(reminder, eventStore: eventStore)
                }
            }
        }
    }

    /// Import one reminder: write a 03.01 note (unless a note with the
    /// same filename already exists, in which case this is a no-op name/
    /// date collision, not a retry candidate), then mark the source
    /// reminder complete either way — matching OT-R2O's one-way,
    /// at-most-once behaviour exactly.
    private func importReminder(_ reminder: EKReminder, eventStore: EKEventStore) {
        guard let taskName = reminder.title, !taskName.isEmpty else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var dueDate = today
        var nagTime: String?

        if let comps = reminder.dueDateComponents, let d = cal.date(from: comps) {
            dueDate = cal.startOfDay(for: d)
            if let hour = comps.hour, let minute = comps.minute {
                nagTime = String(format: "%02d:%02d", hour, minute)
            }
        }

        let dueDateStr = isoDate(dueDate)
        let listName = reminder.calendar?.title ?? ""

        var displayName = taskName
        if listName == "Scouts" {
            displayName += " [[11.09 Scouts]]"
        }

        let safeName = sanitiseFilename(displayName)
        let stem = "\(dueDateStr) \(safeName)"
        let noteURL = tasksFolder.appendingPathComponent("\(stem).md")

        if !FileManager.default.fileExists(atPath: noteURL.path) {
            let daysUntilDue = cal.dateComponents([.day], from: today, to: dueDate).day ?? 0
            let status: String
            if daysUntilDue <= 7 {
                status = "hot"
            } else if daysUntilDue <= 30 {
                status = "warm"
            } else {
                status = "cool"
            }

            var lines = [
                "---",
                "name: \(yamlString(displayName))",
                "source: reminders",
                "due: \(dueDateStr)"
            ]
            if let nagTime = nagTime {
                lines.append("nag_time: \(nagTime)")
            }
            lines.append(contentsOf: [
                "role: \"[[Daily mop up]]\"",
                "non_negotiable: true",
                "optional: false",
                "status: \(status)",
                "created: \(isoDate(today))"
            ])

            let taskURL = reminder.url?.absoluteString ?? ""
            if !taskURL.isEmpty {
                lines.append("url: \(yamlString(taskURL))")
            }
            lines.append(contentsOf: [
                "icon: ☑️",
                "color: \"#ef44448f\"",
                "---",
                "`BUTTON[03.01hot]` `BUTTON[03.01warm]` `BUTTON[03.01cool]` `BUTTON[03.01dropped]` `BUTTON[03.01done]`",
                ""
            ])
            if !taskURL.isEmpty {
                lines.append(taskURL)
                lines.append("")
            }

            do {
                try lines.joined(separator: "\n").write(to: noteURL, atomically: true, encoding: .utf8)
            } catch {
                print("ReminderImport: failed to create \(stem): \(error)")
            }
        }

        reminder.isCompleted = true
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            print("ReminderImport: failed to mark '\(taskName)' complete: \(error)")
        }
    }
}

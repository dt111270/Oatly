//
//  Maintenance.swift
//  Oatly
//
//  Periodic in-app maintenance: mirrors the relevant pieces of the
//  weekly task review skill so that the task list stays current without
//  relying on the Sunday review.
//
//  1. **Generate** one-off 03.01 tasks from active 03.02 recurring
//     templates for any occurrences within the next 11 days. Idempotent:
//     skips creation if a note with the same `YYYY-MM-DD {name}.md`
//     filename already exists. Output matches OT-recurring-to-tasks.py
//     so the two can coexist safely.
//
//  2. **Promote** 03.01 tasks with status `warm` or `cool` (including
//     overdue ones) to `hot` if their due date is within today + 11 days.
//
//  3. **Import** open Apple Reminders into 03.01 tasks — see
//     `ReminderImportScheduler.swift`. Native replacement (2026-07-05) for
//     the old `OT-R2O.scpt` + `OT-R2O.py` + Keyboard Maestro pipeline.
//
//  Runs once on init and then every 10 minutes via Timer (was hourly until
//  2026-07-05, tightened once the Reminders import moved in here too — a
//  timed reminder sitting around for up to an hour before being picked up
//  defeated the point of nag_time). No MMUtil host gate yet — to be added
//  once the feature is verified on the laptop.
//

import Foundation

private let kMaintenanceWindowDays = 11
private let kMaintenanceIntervalSeconds: TimeInterval = 10 * 60   // every 10 minutes

extension TaskStore {

    /// Public entry point. Call once from `init()`.
    func startMaintenance() {
        runMaintenance()
        Timer.scheduledTimer(withTimeInterval: kMaintenanceIntervalSeconds, repeats: true) { [weak self] _ in
            self?.runMaintenance()
        }
    }

    /// Run both maintenance steps in sequence. Safe to call repeatedly.
    /// Only fires on MMUtil (or when iCloudSyncOverride is on for laptop
    /// fallback) — same gate as iCloud writes, so the "canonical Mac"
    /// is the one doing periodic vault writes.
    func runMaintenance() {
        guard iCloudSyncEnabled else { return }
        runRecurringGeneration()
        runStatusPromotion()
        runReminderImport()
        // Refresh in-memory state so the UI reflects any file changes.
        load()
        loadRecurring()
        // Stamp the run so the sidebar can show when this last happened.
        DispatchQueue.main.async { [weak self] in
            self?.lastMaintenanceRun = Date()
        }
    }

    // MARK: - Step 1: Generate one-off tasks from recurring templates

    fileprivate func runRecurringGeneration() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let cutoff = cal.date(byAdding: .day, value: kMaintenanceWindowDays, to: today) else { return }

        // We need the freshest list of recurring tasks. The store is
        // polling already but if maintenance fires at the same moment as
        // a poll we may be operating on slightly-stale data — re-read
        // here to make sure we don't miss a brand-new template.
        loadRecurring()

        for recurring in recurringTasks where recurring.status == "active" {
            guard let freq = recurring.frequencyEnum,
                  let root = recurring.rootDateAsDate else { continue }

            let occurrences = allOccurrences(
                rootDate: root,
                frequency: freq,
                from: today,
                to: cutoff
            )
            guard !occurrences.isEmpty else { continue }

            let parentStem = recurring.fileURL.deletingPathExtension().lastPathComponent
            let bodyContent = recurring.body

            for due in occurrences {
                let dueStr = isoDate(due)
                let safeName = sanitiseFilename(recurring.name)
                let stem = "\(dueStr) \(safeName)"
                let noteURL = tasksFolder.appendingPathComponent("\(stem).md")

                // Idempotency: skip if a note with this exact filename
                // already exists — regardless of its status. Matches the
                // Python script's behaviour.
                if FileManager.default.fileExists(atPath: noteURL.path) { continue }

                let roleField: String
                if recurring.role.isEmpty {
                    roleField = "\"[[Daily mop up]]\""
                } else {
                    roleField = "\"[[\(recurring.role)]]\""
                }

                var frontmatterLines = [
                    "---",
                    "name: \(yamlString(recurring.name))",
                    "source: recurring-task",
                    "parent: \"[[\(parentStem)]]\"",
                    "due: \(dueStr)",
                    "role: \(roleField)",
                    "non_negotiable: \(recurring.nonNegotiable ? "true" : "false")",
                    "optional: \(recurring.optional ? "true" : "false")",
                    "status: hot",
                    "created: \(isoDate(today))",
                    "icon: ☑️",
                    "color: \"#ef44448f\""
                ]
                // Carried through from the 03.02 template only if set — most
                // recurring tasks have neither, and omitting the keys keeps
                // the generated frontmatter identical to before.
                if let nagTime = recurring.nagTime, !nagTime.isEmpty {
                    frontmatterLines.append("nag_time: \(nagTime)")
                }
                if let url = recurring.url, !url.isEmpty {
                    frontmatterLines.append("url: \(url)")
                }
                frontmatterLines.append("---\n\n")
                let frontmatter = frontmatterLines.joined(separator: "\n")

                let content = frontmatter + bodyContent

                do {
                    try content.write(to: noteURL, atomically: true, encoding: .utf8)
                } catch {
                    print("Maintenance: failed to create \(stem): \(error)")
                }
            }
        }
    }

    // MARK: - Step 2: Promote warm/cool tasks within 11 days to hot

    fileprivate func runStatusPromotion() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let cutoff = cal.date(byAdding: .day, value: kMaintenanceWindowDays, to: today) else { return }
        let cutoffStr = isoDate(cutoff)

        for task in tasks where ["warm", "cool"].contains(task.status) {
            guard let due = task.due, !due.isEmpty else { continue }
            // Promote if due <= cutoff (covers overdue too — overdue dates
            // are always less than today which is always less than cutoff).
            if due <= cutoffStr {
                TaskParser.updateStatus(fileURL: task.fileURL, newStatus: "hot")
            }
        }
    }

    // MARK: - Helpers

    /// All occurrences of a recurring schedule between `from` and `to`
    /// (both inclusive). Uses `RecurringFrequency.advance` so month-end
    /// edge cases, and the weekday-skipping "every weekday" case, are
    /// both handled correctly.
    private func allOccurrences(rootDate: Date,
                                frequency: RecurringFrequency,
                                from: Date,
                                to: Date) -> [Date] {
        let cal = Calendar.current
        var occurrences: [Date] = []
        var candidate = rootDate
        var safety = 0

        // Advance to the first occurrence on or after `from`.
        while candidate < from && safety < 5000 {
            guard let next = frequency.advance(from: candidate, calendar: cal) else { return occurrences }
            candidate = next
            safety += 1
        }

        // Collect all occurrences up to and including `to`.
        while candidate <= to && safety < 5000 {
            occurrences.append(candidate)
            guard let next = frequency.advance(from: candidate, calendar: cal) else { break }
            candidate = next
            safety += 1
        }

        return occurrences
    }

    // Deliberately not `private` — `ReminderImportScheduler.swift` reuses
    // these three rather than duplicating the same formatting/quoting/
    // sanitising logic in a second place, which is exactly the kind of
    // drift that made the old OT-R2O.py (a parallel Python reimplementation
    // of this same logic) worth retiring in the first place.
    func isoDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/London")
        return f.string(from: d)
    }

    /// Quote a name as a YAML string if it contains special characters.
    /// Matches the Python script's `yaml_str` helper.
    func yamlString(_ s: String) -> String {
        let special: Set<Character> = [":", "[", "]", "#", "{", "}", "|", ">", "&", "*", "!", ",", "?", "'", "\""]
        if s.contains(where: { special.contains($0) }) {
            let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return s
    }

    /// Strip characters that are invalid (or awkward) in filenames.
    /// Matches the Python script's `safe_filename` helper.
    func sanitiseFilename(_ name: String) -> String {
        let invalid: Set<Character> = ["\\", "/", "*", "?", ":", "\"", "<", ">", "|", "#", "[", "]"]
        let filtered = String(name.filter { !invalid.contains($0) })
        return filtered.trimmingCharacters(in: .whitespaces)
    }
}

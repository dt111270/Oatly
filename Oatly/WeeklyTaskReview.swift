//
//  WeeklyTaskReview.swift
//  Oatly
//
//  Definition of the Weekly Task Review checklist.
//
//  Replaces the Cowork weekly-task-review skill. The old skill had nine
//  steps including promotion, recurring generation, and a hot-tasks PDF
//  print — those are gone: promotion and recurring generation now happen
//  hourly via TaskStore maintenance, and PDF printing will become its
//  own feature later.
//
//  Five visible steps remain. The runner auto-writes the log + daily-note
//  line on completion of the last step (no separate Finish button).
//

import Foundation

enum WeeklyTaskReview {
    static let checklist = Checklist(
        title: "Weekly Task Review",
        steps: [
            ChecklistStep(
                label: "Review Hot tasks",
                detail: "Switch to the 🔥 Hot view in Oatly's sidebar. Sweep up anything you've already done but haven't flagged complete.",
                action: .manual
            ),
            ChecklistStep(
                label: "Review Overdue tasks",
                detail: "Switch to the 🧯 Overdue view. Clear, drop, or reschedule.",
                action: .manual
            ),
            ChecklistStep(
                label: "Review Warm tasks",
                detail: "Switch to the ⛅ Warm view. Promote anything due in the coming week to Hot; drop or demote what no longer warrants Warm.",
                action: .manual
            ),
            ChecklistStep(
                label: "Review Cool tasks",
                detail: "Switch to the ❄️ Cool view. Promote or drop as appropriate.",
                action: .manual
            ),
            ChecklistStep(
                label: "Scan for invalid statuses",
                detail: nil,
                action: .inline(InlineAction {
                    let offenders = TaskStatusValidator.scan()
                    if offenders.isEmpty {
                        return InlineActionResult(
                            summary: "All tasks have valid statuses."
                        )
                    } else {
                        let lines = offenders.map { rep -> String in
                            if let bad = rep.badValue {
                                return "✗ \(rep.filename) → status: \(bad)"
                            } else {
                                return "✗ \(rep.filename) → no status field"
                            }
                        }
                        let header = "\(offenders.count) task(s) need attention:"
                        return InlineActionResult(
                            summary: header + "\n" + lines.joined(separator: "\n")
                        )
                    }
                })
            )
        ]
    )
}

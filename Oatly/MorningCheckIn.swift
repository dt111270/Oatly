//
//  MorningCheckIn.swift
//  Oatly
//
//  Definition of the Morning Check-In checklist.
//
//  Five visible manual steps. The runner auto-writes the log + daily-note
//  line on completion of the last step.
//

import Foundation

enum MorningCheckIn {
    static let checklist = Checklist(
        title: "Morning Check-In",
        steps: [
            ChecklistStep(
                label: "Review Daily Briefing",
                detail: "Open today's Daily Briefing in your Arc notebook and read through.",
                action: .manual
            ),
            ChecklistStep(
                label: "Email inbox triage",
                detail: "Process overnight email. Action, archive, or defer to @1 Later.",
                action: .manual
            ),
            ChecklistStep(
                label: "Review Hot tasks",
                detail: "Switch to the 🔥 Hot view. Confirm the top of the list reflects today's priorities.",
                action: .manual
            ),
            ChecklistStep(
                label: "Write to-do card",
                detail: "Write today's must-dos on a fresh 3×5 index card.",
                action: .manual
            ),
            ChecklistStep(
                label: "Review calendar",
                detail: "Glance at today's calendar. Note conflicts, prep needed, and travel.",
                action: .manual
            ),
        ]
    )
}

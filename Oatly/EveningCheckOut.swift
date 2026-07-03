//
//  EveningCheckOut.swift
//  Oatly
//
//  Definition of the Evening Check-Out checklist.
//
//  Eight visible steps. Step 7 opens Obsidian via `obsidian://open?vault=…`
//  so the user can clear the vault root. Step 8 is optional and opens a
//  `mailto:tomorrow@fut.io` link — the macOS default mail client
//  (Superhuman in David's case) handles composition. The runner auto-
//  writes the log + daily-note line on completion of the last step.
//

import Foundation

enum EveningCheckOut {
    static let checklist = Checklist(
        title: "Evening Check-Out",
        steps: [
            ChecklistStep(
                label: "Review Daily Briefing page",
                detail: "Review the Daily Briefing page in your Arc notebook for handwritten notes.",
                action: .manual
            ),
            ChecklistStep(
                label: "Triage Overdue",
                detail: "Switch to the 🧯 Overdue view. Anything still overdue: re-date, drop, or push out.",
                action: .manual
            ),
            ChecklistStep(
                label: "Triage Hot",
                detail: "Switch to the 🔥 Hot view. Anything not genuinely Hot tomorrow gets downgraded or dropped.",
                action: .manual
            ),
            ChecklistStep(
                label: "Clear today's email from Inbox",
                detail: "Action or archive every email received today. Eyeball it.",
                action: .manual
            ),
            ChecklistStep(
                label: "Clear today's email from @1 Later",
                detail: "Same sweep — @1 Later folder.",
                action: .manual
            ),
            ChecklistStep(
                label: "Clear Junk",
                detail: "Empty the Junk folder.",
                action: .manual
            ),
            ChecklistStep(
                label: "Clear Obsidian root folder",
                detail: "File or process any loose notes sitting at the vault root.",
                action: .openURL(URL(string: "obsidian://open?vault=DTObs")!)
            ),
            ChecklistStep(
                label: "(Optional) Send tomorrow-notes email",
                detail: "Opens a mailto: link to tomorrow@fut.io in your default mail client. Skip if there's nothing for tomorrow-you to know.",
                action: .openURL(URL(string: "mailto:tomorrow@fut.io")!)
            ),
        ]
    )
}

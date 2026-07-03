//
//  Checklist.swift
//  Oatly
//
//  Data model for the in-app checklist runner. A `Checklist` is a static
//  ordered list of `ChecklistStep`s; a `ChecklistSession` tracks one run
//  through it. Phase 1 supports three step kinds — manual, openURL, and
//  inline (Swift closure). A `script` kind will be added when the first
//  routine needs it.
//

import Foundation

// MARK: - Step actions

/// What a step actually does when active.
enum StepAction {
    /// No automatic action — the user reads the label and ticks done.
    case manual
    /// Step shows an "Open" button that fires the URL via NSWorkspace.
    case openURL(URL)
    /// Step runs a Swift closure on display and shows the result inline.
    case inline(InlineAction)
}

/// Wrapper around the closure so `StepAction` can stay a value type.
struct InlineAction {
    let perform: () -> InlineActionResult
}

/// Output of an inline action — a summary string the runner displays
/// under the step's main label.
struct InlineActionResult {
    let summary: String
}

// MARK: - Step + status

enum StepStatus {
    case pending
    case done       // logged as ✅
    case skipped    // logged as ❌
}

struct ChecklistStep: Identifiable {
    let id = UUID()
    /// Primary headline shown in the runner window.
    let label: String
    /// Optional secondary text (e.g. "Switch to the Hot view in the sidebar").
    let detail: String?
    /// The action that fires when this step becomes current.
    let action: StepAction
}

// MARK: - Checklist

struct Checklist {
    /// Used in the window header and as the log-note filename suffix
    /// (e.g. "Weekly Task Review" → "2026-05-24 Weekly Task Review.md").
    let title: String
    let steps: [ChecklistStep]
}

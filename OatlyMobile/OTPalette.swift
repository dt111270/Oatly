//
//  OTPalette.swift
//  OatlyMobile
//
//  Colour palette + shared formatting for the 2026-07 redesign (Claude
//  Design spec "Reminders Redesign — Handoff Spec, variant 2a"). Replaces
//  the old per-file `brandBlue` constant duplicated across ContentView,
//  iPadTaskListView, and iPadTaskDetailView, and the duplicated 3-state
//  due-date colour logic in TaskRowView/iPadTaskDetailView — same
//  "don't let two copies of the same rule drift apart" reasoning as
//  retiring OT-R2O.py in favour of one Swift implementation.
//
//  Applied in full (cards, background, typography) to the iPhone layout
//  in ContentView.swift/TaskRowView.swift. Applied as colours/accents only
//  — no card layout — to the iPad three-pane views, per David's call:
//  the iPad's column layout is structurally different and wasn't part of
//  the redesign brief.
//

import SwiftUI

enum OTPalette {
    /// Warm cream screen background.
    static let background = Color(red: 0xFB / 255, green: 0xF6 / 255, blue: 0xEE / 255)

    /// White card surface (iPhone card layout only).
    static let cardSurface = Color.white

    /// Primary text/ink.
    static let textPrimary = Color(red: 0x2B / 255, green: 0x26 / 255, blue: 0x20 / 255)

    /// Secondary/time text — textPrimary at 40% opacity.
    static var textSecondary: Color { textPrimary.opacity(0.4) }

    /// Accent — section headers, checkboxes, the + button, on-time due dates.
    static let accent = Color(red: 0x1C / 255, green: 0x63 / 255, blue: 0xD9 / 255)

    /// Overdue due-date text.
    static let overdue = Color(red: 0xC2 / 255, green: 0x41 / 255, blue: 0x0C / 255)

    /// Divider/row separator — textPrimary at 8% opacity.
    static var divider: Color { textPrimary.opacity(0.08) }

    /// Card shadow colour — textPrimary at 6% opacity.
    static var cardShadow: Color { textPrimary.opacity(0.06) }

    /// 2-state due-date colour rule from the spec: rust-orange if overdue,
    /// accent blue otherwise (today or future). A done task gets plain
    /// primary text instead — colour only matters while it still needs
    /// attention. Simpler than the old 3-state red/orange/grey rule.
    static func dueColor(_ due: String, isDone: Bool = false) -> Color {
        // Dimmed to match the muted checkbox ring and greyed-out title once
        // a task's done — the coloured due-date only matters while it's
        // still live.
        guard !isDone else { return textSecondary }
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        return due < today ? overdue : accent
    }

    /// Reformats a `YYYY-MM-DD` due string to the mockup's "MMM d" style
    /// (e.g. "Jul 5"). Falls back to the raw string if it doesn't parse.
    static func formattedDue(_ due: String) -> String {
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        iso.locale = Locale(identifier: "en_US_POSIX")
        guard let date = iso.date(from: due) else { return due }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        out.locale = Locale(identifier: "en_US_POSIX")
        return out.string(from: date)
    }
}

/// White rounded-rect "card" container from the redesign spec — 14pt
/// corner radius, subtle shadow. SwiftUI's native grouped List style
/// doesn't give this floating-card look, so sections are built manually
/// with VStack + this wrapper instead of List (iPhone layout only).
struct OTCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)  // a bit of breathing room under the last row
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(OTPalette.cardSurface)
                .shadow(color: OTPalette.cardShadow, radius: 10, x: 0, y: 2)
        )
    }
}

import Foundation

struct OTTaskJSON: Codable, Hashable {
    let name: String
    let status: String
    let role: String
    let due: String?
    let nonNegotiable: Bool
    let body: String
    let source: String?
    let filepath: String?
    /// `HH:MM`, Europe/London. Presence flags this as a "nagging" task —
    /// see `OTTask.nagTime` and `NaggingNotificationScheduler`.
    let nagTime: String?
    /// Web URL or app deeplink. Opened via the system's standard URL
    /// opener, which already routes http(s) to the default browser and
    /// custom schemes to the owning app.
    let url: String?
}

/// Mirrors `OTRecurringTask` (03.02 templates), for the "Routines" list on
/// mobile — see [[2026-07-05 Oatly Routines]] for the plan. Synced in full,
/// not just the nag-eligible ones, so mobile can filter locally the same
/// way `OTTaskJSON` already does for smart filters — keeps this reusable
/// if "Routines" ever grows beyond just the nagging ones.
struct OTRecurringTaskJSON: Codable, Hashable, Identifiable {
    var id: String { filepath }

    let name: String
    let role: String
    /// Raw frontmatter value (e.g. "weekly", "every 2 weeks") — mobile
    /// doesn't need to parse this beyond display until editing is wired up.
    let frequency: String
    let status: String
    let rootDate: String
    /// `HH:MM`, Europe/London. Presence flags this as nag-eligible — same
    /// convention as `OTTaskJSON.nagTime`.
    let nagTime: String?
    let url: String?
    let filepath: String
    /// Pre-computed via `RecurringFrequency.advance()` on the Mac side
    /// (`OTRecurringTask.nextDueString`) — mobile has no copy of that
    /// frequency maths and shouldn't need one just to show "next: ...".
    /// `nil` if the frequency or root date couldn't be parsed.
    let nextDue: String?
}

struct OTTasksPayload: Codable, Hashable {
    let updated: String
    let tasks: [OTTaskJSON]
    let recurringTasks: [OTRecurringTaskJSON]
}

//
//  RecurringTask.swift
//  Oatly
//
//  Model + frequency enum for recurring task notes stored in
//  /00-09 DTOS/03 Working Folders/03.02 repeating tasks/
//

import Foundation

// MARK: - Frequency

/// The set of repeat frequencies that the Add Recurring Task modal offers.
/// Existing recurring notes in the vault may use slightly different wording,
/// in which case `parse` returns nil and the next-due date can't be computed
/// (the row will fall back to showing the raw frequency string with a "—"
/// for next due).
enum RecurringFrequency: String, CaseIterable, Hashable, Identifiable {
    case daily         = "daily"
    case weekly        = "weekly"
    case every2Weeks   = "every 2 weeks"
    case every3Weeks   = "every 3 weeks"
    case every4Weeks   = "every 4 weeks"
    case monthly       = "monthly"
    case every2Months  = "every 2 months"
    case quarterly     = "quarterly"
    case every6Months  = "every 6 months"
    case yearly        = "yearly"
    /// Monday–Friday, skipping weekends. Can't be expressed as a fixed
    /// Calendar.Component step like the other cases — see `advance`.
    case weekdays      = "every weekday"

    var id: String { rawValue }
    var label: String { rawValue }

    /// Calendar component + value to add per occurrence. Not meaningful
    /// for `.weekdays` — use `advance(from:calendar:)` instead, which
    /// handles every case including the weekday-skipping one.
    var step: (component: Calendar.Component, value: Int) {
        switch self {
        case .daily:        return (.day, 1)
        case .weekly:       return (.day, 7)
        case .every2Weeks:  return (.day, 14)
        case .every3Weeks:  return (.day, 21)
        case .every4Weeks:  return (.day, 28)
        case .monthly:      return (.month, 1)
        case .every2Months: return (.month, 2)
        case .quarterly:    return (.month, 3)
        case .every6Months: return (.month, 6)
        case .yearly:       return (.year, 1)
        case .weekdays:     return (.day, 1)   // unused; advance() overrides
        }
    }

    /// Advance a single occurrence forward according to this frequency.
    /// All cases except `.weekdays` just add `step`. `.weekdays` adds a
    /// day at a time and skips over Saturday/Sunday, so "every weekday"
    /// from a Friday lands on the following Monday.
    func advance(from date: Date, calendar: Calendar = Calendar.current) -> Date? {
        switch self {
        case .weekdays:
            guard var next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            while calendar.isDateInWeekend(next) {
                guard let after = calendar.date(byAdding: .day, value: 1, to: next) else { return nil }
                next = after
            }
            return next
        default:
            return calendar.date(byAdding: step.component, value: step.value, to: date)
        }
    }

    /// Forgiving parser. Handles:
    /// - The canonical dropdown wording (`weekly`, `monthly`, `quarterly`, ...).
    /// - Common synonyms used in existing 03.02 notes (`every week`,
    ///   `every month`, `every year`, `every 3 months`, ...).
    /// - Trailing day-of-week qualifiers (`every week on Friday`) — the
    ///   actual day is implied by the root date, so we just drop the suffix.
    /// - A few colloquial extras (fortnightly, bi-weekly, annually, etc.).
    /// Returns nil for anything we still can't interpret.
    static func parse(_ raw: String) -> RecurringFrequency? {
        var s = raw.lowercased().trimmingCharacters(in: .whitespaces)

        // Strip a trailing " on {weekday}" qualifier.
        let weekdays = ["monday", "tuesday", "wednesday", "thursday",
                        "friday", "saturday", "sunday"]
        for wd in weekdays {
            let suffix = " on \(wd)"
            if s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // Canonical (dropdown) wording.
        if let direct = allCases.first(where: { $0.rawValue == s }) { return direct }

        // Common synonyms.
        switch s {
        case "every day":                                           return .daily
        case "every week":                                          return .weekly
        case "every 2 weeks", "fortnightly", "bi-weekly", "biweekly": return .every2Weeks
        case "every 3 weeks":                                       return .every3Weeks
        case "every 4 weeks":                                       return .every4Weeks
        case "every month":                                         return .monthly
        case "every 2 months", "bi-monthly", "bimonthly":           return .every2Months
        case "every 3 months":                                      return .quarterly
        case "every 6 months", "biannually", "semi-annually":       return .every6Months
        case "every year", "annually":                              return .yearly
        case "every weekday", "weekdays", "every week day",
             "monday to friday", "mon-fri", "weekday":               return .weekdays
        default:                                                    return nil
        }
    }
}

// MARK: - Model

struct OTRecurringTask: Identifiable, Equatable, Hashable {
    let id: URL
    let fileURL: URL

    var name: String
    var role: String          // wikilink brackets stripped
    var frequency: String     // raw frontmatter value
    var status: String        // "active" or "paused"
    var nonNegotiable: Bool
    var optional: Bool
    var rootDate: String      // YYYY-MM-DD as stored
    /// `HH:MM`, Europe/London. If set, every generated occurrence inherits
    /// this as its own `nag_time` — see `OTTask.nagTime`.
    var nagTime: String?
    /// Carried through to generated occurrences the same way as `nagTime`.
    var url: String?

    var body: String

    static func == (lhs: OTRecurringTask, rhs: OTRecurringTask) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - Derived

    /// Parsed `root date` field.
    var rootDateAsDate: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/London")
        return f.date(from: rootDate)
    }

    /// Parsed frequency, or nil if free-text doesn't match a known case.
    var frequencyEnum: RecurringFrequency? {
        RecurringFrequency.parse(frequency)
    }

    /// First occurrence on or after today, given the root date + frequency.
    /// Returns nil if either component is unparseable.
    var nextDue: Date? {
        guard let root = rootDateAsDate,
              let freq = frequencyEnum else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var next = root
        var safety = 0
        while next < today && safety < 5000 {
            guard let advanced = freq.advance(from: next, calendar: calendar) else { break }
            next = advanced
            safety += 1
        }
        return next
    }

    /// `next due` formatted as YYYY-MM-DD for display, or "—" if unknown.
    var nextDueString: String {
        guard let d = nextDue else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/London")
        return f.string(from: d)
    }
}

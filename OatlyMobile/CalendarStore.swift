//
//  CalendarStore.swift
//  OatlyMobile
//
//  Reads today's events from the four named calendars in iOS Calendar
//  and exposes them as a sorted [CalendarEvent] for the Hot screen.
//

import Foundation
import EventKit
import Combine

struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool

    var isPast: Bool {
        end < Date()
    }

    var timeLabel: String {
        if isAllDay { return "all-day" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_GB")
        return f.string(from: start)
    }
}

@MainActor
final class CalendarStore: ObservableObject {
    @Published var events: [CalendarEvent] = []
    @Published var hasAccess: Bool = false

    private let store = EKEventStore()

    /// Only events from calendars with these exact titles are shown.
    /// David's phone has a single calendar account (".me", an O365 account)
    /// so filtering by title alone is unambiguous.
    private let targetCalendarTitles: Set<String> = [
        "Birthdays",
        "Calendar",
        "Family",
        "United Kingdom holidays"
    ]

    /// Call once on first appearance to prompt the user, then keep the
    /// store loaded. Safe to call repeatedly — if access is already
    /// granted, this just refreshes events.
    func requestAccessAndLoad() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            hasAccess = granted
            if granted {
                load()
            } else {
                events = []
            }
        } catch {
            hasAccess = false
            events = []
        }
    }

    /// Fetch today's events from the target calendars, sorted with
    /// all-day events first, then by start time.
    func load() {
        let calendars = store.calendars(for: .event)
            .filter { targetCalendarTitles.contains($0.title) }

        guard !calendars.isEmpty else {
            events = []
            return
        }

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else {
            events = []
            return
        }

        let predicate = store.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: calendars
        )

        let fetched = store.events(matching: predicate)
            .map { ekEvent -> CalendarEvent in
                // eventIdentifier can be nil for occurrences of recurring
                // events; fall back to title + start to keep IDs stable.
                let base = ekEvent.eventIdentifier ?? ekEvent.title ?? "(no title)"
                let id = "\(base)|\(ekEvent.startDate.timeIntervalSince1970)"
                return CalendarEvent(
                    id: id,
                    title: ekEvent.title ?? "(no title)",
                    start: ekEvent.startDate,
                    end: ekEvent.endDate,
                    isAllDay: ekEvent.isAllDay
                )
            }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return a.start < b.start
            }

        events = fetched
    }
}

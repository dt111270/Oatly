//
//  RoutinesListView.swift
//  OatlyMobile
//
//  "Routines" — the 03.02 recurring templates that have a `nag_time` set,
//  i.e. the ones that get the Due-app-style repeat-every-5-minutes
//  treatment from NaggingNotificationScheduler once they're hot. Lets
//  David edit a routine's title/frequency/time from his phone rather than
//  needing to open the note in Obsidian directly.
//
//  Reuses the card/row visual language from the main redesign (OTCard,
//  OTPalette) for consistency, but this is its own screen, not a
//  SmartFilter case — see ContentPage in ContentView.swift for why.
//

import SwiftUI

struct RoutinesListView: View {
    @ObservedObject var store: iOSTaskStore
    @State private var editingRoutine: OTRecurringTaskJSON?

    /// Only the nag-eligible routines — `store.routines` itself carries
    /// every synced recurring task, same "sync everything, filter per
    /// screen" pattern as `store.tasks`/`SmartFilter`.
    private var routines: [OTRecurringTaskJSON] {
        store.routines
            .filter { !($0.nagTime ?? "").isEmpty }
            .sorted { ($0.nextDue ?? "9999-99-99") < ($1.nextDue ?? "9999-99-99") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !routines.isEmpty {
                    OTCard {
                        iOSSectionHeaderView(title: "Routines")
                        ForEach(Array(routines.enumerated()), id: \.element.filepath) { index, routine in
                            RoutineRowView(
                                routine: routine,
                                showDivider: index < routines.count - 1,
                                onTap: { editingRoutine = routine }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(OTPalette.background)
        .refreshable { store.load() }
        .overlay {
            if routines.isEmpty {
                ContentUnavailableView("No routines", systemImage: "alarm")
            }
        }
        .sheet(item: $editingRoutine) { routine in
            RoutineEditView(store: store, routine: routine)
        }
    }
}

struct RoutineRowView: View {
    let routine: OTRecurringTaskJSON
    var showDivider: Bool = true
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Text("⏰")
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(routine.name)
                            .font(.system(size: 14))
                            .foregroundColor(OTPalette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(routine.frequency.isEmpty ? "—" : routine.frequency)
                            .font(.system(size: 11.5))
                            .foregroundColor(OTPalette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let nagTime = routine.nagTime, !nagTime.isEmpty {
                        Text(nagTime)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(OTPalette.accent)
                            .fixedSize()
                    }
                }
                .padding(.vertical, 6.5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDivider {
                Rectangle()
                    .fill(OTPalette.divider)
                    .frame(height: 0.5)
            }
        }
    }
}

// MARK: - Edit sheet

struct RoutineEditView: View {
    @ObservedObject var store: iOSTaskStore
    let routine: OTRecurringTaskJSON
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var frequency: RecurringFrequency?
    @State private var nagTime: Date
    @State private var isSaving = false

    init(store: iOSTaskStore, routine: OTRecurringTaskJSON) {
        self.store = store
        self.routine = routine
        _name = State(initialValue: routine.name)
        _frequency = State(initialValue: RecurringFrequency.parse(routine.frequency))
        _nagTime = State(initialValue: Self.date(fromHHMM: routine.nagTime ?? "09:00") ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Name", text: $name)
                }
                Section("Frequency") {
                    Picker("Frequency", selection: $frequency) {
                        Text("Unrecognised — \(routine.frequency)").tag(RecurringFrequency?.none)
                        ForEach(RecurringFrequency.allCases) { freq in
                            Text(freq.label).tag(RecurringFrequency?.some(freq))
                        }
                    }
                }
                Section("Time") {
                    DatePicker("Nag time", selection: $nagTime, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Save

    /// Only writes fields that actually changed — each one is a separate
    /// `obsidian://adv-uri` open (see `iOSTaskStore.updateRoutine`), so
    /// there's no reason to fire one for a field the user didn't touch.
    private func save() {
        var fields: [(key: String, value: String)] = []

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty, trimmedName != routine.name {
            fields.append((key: "name", value: trimmedName))
        }
        if let frequency, frequency.rawValue != routine.frequency {
            fields.append((key: "frequency", value: frequency.rawValue))
        }
        let timeString = Self.hhmm(from: nagTime)
        if timeString != (routine.nagTime ?? "") {
            fields.append((key: "nag_time", value: timeString))
        }

        guard !fields.isEmpty else {
            dismiss()
            return
        }

        isSaving = true
        store.updateRoutine(filepath: routine.filepath, fields: fields) {
            DispatchQueue.main.async {
                isSaving = false
                dismiss()
                store.load()
            }
        }
    }

    // MARK: - Time helpers

    /// Both directions use Europe/London explicitly, matching the
    /// convention everywhere else `nag_time`/`due` are parsed or formatted
    /// (see `NaggingNotificationScheduler`) — the actual calendar day
    /// carried by the resulting `Date` doesn't matter, only the hour/minute
    /// the picker shows and writes back.
    private static func date(fromHHMM hhmm: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/London")
        return f.date(from: hhmm)
    }

    private static func hhmm(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/London")
        return f.string(from: date)
    }
}

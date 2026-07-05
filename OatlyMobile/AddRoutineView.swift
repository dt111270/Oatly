//
//  AddRoutineView.swift
//  OatlyMobile
//
//  Creates a new 03.02 recurring task, reached from the Routines tab's +
//  button. Mirrors the Mac's AddRecurringTaskView frontmatter shape
//  exactly (type: repeating-task, "root date" with a space, etc.) so both
//  creation paths produce identical notes — but writes via
//  obsidian://adv-uri&mode=new like AddTaskView does, since mobile has no
//  direct filesystem access to the vault the way the Mac app does.
//
//  nag_time is always set here (unlike AddRecurringTaskView, which has no
//  such field) — this form only exists to serve the Routines list, which
//  only shows nag-eligible routines, so a routine created from here that
//  didn't get a nag_time would just vanish from the list that created it.
//

import SwiftUI

struct AddRoutineView: View {
    @Environment(\.dismiss) var dismiss

    private let roles = ["Daily mop up", "DTOS", "Family", "Friend", "Home", "Media",
                          "MJT Producer", "Personal care", "Scout"]

    @State private var name = ""
    @State private var role = "Daily mop up"
    @State private var frequency: RecurringFrequency = .daily
    @State private var rootDate = Date()
    @State private var nagTime = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Name", text: $name)
                }
                Section("Role") {
                    Picker("Role", selection: $role) {
                        ForEach(roles, id: \.self) { r in
                            Text(r).tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Frequency") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(RecurringFrequency.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                }
                Section("Starts on") {
                    DatePicker("Base date", selection: $rootDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                Section("Nag time") {
                    DatePicker("Time", selection: $nagTime, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createRoutine()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func createRoutine() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.timeZone = TimeZone(identifier: "Europe/London")
        let rootDateStr = dateFmt.string(from: rootDate)

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.timeZone = TimeZone(identifier: "Europe/London")
        let nagTimeStr = timeFmt.string(from: nagTime)

        // No date prefix — matches AddRecurringTaskView's filename
        // convention for 03.02 notes exactly (unlike 03.01 tasks, which
        // are date-prefixed).
        let safeName = trimmedName.replacingOccurrences(
            of: "[\\/*?:\"<>|#\\[\\]]", with: "", options: .regularExpression
        )
        let filepath = "00-09 DTOS/03 Working Folders/03.02 repeating tasks/\(safeName).md"

        let content = """
---
name: \(trimmedName)
type: repeating-task
role: "[[\(role)]]"
frequency: \(frequency.rawValue)
status: active
non_negotiable: false
optional: false
root date: \(rootDateStr)
nag_time: \(nagTimeStr)
---
`BUTTON[03.01hot]` `BUTTON[03.01warm]` `BUTTON[03.01cool]` `BUTTON[03.01dropped]` `BUTTON[03.01done]`

"""
        guard let encodedPath = filepath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedContent = content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "obsidian://adv-uri?vault=DTObs&filepath=\(encodedPath)&data=\(encodedContent)&mode=new")
        else { return }

        UIApplication.shared.open(url)
    }
}

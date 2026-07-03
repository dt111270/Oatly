//
//  AddRecurringTaskView.swift
//  Oatly
//
//  Modal for creating a new recurring task. Writes the .md file directly
//  into `03.02 repeating tasks/` via FileManager (no Obsidian URI needed).
//

import SwiftUI

struct AddRecurringTaskView: View {
    @ObservedObject var store: TaskStore
    /// Called after a successful save. Passes the new task's name so the
    /// caller can locate and select it from `store.recurringTasks`.
    var onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var role: String = ""
    @State private var rootDate: Date = Date()
    @State private var frequency: RecurringFrequency = .weekly
    @State private var availableRoles: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Recurring Task")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.bottom, 16)

            Form {
                TextField("Name", text: $name)

                Picker("Role", selection: $role) {
                    Text("Select a role…").tag("")
                    ForEach(availableRoles, id: \.self) { r in
                        Text(r).tag(r)
                    }
                }

                DatePicker("Base date", selection: $rootDate, displayedComponents: .date)

                Picker("Frequency", selection: $frequency) {
                    ForEach(RecurringFrequency.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 8)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            availableRoles = store.loadRoles()
        }
    }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && !role.isEmpty
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard !role.isEmpty else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "Europe/London")
        let rootDateStr = dateFormatter.string(from: rootDate)

        let fileURL = store.recurringFolder
            .appendingPathComponent("\(trimmedName).md")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            errorMessage = "A recurring task named “\(trimmedName)” already exists."
            return
        }

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
        ---
        `BUTTON[03.01hot]` `BUTTON[03.01warm]` `BUTTON[03.01cool]` `BUTTON[03.01dropped]` `BUTTON[03.01done]`
        """

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            onSaved(trimmedName)
            dismiss()
        } catch {
            errorMessage = "Failed to write file: \(error.localizedDescription)"
        }
    }
}

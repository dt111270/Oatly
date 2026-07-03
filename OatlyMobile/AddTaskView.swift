//
//  AddTaskView.swift
//  Oatly
//
//  Created by David Turnbull on 01/05/2026.
//


import SwiftUI

struct AddTaskView: View {
    @Environment(\.dismiss) var dismiss

    let roles = ["Daily mop up", "DTOS", "Family", "Friend", "Home", "Media",
                 "MJT Producer", "Personal care", "Scout"]

    @State private var name = ""
    @State private var role = "Daily mop up"
    @State private var dueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
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
                Section("Due date") {
                    DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTask()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func createTask() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateStr = fmt.string(from: dueDate)
        let today = fmt.string(from: Date())

        let days = Calendar.current.dateComponents([.day], from: Date(), to: dueDate).day ?? 0
        let status = days <= 7 ? "hot" : days <= 30 ? "warm" : "cool"

        let safeName = trimmedName.replacingOccurrences(
            of: "[\\/*?:\"<>|#\\[\\]]", with: "", options: .regularExpression
        )
        let filepath = "00-09 DTOS/03 Working Folders/03.01 tasks/\(dateStr) \(safeName).md"

        let content = """
---
name: \(trimmedName)
source: manual
due: \(dateStr)
role: "[[\(role)]]"
non_negotiable: false
optional: false
status: \(status)
created: \(today)
icon: ☑️
color: "#ef44448f"
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
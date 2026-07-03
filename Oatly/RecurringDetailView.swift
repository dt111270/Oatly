//
//  RecurringDetailView.swift
//  Oatly
//
//  Right pane for the Recurring sidebar selection. Shows metadata
//  (name, role, frequency, base date, next due) plus an Open in
//  Obsidian button and the note body (read-only).
//

import SwiftUI

private let brandBlue = Color(red: 48/255, green: 95/255, blue: 188/255)

struct RecurringDetailView: View {
    let task: OTRecurringTask?

    var body: some View {
        Group {
            if let task = task {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // Header: name + Obsidian button
                        HStack(alignment: .firstTextBaseline) {
                            Text(task.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                            if task.status == "paused" {
                                Text("paused")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Button("🔗 Obsidian") {
                                let stem = task.fileURL.deletingPathExtension().lastPathComponent
                                let encoded = stem.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? stem
                                if let url = URL(string: "obsidian://open?vault=DTObs&file=\(encoded)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.12))
                            .foregroundColor(.purple)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.purple.opacity(0.4), lineWidth: 1))
                        }

                        // Metadata grid
                        VStack(alignment: .leading, spacing: 6) {
                            metadataRow(label: "Role", value: task.role.isEmpty ? "—" : task.role)
                            metadataRow(label: "Frequency", value: task.frequency.isEmpty ? "—" : task.frequency)
                            metadataRow(label: "Base date", value: task.rootDate)
                            metadataRow(label: "Next due", value: task.nextDueString,
                                        valueColor: dueColour(task.nextDueString))
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        // Body (read-only)
                        if !task.body.isEmpty {
                            Divider()
                            Text(cleanBody(task.body))
                                .font(.body)
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(20)
                }
            } else {
                VStack {
                    Text("Select a recurring task")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func metadataRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(valueColor)
            Spacer()
        }
    }

    private func dueColour(_ due: String) -> Color {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        if due == "—" { return .secondary }
        if due < today { return .red }
        if due == today { return .orange }
        return .primary
    }

    private func cleanBody(_ raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")
            .filter { !$0.contains("BUTTON[") }
        // Strip leading blank lines and horizontal-rule separators (3+ dashes).
        while !lines.isEmpty {
            let trimmed = lines[0].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || (trimmed.allSatisfy({ $0 == "-" }) && trimmed.count >= 3) {
                lines.removeFirst()
            } else {
                break
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

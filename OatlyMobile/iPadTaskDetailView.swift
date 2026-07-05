//
//  iPadTaskDetailView.swift
//  OatlyMobile (iPad)
//
//  Right pane of the iPad three-pane layout. Shows the selected task's
//  metadata, a status-change button row, and the body text (read-only).
//  Status changes fire an obsidian://adv-uri to mutate frontmatter.
//

import SwiftUI
import UIKit

struct iPadTaskDetailView: View {
    let task: OTTaskJSON

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                Text(task.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // Metadata
                HStack(spacing: 16) {
                    Label(displayRole(task.role), systemImage: "person.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    if let due = task.due {
                        Label(due, systemImage: "calendar")
                            .font(.system(size: 14))
                            .foregroundColor(dueColour(due))
                    }
                    Spacer()
                }

                Divider()

                // Status buttons
                VStack(alignment: .leading, spacing: 8) {
                    Text("Change status")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        statusButton(label: "🔥 Hot",    value: "hot")
                        statusButton(label: "⛅ Warm",   value: "warm")
                        statusButton(label: "❄️ Cool",   value: "cool")
                        statusButton(label: "✅ Done",   value: "done")
                        statusButton(label: "🚫 Dropped", value: "dropped")
                    }
                }

                Divider()

                // Body
                if !task.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(task.body)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else {
                    Text("No body text")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.6))
                        .italic()
                }

                Spacer(minLength: 24)

                // Open in Obsidian
                Button {
                    openInObsidian()
                } label: {
                    Label("Open in Obsidian", systemImage: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(OTPalette.accent)
            }
            .padding(24)
        }
        .background(OTPalette.background)
    }

    // MARK: - Status change

    private func statusButton(label: String, value: String) -> some View {
        Button(label) {
            changeStatus(to: value)
        }
        .buttonStyle(.bordered)
        .tint(OTPalette.accent)
        .font(.system(size: 13, weight: .medium))
    }

    private func changeStatus(to status: String) {
        guard let filepath = task.filepath else { return }
        let encoded = filepath
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filepath
        let urlString = "obsidian://adv-uri?vault=DTObs&filepath=\(encoded)&frontmatterkey=status&data=\(status)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    private func openInObsidian() {
        guard let filepath = task.filepath else { return }
        let encoded = filepath
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filepath
        let urlString = "obsidian://adv-uri?vault=DTObs&filepath=\(encoded)&openmode=true"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Helpers

    private func displayRole(_ role: String) -> String {
        var r = role
        if r.hasPrefix("[[") { r.removeFirst(2) }
        if r.hasSuffix("]]") { r.removeLast(2) }
        return r
    }

    private func dueColour(_ due: String) -> Color {
        OTPalette.dueColor(due)
    }
}

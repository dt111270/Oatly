//
//  TaskStatusValidator.swift
//  Oatly
//
//  Walks 03.01 task notes and flags any whose `status:` field is missing
//  or set to a value outside the canonical five (hot, warm, cool, done,
//  dropped). Used by the Weekly Task Review checklist's "Scan for invalid
//  statuses" step. Deliberately a free helper rather than a TaskStore
//  extension — runs in any window with no coupling to the polled store.
//
//  Mirrors the Python scanner that lived in step 7 of the old Cowork
//  weekly-task-review skill.
//

import Foundation

enum TaskStatusValidator {
    struct Report {
        let filename: String
        /// The invalid value found, or nil if the file has no status field at all.
        let badValue: String?
    }

    static let validStatuses: Set<String> = ["hot", "warm", "cool", "done", "dropped"]

    static let tasksFolder = URL(fileURLWithPath:
        "/Users/davidturnbull/Documents/DTObs/00-09 DTOS/03 Working Folders/03.01 tasks"
    )

    /// Scan all `.md` files in 03.01. Returns one `Report` per offender,
    /// sorted by filename. Returns an empty array when everything is clean.
    static func scan() -> [Report] {
        var flagged: [Report] = []

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tasksFolder,
            includingPropertiesForKeys: nil
        ) else { return flagged }

        // Match `^status:\s*(\S+)` line-by-line. Multi-line anchors mean ^
        // matches start of every line, not just start of string.
        let pattern = try? NSRegularExpression(
            pattern: "^status:\\s*(\\S+)",
            options: [.anchorsMatchLines]
        )

        let sortedFiles = files
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in sortedFiles {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let range = NSRange(content.startIndex..., in: content)
            if let match = pattern?.firstMatch(in: content, options: [], range: range),
               let valueRange = Range(match.range(at: 1), in: content) {
                let raw = String(content[valueRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !validStatuses.contains(raw) {
                    flagged.append(Report(filename: file.lastPathComponent, badValue: raw))
                }
            } else {
                flagged.append(Report(filename: file.lastPathComponent, badValue: nil))
            }
        }

        return flagged
    }
}

//
//  ChecklistLogger.swift
//  Oatly
//
//  Writes the per-checklist log note and appends a one-liner to today's
//  daily note. Triggered by `ChecklistSession.finish()`. All file writes
//  are direct via `FileManager` — no Obsidian MCP, no scripts.
//
//  Output:
//    • {vault}/YYYY-MM-DD {Checklist Title}.md
//        ✅/❌ list of steps, one per line
//    • appended to {vault}/YYYY-MM-DD.md:
//        - *HH:MM* - LOG: [[YYYY-MM-DD {Checklist Title}]]
//
//  Times are in Europe/London.
//

import Foundation

enum ChecklistLogger {
    enum LoggerError: Error {
        case failedToWriteLog(underlying: Error)
        case failedToAppendToDailyNote(underlying: Error)
    }

    /// Vault root. Hard-coded to match TaskStore. If the vault ever moves,
    /// update both in lock-step.
    static let vaultRoot = URL(fileURLWithPath: "/Users/davidturnbull/Documents/DTObs")

    static func writeLog(for session: ChecklistSession) throws {
        let london = TimeZone(identifier: "Europe/London")!
        let now = Date()

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.timeZone = london
        let dateStr = dateFmt.string(from: now)

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.timeZone = london
        let timeStr = timeFmt.string(from: now)

        let logStem = "\(dateStr) \(session.checklist.title)"
        let logURL = vaultRoot.appendingPathComponent("\(logStem).md")
        let dailyURL = vaultRoot.appendingPathComponent("\(dateStr).md")

        // --- Compose log note ---
        let lines = zip(session.checklist.steps, session.stepStatuses).map { step, status -> String in
            let mark: String
            switch status {
            case .done:    mark = "✅"
            case .skipped: mark = "❌"
            case .pending: mark = "⏸" // defensive — shouldn't appear in a finished session
            }
            return "- \(mark) \(step.label)"
        }
        let logContent = lines.joined(separator: "\n") + "\n"

        do {
            try logContent.write(to: logURL, atomically: true, encoding: .utf8)
        } catch {
            throw LoggerError.failedToWriteLog(underlying: error)
        }

        // --- Append to daily note (read-modify-write) ---
        let logLine = "- *\(timeStr)* - LOG: [[\(logStem)]]"

        do {
            var existing = ""
            if FileManager.default.fileExists(atPath: dailyURL.path) {
                existing = (try? String(contentsOf: dailyURL, encoding: .utf8)) ?? ""
            }
            // Ensure exactly one trailing newline before appending the new line.
            let normalised = existing.hasSuffix("\n") || existing.isEmpty
                ? existing
                : (existing + "\n")
            let newContent = normalised + logLine + "\n"
            try newContent.write(to: dailyURL, atomically: true, encoding: .utf8)
        } catch {
            throw LoggerError.failedToAppendToDailyNote(underlying: error)
        }
    }
}

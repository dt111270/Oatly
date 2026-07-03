//
//  TaskParser.swift
//  OT
//
//  Created by David Turnbull on 28/04/2026.
//

import Foundation

struct TaskParser {
    static func parse(fileURL: URL) -> OTTask? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }

        let lines = raw.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }

        // Find the closing ---
        var fmEnd = -1
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                fmEnd = i
                break
            }
        }
        guard fmEnd > 0 else { return nil }

        let fmLines = Array(lines[1..<fmEnd])
        let bodyLines = Array(lines[(fmEnd + 1)...])
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse frontmatter into key/value pairs
        var fm: [String: String] = [:]
        var rawFrontmatter: [(key: String, value: String)] = []
        for line in fmLines {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            fm[key] = value
            rawFrontmatter.append((key: key, value: value))
        }

        // Must have at least a name
        guard let name = fm["name"], !name.isEmpty else { return nil }

        return OTTask(
            id: fileURL,
            fileURL: fileURL,
            name: name,
            status: fm["status"] ?? "cool",
            role: cleanWikilink(fm["role"] ?? ""),
            due: fm["due"],
            source: fm["source"],
            parent: cleanWikilink(fm["parent"] ?? ""),
            nonNnegotiable: fm["non_negotiable"] == "true",
            optional: fm["optional"] == "true",
            created: fm["created"],
            url: fm["url"],
            body: body,
            rawFrontmatter: rawFrontmatter
        )
    }

    // Strips [[ and ]] from wikilinks
    private static func cleanWikilink(_ s: String) -> String {
        s.replacingOccurrences(of: "[[", with: "")
         .replacingOccurrences(of: "]]", with: "")
    }

    /// Parse a recurring task note from `03.02 repeating tasks/`.
    /// Frontmatter keys are read with the same split-on-first-colon approach
    /// as `parse`, which handles the `root date` key with a space correctly.
    static func parseRecurring(fileURL: URL) -> OTRecurringTask? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }

        let lines = raw.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }

        var fmEnd = -1
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                fmEnd = i
                break
            }
        }
        guard fmEnd > 0 else { return nil }

        let fmLines = Array(lines[1..<fmEnd])
        let bodyLines = Array(lines[(fmEnd + 1)...])
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        var fm: [String: String] = [:]
        for line in fmLines {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            fm[key] = value
        }

        guard let name = fm["name"], !name.isEmpty else { return nil }
        guard let rootDate = fm["root date"], !rootDate.isEmpty else { return nil }

        return OTRecurringTask(
            id: fileURL,
            fileURL: fileURL,
            name: name,
            role: cleanWikilink(fm["role"] ?? ""),
            frequency: fm["frequency"] ?? "",
            status: fm["status"] ?? "active",
            nonNegotiable: fm["non_negotiable"] == "true",
            optional: fm["optional"] == "true",
            rootDate: rootDate,
            body: body
        )
    }
    static func updateStatus(fileURL: URL, newStatus: String) {
        guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: "\n")
        let updated = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("status:") {
                return "status: \(newStatus)"
            }
            return line
        }
        content = updated.joined(separator: "\n")

        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    static func updateBody(fileURL: URL, newBody: String) {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: "\n")
        var fmEnd = -1, fmCount = 0
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                fmCount += 1
                if fmCount == 2 { fmEnd = i; break }
            }
        }
        guard fmEnd >= 0 else { return }
        let frontmatter = lines[0...fmEnd].joined(separator: "\n")
        let buttonLine = "`BUTTON[03.01hot]` `BUTTON[03.01warm]` `BUTTON[03.01cool]` `BUTTON[03.01dropped]` `BUTTON[03.01done]`"
        let newContent = newBody.isEmpty
            ? frontmatter + "\n" + buttonLine + "\n"
            : frontmatter + "\n" + buttonLine + "\n\n" + newBody + "\n"
        try? newContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

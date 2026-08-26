import Foundation

/// One Markdown note on disk. Title is the filename without the extension —
/// the folder stays fully Obsidian-compatible (plain .md, no frontmatter).
struct NoteFile: Identifiable, Equatable {
    let url: URL
    var title: String
    var modifiedAt: Date

    var id: String { url.path }
}

/// Pure filename logic, kept separate for testability.
enum NoteNaming {
    /// A title safe to use as a filename: no path separators, no leading
    /// dots, single-line, capped length.
    static func sanitize(_ title: String) -> String {
        var name = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") {
            name.removeFirst()
        }
        // Collapse runs of spaces left by the replacements.
        while name.contains("  ") {
            name = name.replacingOccurrences(of: "  ", with: " ")
        }
        if name.count > 80 {
            name = String(name.prefix(80)).trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? "Untitled" : name
    }

    /// First free URL for a title: "Name.md", then "Name 2.md", "Name 3.md"…
    static func uniqueURL(title: String, in folder: URL) -> URL {
        let base = sanitize(title)
        var candidate = folder.appendingPathComponent(base + ".md")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(counter).md")
            counter += 1
        }
        return candidate
    }

    /// Quick-capture filename: the first line of the text (trimmed to 40
    /// chars) or a timestamped fallback.
    static func captureName(from text: String, now: Date = Date()) -> String {
        let firstLine = text
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if !firstLine.isEmpty {
            return sanitize(String(firstLine.prefix(40)))
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Capture " + formatter.string(from: now)
    }
}

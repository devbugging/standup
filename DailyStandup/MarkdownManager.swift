import Foundation

class MarkdownManager {

    func scanProjects(repoPath: String) -> [String] {
        let projectsDir = (repoPath as NSString).appendingPathComponent("projects")
        let fm = FileManager.default

        guard let items = try? fm.contentsOfDirectory(atPath: projectsDir) else { return [] }

        return items
            .filter { item in
                var isDir: ObjCBool = false
                let path = (projectsDir as NSString).appendingPathComponent(item)
                return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue && !item.hasPrefix(".")
            }
            .sorted()
    }

    func addStandupEntry(repoPath: String, date: String, userName: String, roles: String, content: String) {
        let filePath = "\(repoPath)/projects/standup.md"
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        var lines = readLines(filePath, fallback: "# Standup Notes")
        let dateHeader = "## \(date)"
        let personLines = ["### \(userName) (\(roles))", ""]
            + content.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")

        if let dateIdx = lines.firstIndex(where: { $0 == dateHeader }) {
            // Date exists — find where this section ends (next ## or EOF)
            var insertIdx = dateIdx + 1
            while insertIdx < lines.count {
                if lines[insertIdx].hasPrefix("## ") { break }
                insertIdx += 1
            }
            // Insert person block before next date section
            lines.insert(contentsOf: [""] + personLines + [""], at: insertIdx)
        } else {
            // New date — insert after the title line
            let titleIdx = lines.firstIndex(where: { $0.hasPrefix("# ") }) ?? 0
            lines.insert(contentsOf: ["", dateHeader, ""] + personLines + [""], at: titleIdx + 1)
        }

        writeLines(filePath, lines)
    }

    func addTodoEntry(repoPath: String, date: String, userName: String, roles: String, content: String) {
        let filePath = "\(repoPath)/projects/todo.md"
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        var lines = readLines(filePath, fallback: "# To Do")

        let todoLines = content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line -> String in
                if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") { return line }
                if line.hasPrefix("- ") { return "- [ ] " + String(line.dropFirst(2)) }
                return "- [ ] " + line
            }

        let personLines = ["### \(userName) (\(roles))", ""] + todoLines
        let dateHeader = "## \(date)"

        if let dateIdx = lines.firstIndex(where: { $0 == dateHeader }) {
            var insertIdx = dateIdx + 1
            while insertIdx < lines.count {
                if lines[insertIdx].hasPrefix("## ") { break }
                insertIdx += 1
            }
            lines.insert(contentsOf: [""] + personLines + [""], at: insertIdx)
        } else {
            let titleIdx = lines.firstIndex(where: { $0.hasPrefix("# ") }) ?? 0
            lines.insert(contentsOf: ["", dateHeader, ""] + personLines + [""], at: titleIdx + 1)
        }

        writeLines(filePath, lines)
    }

    // MARK: - Read Todos

    /// Returns all unchecked todo items for the given user (or all ungrouped items).
    func readPendingTodos(repoPath: String, userName: String) -> [String] {
        let filePath = "\(repoPath)/projects/todo.md"
        let lines = readLines(filePath, fallback: "# To Do")

        var results: [String] = []
        var inUserSection = false
        var inUngroupedDateSection = false
        var dateHasPersonHeaders = false
        var currentDate = ""

        // Two-pass: first detect which date sections have person headers
        var datesWithHeaders = Set<String>()
        var activeDate = ""
        for line in lines {
            if line.hasPrefix("## ") && !line.hasPrefix("### ") {
                activeDate = line
            } else if line.hasPrefix("### ") {
                datesWithHeaders.insert(activeDate)
            }
        }

        // Second pass: collect items
        for line in lines {
            if line.hasPrefix("## ") && !line.hasPrefix("### ") {
                currentDate = line
                dateHasPersonHeaders = datesWithHeaders.contains(currentDate)
                inUserSection = false
                inUngroupedDateSection = !dateHasPersonHeaders
            } else if line.hasPrefix("### ") {
                let header = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                inUserSection = header.lowercased().hasPrefix(userName.lowercased())
                inUngroupedDateSection = false
            } else if line.hasPrefix("- [ ] ") {
                if inUserSection || inUngroupedDateSection {
                    let item = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    if !item.isEmpty && !results.contains(item) {
                        results.append(item)
                    }
                }
            }
        }

        return results
    }

    // MARK: - File helpers

    private func readLines(_ path: String, fallback: String) -> [String] {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? fallback
        return text.components(separatedBy: "\n")
    }

    private func writeLines(_ path: String, _ lines: [String]) {
        let result = lines.joined(separator: "\n")
        try? result.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

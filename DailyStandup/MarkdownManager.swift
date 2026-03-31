import Foundation

class MarkdownManager {

    // MARK: - File paths

    /// Returns the filename prefix from the user's name, e.g. "greg" from "Greg"
    private func filePrefix(userName: String) -> String {
        userName.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Returns the path for a standup file.
    /// Project-specific: `projects/{project}/{name}-standup.md`
    /// General: `projects/{name}-standup.md`
    func standupFilePath(repoPath: String, project: String, userName: String) -> String {
        let prefix = filePrefix(userName: userName)
        if project == "General" {
            return "\(repoPath)/projects/\(prefix)-standup.md"
        }
        return "\(repoPath)/projects/\(project)/\(prefix)-standup.md"
    }

    /// Returns the path for a todo file.
    /// Project-specific: `projects/{project}/{name}-todo.md`
    /// General: `projects/{name}-todo.md`
    func todoFilePath(repoPath: String, project: String, userName: String) -> String {
        let prefix = filePrefix(userName: userName)
        if project == "General" {
            return "\(repoPath)/projects/\(prefix)-todo.md"
        }
        return "\(repoPath)/projects/\(project)/\(prefix)-todo.md"
    }

    /// Returns the path for a git activity file.
    /// Project-specific: `projects/{project}/{name}-git.md`
    func gitFilePath(repoPath: String, project: String, userName: String) -> String {
        let prefix = filePrefix(userName: userName)
        return "\(repoPath)/projects/\(project)/\(prefix)-git.md"
    }

    /// Returns the relative path from repoPath for git staging
    func relativeStandupPath(project: String, userName: String) -> String {
        let prefix = filePrefix(userName: userName)
        if project == "General" {
            return "projects/\(prefix)-standup.md"
        }
        return "projects/\(project)/\(prefix)-standup.md"
    }

    func relativeTodoPath(project: String, userName: String) -> String {
        let prefix = filePrefix(userName: userName)
        if project == "General" {
            return "projects/\(prefix)-todo.md"
        }
        return "projects/\(project)/\(prefix)-todo.md"
    }

    func relativeGitPath(project: String, userName: String) -> String {
        let prefix = filePrefix(userName: userName)
        return "projects/\(project)/\(prefix)-git.md"
    }

    // MARK: - Scan projects

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

    // MARK: - Write standup entries (grouped by project)

    /// Writes standup entries to per-project files. Returns the list of relative file paths that were written.
    func addStandupEntries(
        repoPath: String,
        date: String,
        userName: String,
        itemsByProject: [String: [String]]
    ) -> [String] {
        var writtenFiles: [String] = []

        for (project, items) in itemsByProject {
            guard !items.isEmpty else { continue }
            let filePath = standupFilePath(repoPath: repoPath, project: project, userName: userName)
            let bulletLines = items.map { "- \($0)" }

            var lines = readLines(filePath, fallback: "# Standup Notes")
            let dateHeader = "## \(date)"

            if let dateIdx = lines.firstIndex(where: { $0 == dateHeader }) {
                var insertIdx = dateIdx + 1
                while insertIdx < lines.count {
                    if lines[insertIdx].hasPrefix("## ") { break }
                    insertIdx += 1
                }
                lines.insert(contentsOf: [""] + bulletLines, at: insertIdx)
            } else {
                let titleIdx = lines.firstIndex(where: { $0.hasPrefix("# ") }) ?? 0
                lines.insert(contentsOf: ["", dateHeader, ""] + bulletLines, at: titleIdx + 1)
            }

            writeLines(filePath, lines)
            writtenFiles.append(relativeStandupPath(project: project, userName: userName))
        }

        return writtenFiles
    }

    // MARK: - Write todo entries (grouped by project)

    /// Writes todo entries to per-project files. Returns the list of relative file paths that were written.
    func addTodoEntries(
        repoPath: String,
        date: String,
        userName: String,
        itemsByProject: [String: [String]]
    ) -> [String] {
        var writtenFiles: [String] = []

        for (project, items) in itemsByProject {
            guard !items.isEmpty else { continue }
            let filePath = todoFilePath(repoPath: repoPath, project: project, userName: userName)

            let todoLines = items
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { line -> String in
                    if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") { return line }
                    if line.hasPrefix("- ") { return "- [ ] " + String(line.dropFirst(2)) }
                    return "- [ ] " + line
                }

            var lines = readLines(filePath, fallback: "# To Do")
            let dateHeader = "## \(date)"

            if let dateIdx = lines.firstIndex(where: { $0 == dateHeader }) {
                var insertIdx = dateIdx + 1
                while insertIdx < lines.count {
                    if lines[insertIdx].hasPrefix("## ") { break }
                    insertIdx += 1
                }
                lines.insert(contentsOf: [""] + todoLines, at: insertIdx)
            } else {
                let titleIdx = lines.firstIndex(where: { $0.hasPrefix("# ") }) ?? 0
                lines.insert(contentsOf: ["", dateHeader, ""] + todoLines, at: titleIdx + 1)
            }

            writeLines(filePath, lines)
            writtenFiles.append(relativeTodoPath(project: project, userName: userName))
        }

        return writtenFiles
    }

    // MARK: - Write git activity entries

    /// Writes AI-summarized git commit activity to a per-project git.md file.
    /// Returns the relative file path if written, nil otherwise.
    func addGitEntry(
        repoPath: String,
        date: String,
        userName: String,
        project: String,
        bulletPoints: [String]
    ) -> String? {
        guard !bulletPoints.isEmpty else { return nil }
        let filePath = gitFilePath(repoPath: repoPath, project: project, userName: userName)
        let bulletLines = bulletPoints.map { "- \($0)" }

        var lines = readLines(filePath, fallback: "# Git Activity")
        let dateHeader = "## \(date)"

        if let dateIdx = lines.firstIndex(where: { $0 == dateHeader }) {
            var insertIdx = dateIdx + 1
            while insertIdx < lines.count {
                if lines[insertIdx].hasPrefix("## ") { break }
                insertIdx += 1
            }
            lines.insert(contentsOf: [""] + bulletLines, at: insertIdx)
        } else {
            let titleIdx = lines.firstIndex(where: { $0.hasPrefix("# ") }) ?? 0
            lines.insert(contentsOf: ["", dateHeader, ""] + bulletLines, at: titleIdx + 1)
        }

        writeLines(filePath, lines)
        return relativeGitPath(project: project, userName: userName)
    }

    // MARK: - Read pending todos (across all project folders)

    /// Returns all unchecked todo items for this user, scanning all per-user todo files.
    func readPendingTodos(repoPath: String, userName: String) -> [String] {
        let prefix = filePrefix(userName: userName)
        let todoFilename = "\(prefix)-todo.md"
        let projectsDir = "\(repoPath)/projects"
        let fm = FileManager.default

        var results: [String] = []

        // Check general todo file
        let generalPath = "\(projectsDir)/\(todoFilename)"
        results.append(contentsOf: readTodosFromFile(generalPath))

        // Check each project subdirectory
        if let items = try? fm.contentsOfDirectory(atPath: projectsDir) {
            for item in items {
                let dirPath = (projectsDir as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue, !item.hasPrefix(".") else {
                    continue
                }
                let todoPath = (dirPath as NSString).appendingPathComponent(todoFilename)
                if fm.fileExists(atPath: todoPath) {
                    let projectTodos = readTodosFromFile(todoPath)
                        .map { "\(item): \($0)" }
                    results.append(contentsOf: projectTodos)
                }
            }
        }

        return results
    }

    /// Reads all unchecked todo items from a single file. Since files are per-user,
    /// we just collect all `- [ ]` items regardless of section.
    private func readTodosFromFile(_ filePath: String) -> [String] {
        let lines = readLines(filePath, fallback: "")
        var results: [String] = []

        for line in lines {
            if line.hasPrefix("- [ ] ") {
                let item = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !item.isEmpty && !results.contains(item) {
                    results.append(item)
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
        // Ensure parent directory exists
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let result = lines.joined(separator: "\n")
        try? result.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

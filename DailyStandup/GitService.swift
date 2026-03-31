import Foundation

enum GitError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let msg): return "Git error: \(msg)"
        }
    }
}

class GitService {

    @discardableResult
    func run(_ args: [String], in directory: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: directory)

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outData, encoding: .utf8) ?? ""
                let errOutput = String(data: errData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: GitError.failed(errOutput.isEmpty ? output : errOutput))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Checks if a directory is a git repo with a projects/ subdirectory
    func isValidRepo(at path: String) -> Bool {
        let fm = FileManager.default
        let gitDir = (path as NSString).appendingPathComponent(".git")
        let projectsDir = (path as NSString).appendingPathComponent("projects")
        var isDir: ObjCBool = false
        let hasGit = fm.fileExists(atPath: gitDir, isDirectory: &isDir) && isDir.boolValue
        let hasProjects = fm.fileExists(atPath: projectsDir, isDirectory: &isDir) && isDir.boolValue
        return hasGit && hasProjects
    }

    /// Creates a new git repo with the standup structure
    func initializeRepo(at path: String, projectNames: [String]) async throws {
        let fm = FileManager.default
        let projectsDir = (path as NSString).appendingPathComponent("projects")

        // Create root and projects directory
        try fm.createDirectory(atPath: projectsDir, withIntermediateDirectories: true)

        // Create project subdirectories
        for name in projectNames {
            let projectDir = (projectsDir as NSString).appendingPathComponent(name)
            if !fm.fileExists(atPath: projectDir) {
                try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
            }
        }

        // Create .gitignore
        let gitignorePath = (path as NSString).appendingPathComponent(".gitignore")
        if !fm.fileExists(atPath: gitignorePath) {
            try ".DS_Store\n".write(toFile: gitignorePath, atomically: true, encoding: .utf8)
        }

        // Initialize git repo if not already one
        let gitDir = (path as NSString).appendingPathComponent(".git")
        if !fm.fileExists(atPath: gitDir) {
            _ = try await run(["init"], in: path)
        }

        // Stage and commit
        _ = try await run(["add", "."], in: path)
        _ = try await run(["commit", "-m", "Initial standup repository setup"], in: path)
    }

    /// Adds new project directories to an existing repo
    func addProjects(_ names: [String], repoPath: String) throws {
        let fm = FileManager.default
        let projectsDir = (repoPath as NSString).appendingPathComponent("projects")
        for name in names {
            let projectDir = (projectsDir as NSString).appendingPathComponent(name)
            if !fm.fileExists(atPath: projectDir) {
                try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
            }
        }
    }

    func pull(repoPath: String) async throws {
        // Skip pull if there's no remote configured
        let remotes = (try? await run(["remote"], in: repoPath)) ?? ""
        guard !remotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Skip pull if the current branch has no tracking branch
        let tracking = try? await run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: repoPath)
        guard let t = tracking, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        _ = try await run(["pull", "--rebase"], in: repoPath)
    }

    func commitAndPush(repoPath: String, message: String, files: [String]) async throws {
        for file in files {
            _ = try await run(["add", file], in: repoPath)
        }
        _ = try await run(["commit", "-m", message], in: repoPath)

        // Only push if there's a remote and tracking branch
        let remotes = (try? await run(["remote"], in: repoPath)) ?? ""
        guard !remotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let tracking = try? await run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: repoPath)
        guard let t = tracking, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        _ = try await run(["push"], in: repoPath)
    }
}

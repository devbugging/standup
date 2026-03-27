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

    func pull(repoPath: String) async throws {
        _ = try await run(["pull", "--rebase"], in: repoPath)
    }

    func commitAndPush(repoPath: String, message: String, files: [String]) async throws {
        for file in files {
            _ = try await run(["add", file], in: repoPath)
        }
        _ = try await run(["commit", "-m", message], in: repoPath)
        _ = try await run(["push"], in: repoPath)
    }
}

import Foundation
import Combine

enum StandupPhase: Equatable, Hashable {
    case ready
    case recording
    case processing
    case review
    case pushing
    case done
    case error(String)
}

@MainActor
class StandupViewModel: ObservableObject {
    @Published var phase: StandupPhase = .ready
    @Published var projects: [String] = []
    @Published var standupText = ""
    @Published var todoText = ""
    @Published var statusMessage = ""

    let recorder = AudioRecorder()
    private let whisper = WhisperService()
    private let openai = OpenAIService()
    private let git = GitService()
    private let markdown = MarkdownManager()
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Forward recorder changes so SwiftUI re-renders
        recorder.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var dateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        return fmt.string(from: Date())
    }

    func prepare() {
        let settings = AppState.shared.settings
        projects = markdown.scanProjects(repoPath: settings.repoPath)

        Task {
            do {
                statusMessage = "Pulling latest changes..."
                try await git.pull(repoPath: settings.repoPath)
                statusMessage = ""
            } catch {
                statusMessage = "Pull warning: \(error.localizedDescription)"
            }
        }
    }

    func startRecording() {
        do {
            try recorder.startRecording()
            phase = .recording
        } catch {
            phase = .error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func completeRecording() {
        recorder.stopRecording()
        phase = .processing

        Task {
            do {
                try recorder.validateRecording()
                let settings = AppState.shared.settings

                statusMessage = "Transcribing audio..."
                let transcript = try await whisper.transcribe(
                    fileURL: recorder.recordingURL,
                    apiKey: settings.openAIAPIKey
                )

                statusMessage = "Structuring notes with AI..."
                let (standup, todo) = try await openai.structureTranscript(
                    rawText: transcript,
                    projects: projects,
                    userName: settings.userName,
                    userRoles: settings.userRoles
                )

                standupText = standup
                todoText = todo
                statusMessage = ""
                phase = .review
            } catch {
                statusMessage = ""
                phase = .error(error.localizedDescription)
            }
        }
    }

    func confirm() {
        phase = .pushing

        Task {
            do {
                let settings = AppState.shared.settings

                statusMessage = "Pulling latest..."
                try await git.pull(repoPath: settings.repoPath)

                var filesToCommit = [String]()

                // Parse standup text by project and write per-project files
                if !standupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    statusMessage = "Updating standup notes..."
                    let standupByProject = parseStandupByProject(standupText)
                    let standupFiles = markdown.addStandupEntries(
                        repoPath: settings.repoPath,
                        date: dateString,
                        userName: settings.userName,
                        itemsByProject: standupByProject
                    )
                    filesToCommit.append(contentsOf: standupFiles)
                }

                // Parse todo text by project and write per-project files
                if !todoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    statusMessage = "Updating todo list..."
                    let todoByProject = parseTodoByProject(todoText)
                    let todoFiles = markdown.addTodoEntries(
                        repoPath: settings.repoPath,
                        date: dateString,
                        userName: settings.userName,
                        itemsByProject: todoByProject
                    )
                    filesToCommit.append(contentsOf: todoFiles)
                }

                // Fetch git commits for projects with repo locations and write git.md
                statusMessage = "Processing git activity..."
                let gitFiles = await processGitActivity(
                    settings: settings,
                    date: dateString
                )
                filesToCommit.append(contentsOf: gitFiles)

                if !filesToCommit.isEmpty {
                    statusMessage = "Committing and pushing..."
                    try await git.commitAndPush(
                        repoPath: settings.repoPath,
                        message: "standup: \(settings.userName) \(dateString)",
                        files: filesToCommit
                    )
                }

                phase = .done
                statusMessage = ""

                // Invalidate and re-process todo cache since new items were added
                TodoCache.shared.invalidate()
                TodoCache.shared.refreshIfNeeded()
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Git activity processing

    /// For each project that has a local repo path, fetch today's commits and summarize with OpenAI.
    private func processGitActivity(settings: UserSettings, date: String) async -> [String] {
        var gitFiles: [String] = []
        let projectInfos = settings.projects

        for info in projectInfos {
            guard !info.repoURL.isEmpty else { continue }
            let repoDir = info.repoURL

            // Verify the directory exists and is a git repo
            let fm = FileManager.default
            let gitDir = (repoDir as NSString).appendingPathComponent(".git")
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: gitDir, isDirectory: &isDir), isDir.boolValue else { continue }

            do {
                // Get today's commits by this user
                let authorName = settings.userName
                let logOutput = try await git.run(
                    ["log", "--since=\(date) 00:00", "--until=\(date) 23:59",
                     "--author=\(authorName)", "--pretty=format:%s", "--no-merges"],
                    in: repoDir
                )

                let commitMessages = logOutput
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty }

                guard !commitMessages.isEmpty else { continue }

                // Summarize commits with OpenAI
                let bullets = try await summarizeCommits(
                    commitMessages: commitMessages,
                    projectName: info.name,
                    apiKey: settings.openAIAPIKey
                )

                // Write to git.md
                if let relativePath = markdown.addGitEntry(
                    repoPath: settings.repoPath,
                    date: date,
                    userName: settings.userName,
                    project: info.name,
                    bulletPoints: bullets
                ) {
                    gitFiles.append(relativePath)
                }
            } catch {
                print("Git activity for \(info.name): \(error.localizedDescription)")
            }
        }

        return gitFiles
    }

    /// Summarizes raw commit messages into clean bullet points using OpenAI.
    private func summarizeCommits(
        commitMessages: [String],
        projectName: String,
        apiKey: String
    ) async throws -> [String] {
        let numbered = commitMessages.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        let systemPrompt = """
        You summarize git commit messages into clear, concise bullet points describing work done.

        Rules:
        - Group related commits into a single bullet point where it makes sense.
        - Write in past tense, concise (one sentence each).
        - Remove noise like "fix typo", "wip", "merge branch" unless they're the only commits.
        - Return ONLY a JSON array of strings, one per bullet point. No markdown, no code fences.
        - Example: ["Implemented user authentication flow","Fixed pagination bug in dashboard"]
        """

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Project: \(projectName)\n\nCommit messages:\n\(numbered)"]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else { return commitMessages }

        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8),
              let bullets = try? JSONDecoder().decode([String].self, from: jsonData) else {
            // Fallback: use raw commit messages
            return commitMessages
        }

        return bullets
    }

    // MARK: - Parsing helpers

    /// Parses standup text formatted as `- **Project:** description` into a dictionary grouped by project.
    private func parseStandupByProject(_ text: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Match "- **Project:** description"
            if trimmed.hasPrefix("- **"),
               let endBold = trimmed.range(of: ":**") {
                let project = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<endBold.lowerBound])
                let description = String(trimmed[endBold.upperBound...]).trimmingCharacters(in: .whitespaces)
                result[project, default: []].append(description)
            } else {
                // No project tag — goes to General
                let clean = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
                result["General", default: []].append(clean)
            }
        }
        return result
    }

    /// Parses todo text formatted as `Project: description` into a dictionary grouped by project.
    private func parseTodoByProject(_ text: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Match "Project: description"
            if let colonRange = trimmed.range(of: ": ") {
                let project = String(trimmed[..<colonRange.lowerBound])
                let description = String(trimmed[colonRange.upperBound...])
                // Only treat as project if it matches a known project name
                if projects.contains(project) {
                    result[project, default: []].append(description)
                } else {
                    result["General", default: []].append(trimmed)
                }
            } else {
                result["General", default: []].append(trimmed)
            }
        }
        return result
    }

    func reset() {
        phase = .ready
        standupText = ""
        todoText = ""
        statusMessage = ""
        prepare()
    }

}

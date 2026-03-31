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
                        roles: settings.userRoles,
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
                        roles: settings.userRoles,
                        itemsByProject: todoByProject
                    )
                    filesToCommit.append(contentsOf: todoFiles)
                }

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

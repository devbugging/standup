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
    private let transcriber = ElevenLabsService()
    private let git = GitService()
    private let markdown = MarkdownManager()

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
                let apiKey = AppState.shared.settings.elevenLabsAPIKey
                let transcript = try await transcriber.transcribe(
                    fileURL: recorder.recordingURL,
                    apiKey: apiKey
                )
                let (standup, todo) = parseTranscript(transcript)
                standupText = standup
                todoText = todo
                phase = .review
            } catch {
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

                statusMessage = "Updating standup notes..."
                markdown.addStandupEntry(
                    repoPath: settings.repoPath,
                    date: dateString,
                    userName: settings.userName,
                    roles: settings.userRoles,
                    content: standupText
                )

                statusMessage = "Updating todo list..."
                markdown.addTodoEntry(
                    repoPath: settings.repoPath,
                    date: dateString,
                    content: todoText
                )

                statusMessage = "Committing and pushing..."
                var filesToCommit = [String]()
                if !standupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    filesToCommit.append("projects/standup.md")
                }
                if !todoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    filesToCommit.append("projects/todo.md")
                }

                if !filesToCommit.isEmpty {
                    try await git.commitAndPush(
                        repoPath: settings.repoPath,
                        message: "standup: \(settings.userName) \(dateString)",
                        files: filesToCommit
                    )
                }

                phase = .done
                statusMessage = ""
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    func reset() {
        phase = .ready
        standupText = ""
        todoText = ""
        statusMessage = ""
        prepare()
    }

    // MARK: - Transcript Parsing

    private func parseTranscript(_ text: String) -> (standup: String, todo: String) {
        let lower = text.lowercased()
        let todoKeywords = [
            "to do list", "to-do list", "todo list", "to do items",
            "todos:", "to dos:", "for todos", "for to do", "to-dos",
            "to do:", "todo:", "things to do", "still need to"
        ]

        var standupPart = text
        var todoPart = ""

        for keyword in todoKeywords {
            if let range = lower.range(of: keyword) {
                standupPart = String(text[text.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                todoPart = String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        let standupFormatted = formatStandupLines(standupPart)
        let todoFormatted = formatTodoLines(todoPart)

        return (standupFormatted, todoFormatted)
    }

    private func formatStandupLines(_ text: String) -> String {
        let sentences = splitIntoItems(text)
        return sentences.map { sentence in
            if let project = matchProject(sentence) {
                let cleaned = removeProjectMention(sentence, project: project)
                return "- **\(project):** \(cleaned)"
            }
            return "- \(sentence)"
        }.joined(separator: "\n")
    }

    private func formatTodoLines(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        let sentences = splitIntoItems(text)
        return sentences.map { sentence in
            if let project = matchProject(sentence) {
                let cleaned = removeProjectMention(sentence, project: project)
                return "\(project): \(cleaned)"
            }
            return sentence
        }.joined(separator: "\n")
    }

    private func splitIntoItems(_ text: String) -> [String] {
        return text.components(separatedBy: CharacterSet(charactersIn: ".\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func matchProject(_ text: String) -> String? {
        let lower = text.lowercased()
        for project in projects {
            let variations = [
                project.lowercased(),
                project.lowercased().replacingOccurrences(of: " ", with: ""),
                project.lowercased().replacingOccurrences(of: "-", with: " ")
            ]
            for v in variations {
                if lower.contains(v) { return project }
            }
        }
        return nil
    }

    private func removeProjectMention(_ text: String, project: String) -> String {
        var result = text

        let separators = [":", " -", ",", " "]
        for sep in separators {
            let pattern = project + sep
            if let range = result.range(of: pattern, options: .caseInsensitive) {
                result = String(result[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return capitalizeFirst(result)
            }
        }

        // Remove just the project name if at start
        if result.lowercased().hasPrefix(project.lowercased()) {
            result = String(result.dropFirst(project.count)).trimmingCharacters(in: .whitespaces)
            if let first = result.first, ":-,".contains(first) {
                result = String(result.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }

        return capitalizeFirst(result)
    }

    private func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

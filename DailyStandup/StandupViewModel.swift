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
                    userName: settings.userName,
                    roles: settings.userRoles,
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

}

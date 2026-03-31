import Foundation
import Combine

struct ProjectInfo: Codable, Equatable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var description: String = ""
    var repoPaths: [String] = []
    var websiteURL: String = ""
    var fetchGitActivity: Bool = true
}

struct UserSettings: Codable, Equatable {
    var userName: String = ""
    var userRoles: String = ""
    var openAIAPIKey: String = ""
    var selectedMicUID: String = ""
    var notificationHour: Int = 16
    var notificationMinute: Int = 0
    var repoPath: String = ""
    var projects: [ProjectInfo] = []
    var launchAtLogin: Bool = true
    var setupCompleted: Bool = false
}

class AppState: ObservableObject {
    static let shared = AppState()

    @Published var settings: UserSettings {
        didSet { save() }
    }

    private let key = "userSettings"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = UserSettings()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    var isConfigured: Bool {
        settings.setupCompleted
            && !settings.userName.isEmpty
            && !settings.openAIAPIKey.isEmpty
            && !settings.repoPath.isEmpty
    }
}

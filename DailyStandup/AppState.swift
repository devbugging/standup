import Foundation
import Combine

struct UserSettings: Codable, Equatable {
    var userName: String = ""
    var userRoles: String = ""
    var elevenLabsAPIKey: String = ""
    var notificationHour: Int = 16
    var notificationMinute: Int = 0
    var repoPath: String = "/Users/gregorg/Dev/projects"
    var launchAtLogin: Bool = true
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
        !settings.userName.isEmpty && !settings.elevenLabsAPIKey.isEmpty
    }
}

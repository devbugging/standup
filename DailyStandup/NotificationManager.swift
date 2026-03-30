import Foundation
import AppKit

/// Checks the clock every minute and opens the standup window at the configured time.
/// Only triggers once per day.
class NotificationManager {
    static let shared = NotificationManager()

    private var timer: Timer?
    private var lastTriggeredDate: String = ""

    func start() {
        stop()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkTime()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Also check immediately
        checkTime()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call after settings change to pick up new time.
    func reschedule() {
        let s = AppState.shared.settings
        print("Standup window scheduled for \(String(format: "%02d:%02d", s.notificationHour, s.notificationMinute)) daily")
    }

    private func checkTime() {
        let settings = AppState.shared.settings
        guard !settings.userName.isEmpty else { return }

        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let todayString = dateString(now)

        guard hour == settings.notificationHour,
              minute == settings.notificationMinute,
              lastTriggeredDate != todayString else {
            return
        }

        lastTriggeredDate = todayString

        DispatchQueue.main.async {
            WindowManager.shared.showStandup()
            NSSound.beep()
        }
    }

    private func dateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}

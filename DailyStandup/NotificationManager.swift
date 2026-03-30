import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    static let standupActionID = "OPEN_STANDUP"

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            print("Notification permission granted: \(granted)")
        }
    }

    func scheduleDailyReminder(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-standup"])

        let content = UNMutableNotificationContent()
        content.title = "Daily Standup"
        content.body = "Time to record your daily standup update!"
        content.sound = .default
        content.categoryIdentifier = "STANDUP"

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "daily-standup", content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            } else {
                print("Standup reminder scheduled for \(String(format: "%02d:%02d", hour, minute)) daily")
            }
        }

        let openAction = UNNotificationAction(
            identifier: Self.standupActionID,
            title: "Open Standup",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "STANDUP",
            actions: [openAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    /// Fires a test notification in 5 seconds to verify permissions work.
    func sendTestNotification() {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Daily Standup"
        content.body = "Test notification — if you see this, notifications are working!"
        content.sound = .default
        content.categoryIdentifier = "STANDUP"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "test-standup", content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("Test notification failed: \(error)")
            } else {
                print("Test notification scheduled — should appear in 5 seconds")
            }
        }
    }
}

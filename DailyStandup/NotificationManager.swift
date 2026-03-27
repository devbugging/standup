import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    static let standupActionID = "OPEN_STANDUP"

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
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

        center.add(request)

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
}

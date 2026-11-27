import Foundation
import UIKit
import UserNotifications

/// Schedules local reminders at the chosen time.
/// Use By food: 1–3 days before and/or on the day. Best Before food: on the day only (or off).
/// Lock screen actions match the Figma notification designs (Eaten / Frozen / Still good / Delete).
enum ReminderScheduler {
    static let useByCategory = "USE_BY"
    static let bestBeforeCategory = "BEST_BEFORE"

    /// Set when we send the person to the iPhone Settings app to allow notifications.
    /// When they come back and it is allowed, reminders are switched on for them.
    static var enableAfterSettings = false

    static func registerCategories() {
        let eaten = UNNotificationAction(identifier: "EATEN", title: "Eaten", options: [])
        let frozen = UNNotificationAction(identifier: "FROZEN", title: "Frozen", options: [])
        let stillGood = UNNotificationAction(identifier: "STILL_GOOD", title: "Still good", options: [])
        let delete = UNNotificationAction(identifier: "DELETE", title: "Delete", options: [.destructive])
        let useBy = UNNotificationCategory(identifier: useByCategory, actions: [eaten, frozen, delete],
                                           intentIdentifiers: [], options: [])
        let bestBefore = UNNotificationCategory(identifier: bestBeforeCategory, actions: [eaten, stillGood, delete],
                                                intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([useBy, bestBefore])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    static func reschedule(items: [FoodItem], settings: ReminderSettings) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard settings.enabled else { return }

        let calendar = Calendar.current

        // iOS keeps at most 64 pending notifications, so schedule the 60 soonest and refresh on every open.
        var scheduled = 0
        let soonestFirst = items.sorted { $0.expiry < $1.expiry }
        for item in soonestFirst {
            // Which days depends on the date type (see ReminderSettings.dayOffsets)
            for offset in settings.dayOffsets(for: item.dateType) {
                if scheduled >= 60 { break }
                guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: item.expiry)) else { continue }
                var parts = calendar.dateComponents([.year, .month, .day], from: day)
                parts.hour = settings.hour
                parts.minute = settings.minute
                guard let fireDate = calendar.date(from: parts), fireDate > .now else { continue }

                let content = UNMutableNotificationContent()
                content.title = item.name
                content.body = body(for: item, dayOffset: offset)
                content.sound = .default
                content.categoryIdentifier = item.dateType == .useBy ? useByCategory : bestBeforeCategory
                content.userInfo = ["itemID": item.id.uuidString]
                // All reminders for the same morning stack into one group on the lock screen
                // ("Chicken thighs and 3 more"), so several foods never arrive as a pile of separate alerts.
                content.threadIdentifier = "reminders-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
                content.summaryArgument = item.name

                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                let request = UNNotificationRequest(identifier: "\(item.id.uuidString)_\(offset)", content: content, trigger: trigger)
                center.add(request, withCompletionHandler: nil)
                scheduled += 1
            }
        }
    }

    static func body(for item: FoodItem, dayOffset: Int) -> String {
        switch (item.dateType, dayOffset) {
        case (.useBy, 0): "Use by today. Cook it tonight or freeze it."
        case (.useBy, -1): "Use by tomorrow. Plan it into your meals."
        case (.useBy, _): "Use by in \(-dayOffset) days. Plan it into your meals, or freeze it if you won’t get to it."
        case (_, 0): "Best before today. It’s usually still fine, so give it a look before you bin it."
        case (_, -1): "Best before tomorrow. A good one to use up soon."
        default: "Best before in \(-dayOffset) days. A good one to use up soon."
        }
    }
}

/// Receives taps on lock screen notification actions.
nonisolated final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { AppStore.shared.recordDelivered([notification]) }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let idString = response.notification.request.content.userInfo["itemID"] as? String
        let delivered = response.notification
        await MainActor.run {
            AppStore.shared.recordDelivered([delivered])
            guard let idString, let id = UUID(uuidString: idString) else { return }
            if action == UNNotificationDefaultActionIdentifier {
                // Tapping the notification itself opens that food.
                if AppStore.shared.item(with: id) != nil {
                    Router.shared.tab = .home
                    Router.shared.homePath = [.item(id)]
                }
            } else {
                AppStore.shared.handleNotificationAction(action, itemID: id)
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let notificationDelegate = NotificationDelegate()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        ReminderScheduler.registerCategories()
        return true
    }
}

extension AppStore {
    /// Puts reminders that were delivered into the bell list (once each).
    func recordDelivered(_ notifications: [UNNotification]) {
        var added = false
        for n in notifications {
            let content = n.request.content
            guard let idString = content.userInfo["itemID"] as? String, let id = UUID(uuidString: idString),
                  !inbox.contains(where: { $0.requestID == n.request.identifier }) else { continue }
            let type: DateType? = content.categoryIdentifier == ReminderScheduler.useByCategory ? .useBy : .bestBefore
            inbox.append(InboxMessage(title: content.title, body: content.body, date: n.date,
                                      dateType: type, itemID: id, requestID: n.request.identifier))
            added = true
        }
        if added { changed() }
    }

    /// Called when the app opens: reminders that arrived while it was closed.
    func collectDeliveredReminders() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        recordDelivered(delivered)
    }
}

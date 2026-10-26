import Foundation
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

enum AlarmCancellation {
    /// Used by both the app and the island's End intent. IDs also work after app relaunch.
    @MainActor static func cancel(id: UUID) throws {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .authorized {
            if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
                try AlarmManager.shared.cancel(id: id)
            }
        }
        #endif
        let center = UNUserNotificationCenter.current()
        let notificationID = CharacterAlarm.notificationID(id)
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
        var saved = CharacterAlarmSnapshot.load()
        saved.alarms.removeAll { $0.id == id }
        saved.save()
    }
}

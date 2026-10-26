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
            let manager = AlarmManager.shared
            if let alarm = try manager.alarms.first(where: { $0.id == id }) {
                if alarm.state == .alerting { try manager.stop(id: id) }
                if try manager.alarms.contains(where: { $0.id == id }) {
                    do { try manager.cancel(id: id) }
                    catch {
                        // A simultaneous system stop may already have removed it.
                        if try manager.alarms.contains(where: { $0.id == id }) { throw error }
                    }
                }
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

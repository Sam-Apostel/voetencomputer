//
//  ScaleNotifications.swift
//  ScaleSync
//
//  Local notifications for weigh-ins the scale couldn't assign to a profile.
//  Posted from the Bluetooth background wake, so they arrive while the phone
//  is still in a pocket.
//

import Foundation
import UserNotifications

enum ScaleNotifications {

    /// Fixed identifier: a newer unrecognised weigh-in replaces the previous
    /// notification instead of stacking up.
    private static let identifier = "unrecognized-weigh-in"
    nonisolated private static let slotKey = "slot"

    private static let delegate = NotificationDelegate()

    /// Must run at launch: a tap on a notification that cold-starts the app is
    /// only delivered to a delegate that is already installed.
    static func configure() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// - Parameters:
    ///   - slot: the profile the app matched the weigh-in to, or nil if it
    ///     couldn't tell who it was.
    ///   - ownSlot: the profile selected as "My profile" on this phone.
    static func postUnrecognizedWeighIn(weightKg: Double, slot: Int?, ownSlot: Int) {
        let weight = Units.weightString(weightKg)
        let content = UNMutableNotificationContent()
        switch slot {
        case let slot? where slot == ownSlot:
            content.title = "The scale didn't recognise you"
            content.body = "Your weight (\(weight)) is saved, but body composition wasn't measured. Open the app for the 30-second fix."
        case let slot?:
            let name = UserProfiles.displayName(slot: slot)
            content.title = "The scale didn't recognise \(name)"
            content.body = "\(name)'s weight (\(weight)) is saved, but body composition wasn't measured. Open the app for the 30-second fix."
        case nil:
            content.title = "Who just weighed in?"
            content.body = "The scale didn't recognise who weighed \(weight). Open the app to say who it was."
        }
        if let slot {
            content.userInfo = [slotKey: slot]
        }
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    fileprivate nonisolated static func slot(in response: UNNotificationResponse) -> Int? {
        response.notification.request.content.userInfo[slotKey] as? Int
    }
}

/// When the dashboard should offer the "re-save your profile on the scale"
/// steps. Kept in UserDefaults so it survives the app being relaunched in the
/// background between the weigh-in and the user opening it.
enum RecognitionHelp {
    static let timestampKey = "recognitionHelpAt"
    static let slotKey = "recognitionHelpSlot"

    /// Long enough to pick up the phone after stepping off; later than that,
    /// popping up instructions would be out of context.
    static let window: TimeInterval = 60 * 60

    static func request(slot: Int) {
        UserDefaults.standard.set(slot, forKey: slotKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: timestampKey)
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    /// Show the banner even when the app happens to be open — otherwise iOS
    /// drops notifications posted while the app is in the foreground.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Tapping the notification opens the help, however long after the
    /// weigh-in it happens.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let slot = ScaleNotifications.slot(in: response) else { return }
        await MainActor.run { RecognitionHelp.request(slot: slot) }
    }
}

extension ScaleNotifications {
    /// The receipt after a normal weigh-in (DIRECTION.md decision 8): the
    /// phone is usually in a pocket, so this is the app's real first screen.
    /// Replaces the previous one instead of stacking up.
    static func postConfirmation(weightKg: Double, inHealth: Bool, change: String?) {
        let content = UNMutableNotificationContent()
        let weight = Units.weightString(weightKg)
        content.body = [inHealth ? "\(weight), in Apple Health." : "\(weight), saved.", change]
            .compactMap { $0 }
            .joined(separator: " ")
        content.interruptionLevel = .passive
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "weigh-in-receipt", content: content, trigger: nil))
    }
}

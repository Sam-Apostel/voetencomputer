//
//  ShakeGesture.swift
//  ScaleSync
//
//  SwiftUI has no shake gesture; UIKit reports shakes to the responder chain,
//  which ends at the window.
//

import UIKit

extension UIDevice {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShake, object: nil)
        }
    }
}

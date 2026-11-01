//
//  LoginItem.swift
//  NetBar
//
//  Launch at login, through SMAppService.
//
//  Registration is reversible and lives in the system's own login items list, so
//  NetBar shows up in System Settings alongside everything else the user starts at
//  login. A build directory cannot be registered: macOS wants a real bundle, and
//  the call throws instead of silently doing nothing.
//

import Foundation
import ServiceManagement

enum LoginItem {
    /// Whether macOS will start NetBar at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Turns launch at login on or off. Returns NO when macOS refused, which is
    /// what a build directory gets.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return isEnabled == enabled
        } catch {
            NSLog("NetBar: launch at login could not be changed: \(error)")
            return false
        }
    }

    /// Turns launch at login on the first time the app ever runs, so a fresh
    /// install starts at login without anyone hunting for a switch. The decision
    /// is recorded, so turning it off in the panel sticks.
    static func registerOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: configuredKey) else { return }
        defaults.set(true, forKey: configuredKey)
        setEnabled(true)
    }

    private static let configuredKey = "NBLoginItemConfigured"
}

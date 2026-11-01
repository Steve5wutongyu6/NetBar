//
//  AccessibilityPermission.swift
//  NetBar
//
//  The Accessibility grant the system Wi-Fi menu needs.
//
//  Two things make this worth its own type. macOS keys the grant to the binary's
//  code signature, so an ad-hoc signed build presents a new identity after every
//  update and the old grant no longer matches; and the answer can change while
//  NetBar runs, so callers re-read it rather than caching the launch-time answer.
//

import Foundation

enum AccessibilityPermission {
    /// Whether macOS currently lets NetBar drive other apps' interfaces.
    static var isGranted: Bool {
        NBSystemWiFiMenu.isPermitted()
    }

    /// Asks macOS to show its prompt, at most once per version.
    ///
    /// Asking on every launch is what makes a missing grant feel like nagging,
    /// and after an update the new signature would prompt again even though the
    /// user already answered. One ask per version, then the panel row carries the
    /// explanation.
    static func askOnceForThisVersion() {
        guard !isGranted else { return }
        let defaults = UserDefaults.standard
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        guard defaults.string(forKey: askedVersionKey) != version else { return }
        defaults.set(version, forKey: askedVersionKey)
        _ = NBSystemWiFiMenu.requestPermission()
    }

    /// Opens the pane that holds the grant.
    static func openSettings() {
        NBSystemWiFiMenu.openAccessibilitySettings()
    }

    /// Where the app lives, which is what the user has to find in that list. Shown
    /// in the panel because a copy in a build folder and a copy in /Applications
    /// are two different grants.
    static var bundlePath: String {
        Bundle.main.bundlePath
    }

    private static let askedVersionKey = "NBAccessibilityAskedVersion"
}

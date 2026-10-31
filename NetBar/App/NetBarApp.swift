//
//  NetBarApp.swift
//  NetBar
//
//  The app owns no scenes: everything it shows lives in the status item's panel,
//  which `AppDelegate` builds. `Settings` has to be declared to satisfy `App`,
//  and stays empty because NetBar has nothing to configure.
//

import SwiftUI

@main
struct NetBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

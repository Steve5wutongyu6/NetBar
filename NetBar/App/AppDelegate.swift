//
//  AppDelegate.swift
//  NetBar
//
//  NetBar is an accessory: no Dock tile, no windows of its own, one status item.
//  It can also run against a fixture, which is how the render tests and the
//  snapshot mode drive the exact same views without a radio.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        switch LaunchOptions.current {
        case .snapshot(let fixture, let destination):
            // Rendering mode: produce the image, then leave.
            do {
                try SnapshotRenderer.render(fixture: fixture, to: destination)
                FileHandle.standardOutput.write(Data("wrote \(destination.path)\n".utf8))
                NSApp.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
                exit(1)
            }
        case .fixture(let fixture):
            start(source: .fixture(fixture))
        case .live:
            start(source: .live)
        }
    }

    private func start(source: WiFiStore.Source) {
        let store = WiFiStore(source: source)
        let controller = MenuBarController(store: store)
        self.controller = controller
        controller.start()
    }
}

/// Command line the app understands.
enum LaunchOptions {
    case live
    case fixture(URL)
    case snapshot(fixture: URL, destination: URL)

    static var current: LaunchOptions {
        let arguments = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
                return nil
            }
            return arguments[index + 1]
        }
        let fixture = value(after: "--fixture").map { URL(fileURLWithPath: $0) }
        if let destination = value(after: "--snapshot") {
            return .snapshot(
                fixture: fixture ?? URL(fileURLWithPath: "NetBarTests/Fixtures/sample.json"),
                destination: URL(fileURLWithPath: destination)
            )
        }
        if let fixture {
            return .fixture(fixture)
        }
        return .live
    }
}

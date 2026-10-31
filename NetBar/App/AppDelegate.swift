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
        // The test bundle is hosted inside this app, so the tests would otherwise
        // add a status item and trigger the Location prompt on the tester's Mac.
        guard !Self.isRunningTests else { return }
        NSApp.setActivationPolicy(.accessory)

        switch LaunchOptions.current {
        case .scanDump(let destination):
            exit(Diagnostics.writeScanDump(to: destination))
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

        guard case .live = source else { return }
        // macOS reveals network names only to an authorized app, and it only
        // lists an app that asked. Asking at launch is what makes the menu show
        // names instead of a privacy row; after the first answer it is silent.
        store.requestNameAccess()
    }
}

extension AppDelegate {
    /// YES when the process is a test host rather than the running app.
    /// Whether this process is a test host. Checked before the app starts its
    /// status item or asks for Location: a test run must not prompt for
    /// privacy, and it must not hang waiting for an answer.
    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        if environment.keys.contains(where: { $0.hasPrefix("XCTest") || $0.hasPrefix("XCInject") }) {
            return true
        }
        if let injected = environment["DYLD_INSERT_LIBRARIES"], injected.contains(".xctest") {
            return true
        }
        if CommandLine.arguments.contains(where: { $0.hasPrefix("-XCTest") || $0.contains(".xctest") }) {
            return true
        }
        if NSClassFromString("XCTestCase") != nil {
            return true
        }
        return Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
    }
}

/// Command line the app understands.
enum LaunchOptions {
    case live
    case fixture(URL)
    case snapshot(fixture: URL, destination: URL)
    case scanDump(destination: String)

    static var current: LaunchOptions {
        let arguments = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
                return nil
            }
            return arguments[index + 1]
        }
        if let destination = value(after: "--scan-dump") {
            return .scanDump(destination: destination)
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

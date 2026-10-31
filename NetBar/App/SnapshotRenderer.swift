//
//  SnapshotRenderer.swift
//  NetBar
//
//  Draws the menu into a PNG without showing it. CI renders a fixture this way
//  and keeps the image as an artifact, so a layout change is visible in a build
//  without anyone opening the app.
//

import AppKit
import SwiftUI

enum SnapshotRenderer {
    enum Failure: Error {
        case fixtureUnreadable(URL)
        case encodingFailed(URL)
        /// The view hierarchy produced no bitmap at all.
        case renderingFailed
    }

    /// Renders the panel for `fixture` and writes a PNG to `destination`.
    @MainActor
    static func render(fixture: URL, to destination: URL) throws {
        let store = WiFiStore(source: .fixture(fixture))
        store.loadFixtureSynchronously()
        guard !store.output.items.isEmpty else { throw Failure.fixtureUnreadable(fixture) }

        let image = try image(for: store)
        guard let data = image.representation(using: .png, properties: [:]) else {
            throw Failure.encodingFailed(destination)
        }
        try data.write(to: destination)
    }

    /// The rendered panel as an `NSBitmapImageRep`.
    @MainActor
    static func image(for store: WiFiStore) throws -> NSBitmapImageRep {
        let canvas = SnapshotCanvas(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: 240))
        // A fixed appearance keeps the artifact comparable across runs.
        canvas.appearance = NSAppearance(named: .aqua)

        let host = NSHostingView(rootView: MenuPanelView(store: store))
        host.appearance = canvas.appearance
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        canvas.addSubview(host)
        canvas.frame = NSRect(origin: .zero, size: size)
        canvas.layoutSubtreeIfNeeded()

        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds),
              rep.pixelsWide > 0, rep.pixelsHigh > 0 else {
            throw Failure.renderingFailed
        }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        return rep
    }
}

/// Fills the area behind the panel so the PNG has no transparent holes where
/// the menu's material would sample the desktop.
private final class SnapshotCanvas: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

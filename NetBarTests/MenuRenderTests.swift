//
//  MenuRenderTests.swift
//  NetBarTests
//
//  The panel is laid out off screen here, which is what CI uploads as an
//  artifact: a layout change shows up as a different image without anyone
//  opening the app.
//

import AppKit
import Foundation
import Testing

@testable import NetBar

@MainActor
private let fixturesDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

@MainActor
private func renderedStore(_ name: String) -> WiFiStore {
    let store = WiFiStore(source: .fixture(fixturesDirectory.appendingPathComponent(name)))
    store.loadFixtureSynchronously()
    return store
}

@MainActor
private func pngData(_ store: WiFiStore) -> Data? {
    SnapshotRenderer.image(for: store).representation(using: .png, properties: [:])
}

@MainActor
@Test("The panel renders the sample capture as a PNG")
func sampleRenders() throws {
    let store = renderedStore("sample.json")
    let image = SnapshotRenderer.image(for: store)

    #expect(image.pixelsWide > 0)
    #expect(image.pixelsHigh > 0)
    // A menu is wider than it is tall.
    #expect(CGFloat(image.pixelsWide) / CGFloat(image.pixelsHigh) > 1)
    let data = try #require(pngData(store))
    #expect(data.count > 2_000)
    // PNG signature, so a truncated write cannot pass as success.
    #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
}

@MainActor
@Test("The rendered panel is taller when it lists more")
func moreRowsAreTaller() {
    let sample = SnapshotRenderer.image(for: renderedStore("sample.json"))

    let bare = NBEngineInput()
    bare.powerOn = true
    bare.interfaceName = "en0"
    let quiet = WiFiStore(source: .live)
    quiet.applyForTesting(bare)

    let quietImage = SnapshotRenderer.image(for: quiet)
    #expect(sample.pixelsHigh > quietImage.pixelsHigh)
}

@MainActor
@Test("The rendered panel is not blank")
func renderIsNotBlank() throws {
    let image = SnapshotRenderer.image(for: renderedStore("sample.json"))
    let width = image.pixelsWide
    let height = image.pixelsHigh
    var distinct = Set<UInt32>()
    for y in stride(from: 0, to: height, by: 3) {
        for x in stride(from: 0, to: width, by: 3) {
            guard let colour = image.colorAt(x: x, y: y) else { continue }
            let packed = UInt32(colour.redComponent * 255) << 16
                | UInt32(colour.greenComponent * 255) << 8
                | UInt32(colour.blueComponent * 255)
            distinct.insert(packed)
            if distinct.count > 4 { break }
        }
        if distinct.count > 4 { break }
    }
    // A menu with rows, text and glyphs never renders as one flat colour.
    #expect(distinct.count > 4)
}

@MainActor
@Test("Writing a snapshot to disk produces a readable file")
func snapshotWritesToDisk() throws {
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("netbar-snapshot-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: destination) }

    try SnapshotRenderer.render(fixture: fixturesDirectory.appendingPathComponent("sample.json"),
                               to: destination)

    let data = try Data(contentsOf: destination)
    #expect(data.count > 2_000)
    let image = try #require(NSBitmapImageRep(data: data))
    #expect(image.pixelsWide >= Int(MenuMetrics.width))
}

@MainActor
@Test("The bars glyph is a template image at menu size")
func barsGlyphIsATemplate() {
    for strength in 0...4 {
        let image = WiFiIcon.bars(strength: strength)
        #expect(image.isTemplate)
        #expect(image.size.width == WiFiIcon.boxSize)
        #expect(image.size.height == WiFiIcon.boxSize)
    }
}

@MainActor
@Test("Out of range strengths clamp instead of trapping")
func barsClamp() {
    let low = WiFiIcon.bars(strength: -3)
    let high = WiFiIcon.bars(strength: 9)
    #expect(low.size == high.size)
    #expect(low.size.width == WiFiIcon.boxSize)
}

@MainActor
@Test("The status glyph switches to a phone while an Apple hotspot is joined")
func statusGlyphReflectsHotspot() {
    #expect(WiFiIcon.statusSymbol(isHotspot: true, powerOn: true, strength: 4) != nil)
    #expect(WiFiIcon.statusSymbol(isHotspot: false, powerOn: true, strength: 4) != nil)
    #expect(WiFiIcon.statusSymbol(isHotspot: false, powerOn: false, strength: 0) != nil)
}

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
private func pngData(_ store: WiFiStore) throws -> Data? {
    try SnapshotRenderer.image(for: store).representation(using: .png, properties: [:])
}

@MainActor
@Test("The panel renders the sample capture as a PNG")
func sampleRenders() async throws {
    let store = renderedStore("sample.json")
    let image = try SnapshotRenderer.image(for: store)

    #expect(image.pixelsWide > 0)
    #expect(image.pixelsHigh > 0)
    // A menu is wider than it is tall.
    #expect(CGFloat(image.pixelsWide) / CGFloat(image.pixelsHigh) > 1)
    let png = try pngData(store)
    let data = try #require(png)
    #expect(data.count > 2_000)
    // PNG signature, so a truncated write cannot pass as success.
    #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
}

@MainActor
@Test("The rendered panel is taller when it lists more")
func moreRowsAreTaller() throws {
    let sample = try SnapshotRenderer.image(for: renderedStore("sample.json"))

    let bare = NBEngineInput()
    bare.powerOn = true
    bare.interfaceName = "en0"
    let quiet = WiFiStore(source: .live)
    quiet.applyForTesting(bare)

    let quietImage = try SnapshotRenderer.image(for: quiet)
    #expect(sample.pixelsHigh > quietImage.pixelsHigh)
}

@MainActor
@Test("A hairline divides each kind of network, and nothing else")
func sectionsAreSeparated() throws {
    let store = renderedStore("sample.json")
    let items = store.output.items
    let offsets = MenuRowPlanner.separatorOffsets(in: items)

    // The sample menu is hotspot -> known -> other -> footer.
    let sections = items.map(\.section)
    #expect(Set(sections) == [.hotspot, .known, .other, .footer])

    for offset in offsets {
        #expect(items[offset].section != items[offset - 1].section)
        #expect(items[offset].role != .settings)
    }
    // One rule between hotspot and known, one between known and other.
    #expect(offsets.count == 2)
    let transitionOffsets = items.indices.dropFirst().filter { items[$0].section != items[$0 - 1].section }
    #expect(offsets == Set(transitionOffsets.filter { items[$0].role != .settings }))
}

@MainActor
@Test("Unfolding the strangers makes the rendered menu taller")
func unfoldingGrowsTheMenu() async throws {
    let store = renderedStore("sample.json")
    let folded = try SnapshotRenderer.image(for: store).pixelsHigh
    await store.setRevealsOther(true)
    let expanded = try SnapshotRenderer.image(for: store).pixelsHigh
    // The panel re-fits to its content, so the rows must actually take more room.
    #expect(expanded > folded)
}

@MainActor
@Test("The rendered panel is not blank")
func renderIsNotBlank() async throws {
    let image = try SnapshotRenderer.image(for: renderedStore("sample.json"))
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
@Test("Both signal glyphs are template images with a usable size")
func glyphsAreTemplateImages() {
    for strength in 0...WiFiIcon.levels {
        for image in [WiFiIcon.wifi(strength: strength), WiFiIcon.cellular(strength: strength)] {
            #expect(image.isTemplate)
            // Symbols draw inside their own padded box, so only the floor matters.
            #expect(image.size.width >= WiFiIcon.boxSize)
            #expect(image.size.height >= WiFiIcon.boxSize)
        }
    }
}

@MainActor
@Test("Out of range strengths clamp instead of trapping")
func glyphsClamp() {
    #expect(WiFiIcon.wifi(strength: -3).size == WiFiIcon.wifi(strength: 0).size)
    #expect(WiFiIcon.cellular(strength: 9).size == WiFiIcon.cellular(strength: 4).size)
}

@MainActor
@Test("Wi-Fi and Cellular are different glyphs, and a hotspot never looks like Wi-Fi")
func hotspotGlyphDiffersFromWiFi() {
    let wifi = WiFiIcon.statusGlyph(isHotspot: false, powerOn: true, strength: 4)
    let hotspot = WiFiIcon.statusGlyph(isHotspot: true, powerOn: true, strength: 4)
    #expect(wifi != nil)
    #expect(hotspot != nil)
    #expect(wifi?.tiffRepresentation != hotspot?.tiffRepresentation)
    #expect(WiFiIcon.statusGlyph(isHotspot: false, powerOn: false, strength: 0) != nil)
}

@MainActor
@Test("A stronger signal draws a fuller glyph")
func strongerSignalIsNotTheSameDrawing() {
    #expect(WiFiIcon.cellular(strength: 1).tiffRepresentation
        != WiFiIcon.cellular(strength: 4).tiffRepresentation)
    // `wifi` has three fill levels, so its four strengths collapse to three.
    #expect(WiFiIcon.wifi(strength: 1).tiffRepresentation
        != WiFiIcon.wifi(strength: 3).tiffRepresentation)
}

/// Draws every glyph large enough to inspect, and writes the sheet to
/// /tmp/netbar-glyphs.png. Shapes are geometry, so they are worth looking at.
@MainActor
@Test("Glyph sheet renders for inspection")
func glyphSheet() throws {
    let scale = 10
    let cell = Int(WiFiIcon.boxSize) * scale
    let gap = 12
    let glyphs = (0...WiFiIcon.levels).map { WiFiIcon.wifi(strength: $0) }
        + (0...WiFiIcon.levels).map { WiFiIcon.cellular(strength: $0) }
    let width = glyphs.count * cell + (glyphs.count + 1) * gap
    let height = cell + gap * 2

    let context = try #require(CGContext(data: nil, width: width, height: height,
                                         bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .none
    context.setFillColor(NSColor.black.cgColor)

    for (index, image) in glyphs.enumerated() {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
        let x = gap + index * (cell + gap)
        context.draw(cgImage, in: CGRect(x: x, y: gap, width: cell, height: cell))
    }
    let output = try #require(context.makeImage())
    let rep = NSBitmapImageRep(cgImage: output)
    let data = try #require(rep.representation(using: .png, properties: [:]))
    try data.write(to: URL(fileURLWithPath: "/tmp/netbar-glyphs.png"))
}

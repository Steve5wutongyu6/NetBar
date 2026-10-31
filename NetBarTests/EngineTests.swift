//
//  EngineTests.swift
//  NetBarTests
//
//  The app's half of the engine contract: fixtures in, menu out, decoded by the
//  same code the panel uses.
//

import Foundation
import Testing

@testable import NetBar

/// Fixtures live next to this file, in the repository checkout.
@MainActor
private let fixturesDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

@MainActor
private func fixture(_ name: String) -> URL {
    fixturesDirectory.appendingPathComponent(name)
}

@MainActor
private func storedFixture(_ name: String) -> WiFiStore {
    let store = WiFiStore(source: .fixture(fixturesDirectory.appendingPathComponent(name)))
    store.loadFixtureSynchronously()
    return store
}

@MainActor
private func store(_ fixture: URL) -> WiFiStore {
    let store = WiFiStore(source: .fixture(fixture))
    store.loadFixtureSynchronously()
    return store
}

@MainActor
private func rows(_ output: NBEngineOutput, _ section: NBItemSection) -> [NBEngineItem] {
    output.items.filter { $0.section == section && $0.role == .network }
}

@MainActor
@Test("The sample capture renders hotspots, known networks and folded strangers")
func sampleFixtureRendersExpectedMenu() throws {
    let output = store(fixture("sample.json")).output

    #expect(output.statusTitle == nil)
    #expect(output.statusNeedsSetup == false)
    #expect(output.connectedIsHotspot)
    #expect(output.connectedCell == .LTE)
    #expect(output.connectedBattery == 64)
    #expect(output.connectedStrength == 4)
    #expect(output.hiddenOtherCount == 3)

    #expect(output.items.map(\.identifier) == [
        "header.hotspot",
        "hotspot.吴同宇的iPhone",
        "header.known",
        "known.自习室 3",
        "known.自习室 2",
        "other.row",
        "other.Test&Co",
        "other.A\"quoted\"Net",
        "footer.settings",
    ])

    let hotspot = try #require(rows(output, .hotspot).first)
    #expect(hotspot.isJoined)
    #expect(hotspot.detailKind == .appleHotspot)
    #expect(hotspot.cell == .LTE)
    #expect(hotspot.battery == 64)
    #expect(hotspot.strength == 4)
    #expect(rows(output, .known).count == 2)
    #expect(rows(output, .other).count == 2)

    let footer = try #require(output.items.last)
    #expect(footer.role == .settings)
    #expect(footer.title == "Wi-Fi Settings\u{2026}")
}

@MainActor
@Test("A joined iPhone hotspot shows signal, Cellular and battery instead of a lock")
func joinedHotspotUsesHotspotDetail() throws {
    let output = store(fixture("sample.json")).output
    let hotspot = try #require(rows(output, .hotspot).first)

    // The point of the whole app: no link badge on a Personal Hotspot row.
    #expect(hotspot.detailKind == .appleHotspot)
    #expect(hotspot.detailKind != .lock)
    // Never a duplicate row: the hotspot is the joined network, listed once.
    let joined = output.items.filter(\.isJoined)
    #expect(joined.count == 1)
    #expect(joined.first?.identifier == hotspot.identifier)
}

@MainActor
@Test("A locked known network keeps its lock badge")
func lockedNetworkKeepsLock() throws {
    let output = store(fixture("sample.json")).output
    let known = rows(output, .known)
    #expect(known.allSatisfy { $0.detailKind == .lock })
}

@MainActor
@Test("Continuity reports reach the hotspot row")
func continuityReportsReachTheRow() throws {
    let input = NBEngineInput()
    input.powerOn = true
    input.interfaceName = "en0"
    input.currentSSID = "Phone"
    input.currentRSSI = -55
    input.currentIsPersonalHotspot = true

    let peer = NBHotspotPeerInfo()
    peer.name = "Phone"
    peer.batteryPercent = 75
    peer.networkLabel = "5G"
    peer.signalBars = 3
    input.peers = [peer]

    let output = EngineBridge.render(input)
    #expect(output.connectedCell == .fiveG)
    #expect(output.connectedBattery == 75)
    let hotspot = try #require(output.items.first { $0.section == .hotspot && $0.role == .network })
    #expect(hotspot.cell == .fiveG)
    #expect(hotspot.battery == 75)
    #expect(hotspot.cellularSignal == 3)
    #expect(hotspot.detailKind == .appleHotspot)
}

@MainActor
@Test("A capture carries what the radio knows about the joined hotspot")
func snapshotCarriesConnectedHotspotFacts() throws {
    let snapshot = NBSnapshot()
    snapshot.powerOn = true
    snapshot.interfaceName = "en0"
    snapshot.currentRSSI = -55
    snapshot.currentSSID = "Phone"
    snapshot.currentIsPersonalHotspot = true
    snapshot.currentIsApplePersonalHotspot = true
    snapshot.currentHotspotNetwork = .network5G
    snapshot.currentHotspotBattery = 73
    snapshot.networks = []

    let input = WiFiStore.input(from: snapshot, preferred: [])
    #expect(input.currentIsPersonalHotspot)
    #expect(input.currentHotspotNetwork == .network5G)
    #expect(input.currentHotspotBattery == 73)

    // The engine turns those into a hotspot row even though the scan is empty.
    let output = EngineBridge.render(input)
    #expect(output.connectedIsHotspot)
    #expect(output.connectedCell == .fiveG)
    #expect(output.connectedBattery == 73)
    let hotspot = output.items.filter { $0.section == .hotspot && $0.role == .network }
    #expect(hotspot.count == 1)
    #expect(hotspot.first?.isJoined == true)
    #expect(hotspot.first?.detailKind == .appleHotspot)
}

@MainActor
@Test("A capture whose names macOS withheld still lists the joined network")
func redactedFixtureKeepsJoinedSlot() throws {
    let output = store(fixture("redacted.json")).output

    #expect(output.connectedName == nil)
    #expect(rows(output, .hotspot).first?.cell == .fiveG)
    #expect(rows(output, .hotspot).first?.battery == 38)

    let known = rows(output, .known)
    let first = try #require(known.first)
    #expect(first.identifier == "known.redacted")
    #expect(first.redacted)
    #expect(first.isJoined)
    #expect(first.title == "Not Nearby")
}

@MainActor
@Test("With network names hidden, a nearby hotspot still gets a detailed row")
func hiddenNamesKeepHotspotsVisible() throws {
    // This is what an unsigned build sees: macOS redacts every name, but the
    // hotspot beacons still describe themselves.
    let output = store(fixture("hidden-names.json")).output

    let hotspot = try #require(rows(output, .hotspot).first)
    #expect(hotspot.title == "Not Nearby")
    #expect(hotspot.redacted)
    #expect(hotspot.detailKind == .appleHotspot)
    #expect(hotspot.cell == .fiveG)
    #expect(hotspot.battery == 88)
    #expect(hotspot.strength == 3)
    // Unnamed strangers without a saved profile cannot be listed.
    #expect(rows(output, .other).isEmpty)
}

@MainActor
@Test("With the radio off only the settings row remains")
func powerOffCollapsesTheMenu() {
    let input = NBEngineInput()
    input.powerOn = false
    input.interfaceName = "en0"
    let output = EngineBridge.render(input)
    #expect(output.statusTitle == "Wi-Fi Off")
    #expect(output.items.count == 1)
    #expect(output.items.first?.role == .settings)
}

@MainActor
@Test("Malformed engine input yields an empty menu rather than a crash")
func malformedInputIsContained() {
    let output = EngineBridge.render(NBEngineInput())
    // No power, so no networks; the footer is the UI's own row.
    #expect(output.items.allSatisfy { $0.role != .network })
}

@MainActor
@Test("The engine reports its version")
func engineVersionIsReported() {
    #expect(EngineBridge.version.hasPrefix("netbar_engine/"))
}

@MainActor
@Test("A CoreWLAN capture becomes an engine request without losing detail")
func snapshotMapsToEngineInput() throws {
    let snapshot = NBSnapshot()
    snapshot.interfaceName = "en0"
    snapshot.powerOn = true
    snapshot.currentRSSI = -64
    snapshot.currentSSID = "吴同宇的iPhone"
    snapshot.namesAvailable = true

    let hotspot = NBScannedNetwork()
    hotspot.ssid = "吴同宇的iPhone"
    hotspot.serviceName = "Home"
    hotspot.rssi = -64
    hotspot.security = .WPA2
    hotspot.phyMode = .mode80211ax
    hotspot.channel = 36
    hotspot.known = true
    hotspot.personalHotspot = true
    hotspot.hotspotNetwork = .network5G
    hotspot.hotspotBattery = 55

    let stranger = NBScannedNetwork()
    stranger.ssid = "Cafe"
    stranger.rssi = -70
    snapshot.networks = [hotspot, stranger]

    let input = WiFiStore.input(from: snapshot, preferred: ["Home", "Study"])

    #expect(input.powerOn)
    #expect(input.currentSSID == "吴同宇的iPhone")
    #expect(input.connectedNameRedacted == false)
    #expect(input.currentRSSI == -64)
    #expect(input.interfaceName == "en0")
    #expect(input.preferredNetworks == ["Home", "Study"])
    #expect(input.networks.count == 2)

    let mapped = try #require(input.networks.first)
    #expect(mapped.serviceName == "Home")
    #expect(mapped.security == .WPA2)
    #expect(mapped.phyMode == .mode80211ax)
    #expect(mapped.channel == 36)
    #expect(mapped.personalHotspot)
    #expect(mapped.hotspotNetwork == .network5G)
    #expect(mapped.hotspotBattery == 55)
}

@MainActor
@Test("A redacted capture is reported as a hidden connection")
func redactedCaptureSetsTheFlag() {
    let snapshot = NBSnapshot()
    snapshot.powerOn = true
    snapshot.currentSSID = nil
    snapshot.currentRSSI = -58
    snapshot.namesAvailable = false
    snapshot.networks = []

    let input = WiFiStore.input(from: snapshot, preferred: [])
    #expect(input.connectedNameRedacted)

    // An idle radio is not a hidden connection.
    snapshot.currentRSSI = 0
    #expect(WiFiStore.input(from: snapshot, preferred: []).connectedNameRedacted == false)
}

@MainActor
@Test("Re-rendering keeps the list the last scan produced")
func rerenderKeepsTheScan() throws {
    let store = storedFixture("sample.json")
    let before = store.output.items.count
    #expect(before > 1)

    // Unfolding is a view change: same capture, more rows.
    store.revealsOther = true
    #expect(store.output.items.count >= before)
    store.revealsOther = false
    #expect(store.output.items.count == before)
}

@MainActor
@Test("Unfolding the Other Networks row reveals the rest")
func revealOtherExpands() throws {
    let input = NBEngineInput()
    input.powerOn = true
    input.interfaceName = "en0"
    input.networks = (0..<6).map { index in
        let network = NBEngineNetwork()
        network.ssid = "Guest\(index)"
        network.rssi = -40 - Int(index) * 8
        return network
    }

    let folded = EngineBridge.render(input)
    #expect(folded.hiddenOtherCount > 0)
    let visibleFolded = rows(folded, .other).count

    input.revealOther = true
    let expanded = EngineBridge.render(input)
    #expect(expanded.hiddenOtherCount == 0)
    #expect(rows(expanded, .other).count > visibleFolded)
}

@MainActor
@Test("Menu rows decode every field the panel draws")
func itemFieldsSurviveDecoding() throws {
    let input = NBEngineInput()
    input.powerOn = true
    input.interfaceName = "en0"
    let network = NBEngineNetwork()
    network.ssid = "Desk"
    network.rssi = -55
    network.security = .WPA3
    input.networks = [network]

    let item = try #require(EngineBridge.render(input).items.first { $0.role == .network })
    #expect(item.ssid == "Desk")
    #expect(item.security == .WPA3)
    #expect(item.rssi == -55)
    #expect(item.strength == 4)
    #expect(item.detailKind == .lock)
    #expect(item.identifier == "other.Desk")
}

@MainActor
@Test("Bar strength follows the interface reading, not a stale scan")
func barsFollowTheInterface() {
    for (rssi, bars) in [(-50, 4), (-65, 3), (-75, 2), (-85, 1), (-95, 0)] {
        #expect(WiFiIcon.wifi(strength: bars).size.width >= WiFiIcon.boxSize)
        let input = NBEngineInput()
        input.powerOn = true
        input.interfaceName = "en0"
        input.currentSSID = "Home"
        input.currentRSSI = rssi
        #expect(Int(EngineBridge.render(input).connectedStrength) == bars)
    }
}

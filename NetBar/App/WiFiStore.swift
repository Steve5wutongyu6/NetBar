//
//  WiFiStore.swift
//  NetBar
//
//  Everything the menu renders comes from one capture: the radio state, the
//  scan, and the rows the engine derives from them. Scanning blocks the calling
//  thread for up to two seconds, so it never runs on the main actor.
//

import AppKit
import Foundation

@MainActor
@Observable
final class WiFiStore {
    /// Where a capture comes from. Fixtures keep the UI testable without a radio.
    enum Source {
        case live
        case fixture(URL)
    }

    private(set) var output = NBEngineOutput()
    private(set) var isScanning = false
    private(set) var namesUnavailable = false
    private(set) var powerOn = true
    private(set) var connectedName: String?
    private(set) var connectedIsHotspot = false
    private(set) var strength = 0
    private(set) var statusTitle: String?
    /// Incremented on every applied menu, so the panel knows to re-fit its size.
    private(set) var revision = 0

    /// The user unfolded "Other Networks".
    var revealsOther = false {
        didSet {
            guard revealsOther != oldValue else { return }
            // Unfolding is a view change: re-render the same capture.
            rerender()
        }
    }

    let source: Source
    private var lastSnapshot: NBSnapshot?
    /// Networks from the last full scan. A state-only refresh reuses them, so
    /// reading the connection state never empties the list.
    private var scannedNetworks: [NBScannedNetwork] = []
    private var scanState = ScanState()
    private var lastInput: NBEngineInput?

    init(source: Source = .live) {
        self.source = source
    }

    /// Refreshes the menu, optionally rescanning the radio. Callers await the
    /// result, so a second refresh simply queues behind the first.
    func refresh(scan: Bool = true) async {
        await load(scan: scan)
    }

    /// Asks for Location Services authorization. macOS reveals network names —
    /// and the beacon metadata that identifies a Personal Hotspot — only to
    /// authorized apps, and an app that never asks does not even appear in the
    /// pane the settings link opens.
    ///
    /// The answer can take a while, and a suppressed prompt may never arrive, so
    /// this does not wait: the authorization notification brings the new state.
    func requestNameAccess() {
        // The answer arrives on the main thread; refreshing here covers a missed
        // notification, and the notification covers an answer we were not waiting for.
        NBLocationAuthorizer.shared().requestAuthorization { [weak self] authorization in
            guard authorization == .authorized else { return }
            Task { @MainActor in
                await self?.refresh(scan: true)
            }
        }
    }

    /// Re-reads the radio after the user changed the authorization.
    func authorizationDidChange() async {
        guard NBLocationAuthorizer.shared().isAuthorized else { return }
        await refresh(scan: true)
    }

    /// Asks the system to join a network. A saved profile joins with its stored
    /// password; anything else needs the system pane, which is where the click
    /// goes when the radio refuses.
    func connect(_ item: NBEngineItem) async {
        guard case .live = source, let ssid = item.ssid, !item.isJoined else { return }
        let joined: Bool = await Task.detached(priority: .userInitiated) {
            do {
                try NBWiFiBridge.joinNetwork(withSSID: ssid)
                return true
            } catch {
                return false
            }
        }.value
        if joined {
            await refresh(scan: true)
        } else {
            NBWiFiBridge.openWiFiSettings()
        }
    }

    func setPower(_ on: Bool) async {
        guard case .live = source else {
            powerOn = on
            return
        }
        let failure: String? = await Task.detached(priority: .userInitiated) {
            do {
                try NBWiFiBridge.setPowerOn(on)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        if failure == nil {
            powerOn = on
            await refresh(scan: on)
        }
    }

    private func load(scan: Bool) async {
        switch source {
        case .fixture(let url):
            apply(fixtureInput(at: url))
        case .live:
            isScanning = true
            defer { isScanning = false }
            // Registers the app with Location Services on the first capture, so
            // the authorization prompt can appear at all.
            _ = NBLocationAuthorizer.shared()
            // Browsing is what fills in the Cellular column of a hotspot.
            NBHotspotMonitor.shared().start()
            let preferred = NBWiFiBridge.preferredNetworkNames()
            let snapshot = await Self.capture(scan: scan)
            if scan {
                scannedNetworks = snapshot.networks
                scanState = Self.scanState(of: snapshot)
            } else {
                // The connection state changed, the radio's neighbourhood did not,
                // so everything a scan had established carries over.
                snapshot.networks = scannedNetworks
                Self.restore(scanState, into: snapshot)
            }
            lastSnapshot = snapshot
            let input = Self.input(from: snapshot, preferred: preferred)
            apply(input)
        }
    }

    /// What a full scan established and a state-only capture cannot know.
    private struct ScanState {
        var isPersonalHotspot = false
        var isApplePersonalHotspot = false
        var network: NBHotspotNetwork = .networkUnknown
        var battery = 0
        var namesAvailable = true
        var namesUnavailableReason: String?
        var namesAvailabilityKnown = false
    }

    private static func scanState(of snapshot: NBSnapshot) -> ScanState {
        ScanState(
            isPersonalHotspot: snapshot.currentIsPersonalHotspot,
            isApplePersonalHotspot: snapshot.currentIsApplePersonalHotspot,
            network: snapshot.currentHotspotNetwork,
            battery: snapshot.currentHotspotBattery,
            namesAvailable: snapshot.namesAvailable,
            namesUnavailableReason: snapshot.namesUnavailableReason,
            namesAvailabilityKnown: snapshot.namesAvailabilityKnown
        )
    }

    private static func restore(_ state: ScanState, into snapshot: NBSnapshot) {
        snapshot.currentIsPersonalHotspot = state.isPersonalHotspot
        snapshot.currentIsApplePersonalHotspot = state.isApplePersonalHotspot
        snapshot.currentHotspotNetwork = state.network
        snapshot.currentHotspotBattery = state.battery
        snapshot.namesAvailable = state.namesAvailable
        snapshot.namesUnavailableReason = state.namesUnavailableReason
        snapshot.namesAvailabilityKnown = state.namesAvailabilityKnown
    }

    /// Re-renders the last capture, e.g. after the user unfolded the list.
    func rerender() {
        guard let lastInput else { return }
        apply(lastInput)
    }

    private func apply(_ input: NBEngineInput?) {
        guard let input else { return }
        input.revealOther = revealsOther
        lastInput = input
        let rendered = EngineBridge.render(input)
        output = rendered
        revision += 1
        statusTitle = rendered.statusTitle
        powerOn = input.powerOn
        namesUnavailable = input.connectedNameRedacted
        connectedName = rendered.connectedName
        connectedIsHotspot = rendered.connectedIsHotspot
        strength = Int(rendered.connectedStrength)
        if let snapshot = lastSnapshot {
            powerOn = snapshot.powerOn
            // Only a scan can answer this; until one has run, the redaction of the
            // joined name is the best evidence there is.
            if snapshot.namesAvailabilityKnown {
                namesUnavailable = !snapshot.namesAvailable
            }
        }
    }

    /// Renders an engine request directly. Used by snapshot rendering and tests
    /// to lay out a menu that no capture produced.
    func applyForTesting(_ input: NBEngineInput) {
        apply(input)
    }

    /// Hydrates a fixture capture synchronously, for snapshot rendering where no
    /// run loop is available yet.
    func loadFixtureSynchronously() {
        guard case .fixture(let url) = source else { return }
        apply(fixtureInput(at: url))
    }

    private func fixtureInput(at url: URL) -> NBEngineInput? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // A fixture is an engine request, so the menu it produces is the menu a
        // real capture with those values would produce.
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let input = NBEngineInput()
        input.powerOn = object["powerOn"] as? Bool ?? true
        input.currentSSID = object["currentSSID"] as? String
        input.connectedNameRedacted = object["connectedNameRedacted"] as? Bool ?? false
        input.interfaceName = object["interfaceName"] as? String
        input.currentRSSI = object["currentRSSI"] as? Int ?? 0
        input.scanning = object["scanning"] as? Bool ?? true
        input.preferredNetworks = object["preferredNetworks"] as? [String] ?? []
        input.networks = (object["networks"] as? [[String: Any]] ?? []).map(Self.network(from:))
        return input
    }

    private static func network(from object: [String: Any]) -> NBEngineNetwork {
        let network = NBEngineNetwork()
        network.ssid = object["ssid"] as? String
        network.serviceName = object["serviceName"] as? String
        network.bssid = object["bssid"] as? String
        network.rssi = object["rssi"] as? Int ?? 0
        network.security = NBWiFiSecurity(rawValue: object["security"] as? Int ?? 0) ?? .open
        network.phyMode = NBWiFiPHYMode(rawValue: object["phyMode"] as? Int ?? 0) ?? .modeUnknown
        network.channel = object["channel"] as? Int ?? 0
        network.known = object["known"] as? Bool ?? false
        network.personalHotspot = object["personalHotspot"] as? Bool ?? false
        network.hotspotNetwork = NBHotspotNetwork(rawValue: object["hotspotNetwork"] as? Int ?? 0) ?? .networkUnknown
        network.hotspotBattery = object["hotspotBattery"] as? Int ?? 0
        return network
    }

    private static func capture(scan: Bool) async -> NBSnapshot {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: scan ? NBWiFiBridge.captureSnapshot() : NBWiFiBridge.captureState())
            }
        }
    }

    /// Translates a capture into the engine's request.
    static func input(from snapshot: NBSnapshot, preferred: [String]) -> NBEngineInput {
        let input = NBEngineInput()
        input.powerOn = snapshot.powerOn
        input.currentSSID = snapshot.currentSSID
        input.interfaceName = snapshot.interfaceName
        input.currentRSSI = snapshot.currentRSSI
        input.scanning = true
        input.preferredNetworks = preferred
        // macOS hides the name of the joined network whenever it withholds every
        // other name, so a healthy signal with no name means "hidden", not "idle".
        input.connectedNameRedacted = snapshot.currentSSID == nil && snapshot.currentRSSI != 0
        // The radio knows more about the joined network than a name-matched scan
        // record does, and it keeps working while macOS withholds names.
        input.currentIsPersonalHotspot = snapshot.currentIsPersonalHotspot
        input.currentHotspotNetwork = snapshot.currentHotspotNetwork
        input.currentHotspotBattery = snapshot.currentHotspotBattery
        // Continuity knows the Cellular side of a Personal Hotspot; the Wi-Fi
        // beacon never carries it.
        input.peers = NBHotspotMonitor.shared().peers.map { peer in
            let info = NBHotspotPeerInfo()
            info.name = peer.name
            info.batteryPercent = peer.batteryPercent
            info.networkLabel = peer.networkLabel
            info.signalBars = peer.signalBars
            return info
        }
        input.networks = snapshot.networks.map { scanned in
            let network = NBEngineNetwork()
            network.ssid = scanned.ssid
            network.serviceName = scanned.serviceName
            network.bssid = scanned.bssid
            network.rssi = scanned.rssi
            network.security = scanned.security
            network.phyMode = scanned.phyMode
            network.channel = scanned.channel
            network.known = scanned.known
            network.personalHotspot = scanned.personalHotspot
            network.hotspotNetwork = scanned.hotspotNetwork
            network.hotspotBattery = scanned.hotspotBattery
            return network
        }
        return input
    }
}

// Both models are filled on one thread and then handed over: a snapshot is
// written by the capture queue before it crosses to the main actor, and an engine
// reply is decoded on the calling thread before it is used. Neither is mutated
// after that hand-off, which is what the unchecked conformance asserts.
extension NBSnapshot: @unchecked Sendable {}
extension NBEngineOutput: @unchecked Sendable {}

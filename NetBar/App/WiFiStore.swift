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

    /// The user unfolded "Other Networks".
    var revealsOther = false {
        didSet {
            guard revealsOther != oldValue else { return }
            Task { await refresh(scan: false) }
        }
    }

    let source: Source
    private var lastSnapshot: NBSnapshot?

    init(source: Source = .live) {
        self.source = source
    }

    /// Refreshes the menu, optionally rescanning the radio. Callers await the
    /// result, so a second refresh simply queues behind the first.
    func refresh(scan: Bool = true) async {
        await load(scan: scan)
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
            let preferred = NBWiFiBridge.preferredNetworkNames()
            let snapshot = await Self.capture(scan: scan)
            lastSnapshot = snapshot
            let input = Self.input(from: snapshot, preferred: preferred)
            apply(input)
        }
    }

    private func apply(_ input: NBEngineInput?) {
        guard let input else { return }
        input.revealOther = revealsOther
        let rendered = EngineBridge.render(input)
        output = rendered
        statusTitle = rendered.statusTitle
        powerOn = input.powerOn
        namesUnavailable = input.connectedNameRedacted
        connectedName = rendered.connectedName
        connectedIsHotspot = rendered.connectedIsHotspot
        strength = Int(rendered.connectedStrength)
        if let snapshot = lastSnapshot {
            powerOn = snapshot.powerOn
            namesUnavailable = !snapshot.namesAvailable
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

extension NBSnapshot: @unchecked Sendable {}
extension NBEngineOutput: @unchecked Sendable {}

//
//  Diagnostics.swift
//  NetBar
//
//  Dumps what this process can actually see on the radio: authorization state,
//  each beacon's information elements and how they decode. It exists because
//  the hotspot indicators depend on vendor bytes that macOS only hands to an
//  authorized app, so guessing their layout is not an option.
//
//  Reached with `NetBar --scan-dump <path>`; it creates no windows and no
//  status item.
//

import CoreLocation
import CoreWLAN
import Foundation

enum Diagnostics {
    /// Writes a scan dump and returns a process exit code.
    static func writeScanDump(to path: String) -> Int32 {
        var lines: [String] = []
        let authorization = CLLocationManager().authorizationStatus
        lines.append("bundle=\(Bundle.main.bundlePath)")
        lines.append("locationAuthorization=\(describe(authorization))")

        let client: CWWiFiClient = CWWiFiClient.shared()
        guard let interface: CWInterface = client.interface() else {
            lines.append("interface=none")
            return write(lines, to: path)
        }
        lines.append("interface=\(interface.interfaceName ?? "?") power=\(interface.powerOn())")
        lines.append("ssid=\(interface.ssid() ?? "(hidden)") bssid=\(interface.bssid() ?? "(hidden)") rssi=\(interface.rssiValue())")

        let scan = (try? interface.scanForNetworks(withName: nil, includeHidden: false)) ?? []
        lines.append("networks=\(scan.count)")
        for network in scan.sorted(by: { $0.rssiValue > $1.rssiValue }) {
            let ie = network.informationElementData ?? Data()
            let info = NBHotspotParseInformationElements(ie)
            lines.append("""
            network ssid=\(network.ssid ?? "(hidden)") bssid=\(network.bssid ?? "(hidden)") \
            rssi=\(network.rssiValue) ieBytes=\(ie.count) hotspot=\(info.isPersonalHotspot) \
            cellular=\(info.network.rawValue) battery=\(info.batteryPercent) carries=\(info.carriesHotspotInformation)
            """)
            if !ie.isEmpty {
                lines.append("  elements=\(elements(in: ie))")
            }
        }
        return write(lines, to: path)
    }

    /// Every vendor-specific element, with its OUI and payload. The Cellular
    /// indicator is not guaranteed to live in an Apple OUI element, so nothing
    /// vendor-specific is filtered out here.
    private static func elements(in data: Data) -> String {
        var found: [String] = []
        var offset = 0
        while offset + 2 <= data.count {
            let identifier = data[offset]
            let length = Int(data[offset + 1])
            let bodyStart = offset + 2
            guard bodyStart + length <= data.count else { break }
            if identifier == 221, length >= 4 {
                let body = data.subdata(in: bodyStart..<(bodyStart + length))
                let oui = String(format: "%02x:%02x:%02x", body[0], body[1], body[2])
                let payload = body.map { String(format: "%02x", $0) }.joined(separator: " ")
                found.append("oui=\(oui)[\(payload)]")
            }
            offset = bodyStart + length
        }
        return found.isEmpty ? "none" : found.joined(separator: " ")
    }

    private static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    private static func write(_ lines: [String], to path: String) -> Int32 {
        let text = lines.joined(separator: "\n") + "\n"
        do {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            FileHandle.standardOutput.write(Data(text.utf8))
            return 0
        } catch {
            FileHandle.standardError.write(Data("scan dump failed: \(error)\n".utf8))
            return 1
        }
    }
}

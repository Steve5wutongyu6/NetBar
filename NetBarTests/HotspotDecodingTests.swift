//
//  HotspotDecodingTests.swift
//  NetBarTests
//
//  The hotspot metadata that makes an Apple Personal Hotspot row show signal,
//  Cellular and battery instead of a lock is decoded from beacon information
//  elements. These are the frames that decoder has to survive.
//

import Foundation
import Testing

@testable import NetBar

/// One information element: id, length, body.
private func element(_ identifier: UInt8, _ body: [UInt8]) -> Data {
    Data([identifier, UInt8(body.count)] + body)
}

/// An Apple vendor element, with the OUI and element type in front of `body`.
private func appleElement(_ type: UInt8, _ body: [UInt8]) -> Data {
    element(221, [0x00, 0x50, 0xF2, type] + body)
}

private let hotspotMarker: UInt8 = 0x0D
private let deviceInfo: UInt8 = 0x0E
private let cellular: UInt8 = 0x10
private let hotspotFlags: UInt8 = 0x13

@Test("Battery readings decode across the whole range")
func batteryDecoding() {
    // 0x48 is 72 %, 0x64 is 100 %; bit 7 means "charging" and is not subtracted.
    #expect(NBHotspotParseInformationElements(appleElement(deviceInfo, [0x48])).batteryPercent == 72)
    #expect(NBHotspotParseInformationElements(appleElement(deviceInfo, [0x64])).batteryPercent == 100)
    #expect(NBHotspotParseInformationElements(appleElement(deviceInfo, [0x80 | 0x5C])).batteryPercent == 92)
    #expect(NBHotspotParseInformationElements(appleElement(deviceInfo, [0x00])).batteryPercent == 0)
}

@Test("The hotspot marker and its flags both identify a Personal Hotspot")
func hotspotMarkers() {
    let marked = NBHotspotParseInformationElements(appleElement(hotspotMarker, []))
    #expect(marked.isPersonalHotspot)
    #expect(marked.carriesHotspotInformation)

    let flagged = NBHotspotParseInformationElements(appleElement(hotspotFlags, [0x01]))
    #expect(flagged.isPersonalHotspot)

    let unflagged = NBHotspotParseInformationElements(appleElement(hotspotFlags, [0x00]))
    #expect(!unflagged.isPersonalHotspot)
    #expect(unflagged.carriesHotspotInformation)
}

@Test("Cellular generations decode to the indicator the menu draws")
func cellularDecoding() {
    #expect(NBHotspotParseInformationElements(appleElement(cellular, [0x02])).network == .network4G)
    #expect(NBHotspotParseInformationElements(appleElement(cellular, [0x0A])).network == .network5G)
    // 2G/3G and "unknown" both mean no indicator.
    #expect(NBHotspotParseInformationElements(appleElement(cellular, [0x01])).network == .networkUnknown)
    #expect(NBHotspotParseInformationElements(appleElement(cellular, [0x00])).network == .networkUnknown)
}

@Test("A complete iPhone hotspot frame decodes every field")
func completeFrame() {
    var frame = appleElement(hotspotMarker, [])
    frame.append(appleElement(cellular, [0x0A]))
    frame.append(appleElement(deviceInfo, [0x64]))

    let info = NBHotspotParseInformationElements(frame)
    #expect(info.isPersonalHotspot)
    #expect(info.network == .network5G)
    #expect(info.batteryPercent == 100)
    #expect(info.carriesHotspotInformation)
}

@Test("Ordinary networks are not mistaken for hotspots")
func ordinaryFrames() {
    var frame = element(0, [0x01, 0x02, 0x03])
    frame.append(element(48, [0x0C, 0x12, 0x18]))
    frame.append(element(221, [0x00, 0x17, 0xF2, 0x02, 0x01]))

    let info = NBHotspotParseInformationElements(frame)
    #expect(!info.isPersonalHotspot)
    #expect(info.network == .networkUnknown)
    #expect(info.batteryPercent == 0)
}

@Test("Truncated and hostile frames decode to nothing without crashing")
func hostileFrames() {
    // A length byte that promises more bytes than the frame holds.
    let lying = Data([221, 200, 0x00, 0x50, 0xF2, deviceInfo])
    #expect(!NBHotspotParseInformationElements(lying).isPersonalHotspot)

    // An element cut in the middle of the Apple OUI.
    #expect(!NBHotspotParseInformationElements(element(221, [0x00, 0x50])).isPersonalHotspot)

    // A zero-length vendor element, an empty frame and no frame at all.
    #expect(!NBHotspotParseInformationElements(element(221, [])).isPersonalHotspot)
    #expect(!NBHotspotParseInformationElements(Data()).isPersonalHotspot)
    #expect(!NBHotspotParseInformationElements(nil).isPersonalHotspot)

    // Bytes that look like a marker but sit in a non-vendor element.
    #expect(!NBHotspotParseInformationElements(element(0, [0x00, 0x50, 0xF2, hotspotMarker])).isPersonalHotspot)
}

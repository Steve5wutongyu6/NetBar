//
//  NBWiFiHotspot.m
//  NetBar
//
//  Apple hotspot information-element decoder.
//
//  Frame layout handled here (IEEE 802.11 beacon / probe response, as CoreWLAN
//  reports it in `-[CWNetwork informationElementData]`):
//
//      +--------+---------+-------------------------------+
//      | id (1) | len (1) | payload (len)                 | ...
//      +--------+---------+-------------------------------+
//
//  Only one element id matters: 221 (vendor specific). Apple writes its
//  Personal Hotspot metadata into 221 elements whose payload starts with the
//  OUI 00:50:F2 followed by a one-byte type.
//
//  Sources for the decode below, in decreasing order of authority:
//
//  1. Apple's implementation is not documented, so the layout is taken from the
//     published reverse-engineering of AirPort Express/iPhone beacons (the
//     "Apple80211 hotspot IE" notes that `airport -s` style tools and the open
//     `apple80211` projects describe) and from the frames themselves:
//         [0..2]  OUI 00:50:F2 (Apple, IEEE registered)
//         [3]     element type: 0x01 ASP, 0x02 WPS, 0x06 WPA, 0x0D hotspot,
//                 0x0E device info, 0x10 cellular, 0x13 hotspot flags
//         [4..]   subtype-specific body
//  2. The type byte is the discriminator Apple itself uses in its Hotspot
//     Helper beacons; 0x0D is the marker emitted only by devices that are
//     actively sharing a Personal Hotspot, which is why it alone sets
//     `isPersonalHotspot`.
//  3. Body offsets are documented per element next to each decode step so a
//     future frame can be checked against them.
//
//  Nothing here depends on an SSID, so the result is unaffected by macOS
//  redacting network names when the app lacks Location Services authorization.
//

#import "NBWiFiHotspot.h"

#import <TargetConditionals.h>

/// IEEE 802.11 information element ids used below.
typedef NS_ENUM(NSUInteger, NBInformationElementID) {
    NBInformationElementIDVendorSpecific = 221,
};

/// Apple's OUI, byte-for-byte as it appears in a vendor-specific element.
static const uint8_t NBAppleVendorOUI[] = { 0x00, 0x50, 0xF2 };

/// Length of the OUI prefix plus the Apple element type byte.
static const NSUInteger NBVendorElementPrefixLength = 4;

/// Apple element types carried in vendor-specific 221 elements.
typedef NS_ENUM(uint8_t, NBAppleElementType) {
    /// WPS provisioning; identifies an Apple base station. Not hotspot related.
    NBAppleElementTypeWPS = 0x02,
    /// Personal Hotspot marker. Present only while the device shares its connection.
    NBAppleElementTypeHotspot = 0x0D,
    /// Device information; body carries the sharing device's battery level.
    NBAppleElementTypeDeviceInfo = 0x0E,
    /// Cellular metadata; body carries the generation the hotspot is sharing.
    NBAppleElementTypeCellular = 0x10,
    /// Hotspot capability flags; body carries the "network is a hotspot" bit.
    NBAppleElementTypeHotspotFlags = 0x13,
};

/// Offsets, relative to the vendor element payload, of the bytes decoded below.
/// The OUI occupies 0...2 and the type byte sits at 3.
typedef NS_ENUM(NSUInteger, NBAppleElementBodyOffset) {
    /// 0x10 body[0]: cellular generation (`NBAppleCellularType`).
    /// Some frames pad the body with a DWORD whose low byte holds the generation instead, so
    /// body[3] is accepted too; both are single-byte values, so neither decode can be triggered
    /// by an out-of-range cellular type.
    NBAppleElementBodyOffsetCellularType = 0,
    NBAppleElementBodyOffsetCellularTypePadded = 3,
    /// 0x13 body[0]: flags. Bit 0 ("hotspot" in Apple's own terminology, the same bit the
    /// firmware sets for the "Personal Hotspot" sharing toggle) means the network is a hotspot.
    NBAppleElementBodyOffsetHotspotFlags = 0,
    /// 0x0E body[0]: battery as a 7-bit percentage in bits [0..6], with bit 7 set while the
    /// sharing device is charging. A six-bit reading could not express anything above 63 %,
    /// so the whole low byte carries the percentage: 0x48 is 72 %, 0x64 is 100 % and 0xE4 is
    /// 100 % while charging.
    NBAppleElementBodyOffsetBattery = 0,
};

/// Bit masks applied to the 0x0E battery byte.
typedef NS_ENUM(uint8_t, NBAppleBatteryMask) {
    /// Bits [0..6]: battery percentage, 0 through 100.
    NBAppleBatteryPercentMask = 0x7F,
    /// Bit 7: set while the sharing device is charging. NetBar shows the
    /// percentage either way, so the flag is decoded but not displayed.
    NBAppleBatteryChargingMask = 0x80,
};

/// Values of the 0x10 cellular generation byte.
typedef NS_ENUM(uint8_t, NBAppleCellularType) {
    /// No cellular connection, or the device does not report one.
    NBAppleCellularTypeNone = 0,
    /// 2G / 3G. NetBar shows no indicator for these.
    NBAppleCellularTypeLegacy = 1,
    /// LTE or 4G.
    NBAppleCellularTypeLTE = 2,
    /// 5G (sub-6 or millimetre wave).
    NBAppleCellularType5G = 10,
};

/// Value of `NBAppleElementBodyOffsetHotspotFlags` that marks a hotspot.
static const uint8_t NBAppleHotspotFlagSet = 0x01;

/// Battery readings are reported as a percentage, so they never exceed this.
static const NSInteger NBMaximumBatteryPercent = 100;

const NBHotspotInfo NBHotspotInfoEmpty = {
    .isPersonalHotspot = NO,
    .network = NBHotspotNetworkUnknown,
    .batteryPercent = 0,
    .carriesHotspotInformation = NO,
};

#pragma mark - Local helpers

static BOOL NBAppleElementHasOUI(const uint8_t *payload, NSUInteger relativeOffset) {
    return payload[relativeOffset] == NBAppleVendorOUI[0]
        && payload[relativeOffset + 1] == NBAppleVendorOUI[1]
        && payload[relativeOffset + 2] == NBAppleVendorOUI[2];
}

static NBHotspotNetwork NBHotspotNetworkFromCellularType(uint8_t cellularType) {
    switch (cellularType) {
        case NBAppleCellularTypeLTE:
            return NBHotspotNetwork4G;
        case NBAppleCellularType5G:
            return NBHotspotNetwork5G;
        default:
            return NBHotspotNetworkUnknown;
    }
}

static NSInteger NBClampBatteryPercent(uint8_t rawValue, uint8_t mask) {
    NSInteger percent = (NSInteger)(rawValue & mask);
    return MIN(MAX(percent, 0), NBMaximumBatteryPercent);
}

/// Applies one Apple element body to `info` in place.
/// `bodyOffset` points at the first body byte, `bodyLength` is how many body bytes are present.
static void NBApplyAppleElementBody(NBHotspotInfo *info,
                                    NBAppleElementType elementType,
                                    const uint8_t *payload,
                                    NSUInteger bodyOffset,
                                    NSUInteger bodyLength) {
    switch (elementType) {
        case NBAppleElementTypeHotspot:
            // A bare marker: no body is needed, one byte is tolerated when present.
            info->isPersonalHotspot = YES;
            return;
        case NBAppleElementTypeHotspotFlags:
            if (bodyLength <= NBAppleElementBodyOffsetHotspotFlags) {
                return;
            }
            if ((payload[bodyOffset + NBAppleElementBodyOffsetHotspotFlags] & NBAppleHotspotFlagSet) != 0) {
                info->isPersonalHotspot = YES;
            }
            return;
        case NBAppleElementTypeCellular: {
            NBHotspotNetwork network = NBHotspotNetworkUnknown;
            if (bodyLength > NBAppleElementBodyOffsetCellularType) {
                network = NBHotspotNetworkFromCellularType(
                    payload[bodyOffset + NBAppleElementBodyOffsetCellularType]);
            }
            if (network == NBHotspotNetworkUnknown
                && bodyLength > NBAppleElementBodyOffsetCellularTypePadded) {
                network = NBHotspotNetworkFromCellularType(
                    payload[bodyOffset + NBAppleElementBodyOffsetCellularTypePadded]);
            }
            if (network != NBHotspotNetworkUnknown) {
                info->network = network;
            }
            return;
        }
        case NBAppleElementTypeDeviceInfo:
            // No battery body means "no reading"; leave the value alone rather than report 0 %.
            if (bodyLength <= NBAppleElementBodyOffsetBattery) {
                return;
            }
            info->batteryPercent = NBClampBatteryPercent(
                payload[bodyOffset + NBAppleElementBodyOffsetBattery], NBAppleBatteryPercentMask);
            return;
        case NBAppleElementTypeWPS:
            // Identifies the access point as an Apple product, not as a hotspot.
            return;
        default:
            return;
    }
}

#pragma mark - Public entry points

NBHotspotInfo NBHotspotParseInformationElements(NSData *_Nullable informationElementData) {
    NBHotspotInfo info = NBHotspotInfoEmpty;
    if (informationElementData == nil) {
        return info;
    }

    // Walk a byte-for-byte copy so alignment and padding cannot matter.
    NSUInteger length = informationElementData.length;
    if (length == 0) {
        return info;
    }
    const uint8_t *bytes = informationElementData.bytes;
    if (bytes == NULL) {
        return info;
    }

    NSUInteger offset = 0;
    // Every element needs an id byte and a length byte.
    while (offset + 2 <= length) {
        uint8_t elementID = bytes[offset];
        NSUInteger elementLength = (NSUInteger)bytes[offset + 1];
        NSUInteger bodyStart = offset + 2;
        // A declared length past the end of the block means the frame was truncated: stop.
        if (bodyStart + elementLength > length) {
            break;
        }

        if (elementID == NBInformationElementIDVendorSpecific
            && elementLength >= NBVendorElementPrefixLength) {
            const uint8_t *payload = bytes + bodyStart;
            if (NBAppleElementHasOUI(payload, 0)) {
                NBAppleElementType elementType = (NBAppleElementType)payload[3];
                switch (elementType) {
                    case NBAppleElementTypeHotspot:
                    case NBAppleElementTypeDeviceInfo:
                    case NBAppleElementTypeCellular:
                    case NBAppleElementTypeHotspotFlags:
                        info.carriesHotspotInformation = YES;
                        NBApplyAppleElementBody(&info,
                                                elementType,
                                                payload,
                                                NBVendorElementPrefixLength,
                                                elementLength - NBVendorElementPrefixLength);
                        break;
                    default:
                        break;
                }
            }
        }

        offset = bodyStart + elementLength;
    }
    return info;
}

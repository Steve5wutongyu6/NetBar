//
//  NBWiFiHotspot.h
//  NetBar
//
//  Decodes the Apple Personal Hotspot metadata that iPhone and iPad beacons
//  carry inside information elements: whether this network is a personal
//  hotspot, the cellular generation it shares (4G/LTE or 5G) and the battery
//  percentage of the sharing device.
//
//  Everything here is derived from the radio frame itself. Network names are
//  never inspected, so the result survives macOS redacting SSIDs when the
//  process lacks Location Services authorization.
//

#import <Foundation/Foundation.h>
#import <stdbool.h>
#import "NBWiFiModels.h"

NS_ASSUME_NONNULL_BEGIN

/// Metadata decoded from one beacon's information elements.
///
/// A zero-initialised value means "the frame advertised nothing about hotspots".
typedef struct NBHotspotInfo {
    /// YES when the beacon carries Apple's Personal Hotspot marker.
    bool isPersonalHotspot;
    /// Cellular generation the hotspot advertises; `NBHotspotNetworkUnknown` when it advertises none.
    NBHotspotNetwork network;
    /// Battery percentage clamped to 0...100; 0 when the device did not broadcast one.
    NSInteger batteryPercent;
    /// YES when at least one Apple hotspot information element was present, even if it was unusable.
    bool carriesHotspotInformation;
} NBHotspotInfo;

/// A `NBHotspotInfo` that describes no hotspot at all.
FOUNDATION_EXPORT const NBHotspotInfo NBHotspotInfoEmpty;

/// Decodes Apple hotspot information from a beacon's information-element block.
///
/// \param informationElementData The value of `-[CWNetwork informationElementData]`, or `nil`.
///
/// \discussion Never crashes: every offset is bounds-checked, so truncated or
/// malformed elements simply contribute nothing.
FOUNDATION_EXPORT NBHotspotInfo NBHotspotParseInformationElements(NSData *_Nullable informationElementData);

NS_ASSUME_NONNULL_END

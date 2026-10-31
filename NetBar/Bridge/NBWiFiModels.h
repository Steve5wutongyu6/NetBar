//
//  NBWiFiModels.h
//  NetBar
//
//  Notification-style reference types the Objective-C Wi-Fi bridge hands to
//  Swift: one object per capture, written by the bridge and then read-only in
//  practice. Every field is plain C or a nullability-annotated type so the Swift
//  importer generates clean, optional-correct interfaces.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NBWiFiSecurity) {
    NBWiFiSecurityOpen = 0,
    NBWiFiSecurityWEP,
    NBWiFiSecurityWPA,
    NBWiFiSecurityWPA2,
    NBWiFiSecurityWPA3,
    NBWiFiSecurityEnterprise,
};

typedef NS_ENUM(NSInteger, NBWiFiPHYMode) {
    NBWiFiPHYModeUnknown = 0,
    NBWiFiPHYMode80211a = 1,
    NBWiFiPHYMode80211b = 2,
    NBWiFiPHYMode80211g = 3,
    NBWiFiPHYMode80211n = 4,
    NBWiFiPHYMode80211ac = 5,
    NBWiFiPHYMode80211ax = 6,
    NBWiFiPHYMode80211be = 7,
};

typedef NS_ENUM(NSInteger, NBHotspotNetwork) {
    NBHotspotNetworkUnknown = 0,
    NBHotspotNetwork4G,
    NBHotspotNetwork5G,
};

/// One BSS or one ESS as CoreWLAN reported it, enriched with hotspot metadata.
@interface NBScannedNetwork : NSObject

/// Service set identifier. `nil` when macOS redacted the name for this process.
@property (nonatomic, copy, nullable) NSString *ssid;
/// Name of the preferred-network profile this ESSID belongs to, if any. CoreWLAN
/// keeps profile names even when macOS hides SSIDs from the process, so it lets
/// NetBar recognise a saved network without Location Services.
@property (nonatomic, copy, nullable) NSString *serviceName;
/// Basic service set identifier, `XX:XX:XX:XX:XX:XX`.
@property (nonatomic, copy, nullable) NSString *bssid;
/// Received signal strength in dBm.
@property (nonatomic) NSInteger rssi;
@property (nonatomic) NBWiFiSecurity security;
@property (nonatomic) NBWiFiPHYMode phyMode;
/// Radio channel number; 0 when unknown.
@property (nonatomic) NSInteger channel;
/// YES when the network belongs to the current Wi-Fi configuration profile.
@property (nonatomic) BOOL known;
/// YES when the beacon carries the Personal Hotspot marker Apple devices emit.
@property (nonatomic) BOOL personalHotspot;
/// Cellular band a personal hotspot advertises, when it does.
@property (nonatomic) NBHotspotNetwork hotspotNetwork;
/// 0-100 battery reading broadcast by an Apple hotspot, 0 when unknown.
@property (nonatomic) NSInteger hotspotBattery;
/// YES when the scan record carried any hotspot-related information element.
@property (nonatomic) BOOL carriesHotspotInformation;

@end

/// Snapshot of the Wi-Fi interface and everything it can currently see.
@interface NBSnapshot : NSObject

@property (nonatomic, copy, nullable) NSString *interfaceName;
@property (nonatomic) BOOL powerOn;
@property (nonatomic, copy, nullable) NSString *currentSSID;
@property (nonatomic, copy, nullable) NSString *currentBSSID;
@property (nonatomic) NSInteger currentRSSI;
@property (nonatomic) BOOL currentIsPersonalHotspot;
@property (nonatomic) BOOL currentIsApplePersonalHotspot;
@property (nonatomic) NBHotspotNetwork currentHotspotNetwork;
@property (nonatomic) NSInteger currentHotspotBattery;
/// Nearest neighbours the interface could enumerate, weakest last.
@property (nonatomic, copy) NSArray<NBScannedNetwork *> *networks;
/// Whether macOS let this process read network names at all.
@property (nonatomic) BOOL namesAvailable;
/// NO when this capture did not look (the state-only path), so callers can keep
/// whatever the last scan found instead of trusting a default.
@property (nonatomic) BOOL namesAvailabilityKnown;
/// Human readable reason when `namesAvailable` is NO.
@property (nonatomic, copy, nullable) NSString *namesUnavailableReason;

@end

NS_ASSUME_NONNULL_END

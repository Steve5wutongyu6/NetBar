//
//  NBWiFiBridge.m
//  NetBar
//
//  CoreWLAN bridge. All work happens on the calling thread; callers run it off
//  the main thread because a scan blocks for up to two seconds. Nothing here
//  touches the network: CoreWLAN only reads the radio's own scan cache and
//  configuration.
//

#import "NBWiFiBridge.h"
#import "NBWiFiHotspot.h"

#import <AppKit/AppKit.h>
#import <CoreWLAN/CoreWLAN.h>

NSString *const NBWiFiBridgeErrorDomain = @"dev.netbar.app.wifi-bridge";

/// Interface used when no Wi-Fi interface reports that it is powered on.
static NSString *const NBFallbackInterfaceName = @"en0";

/// Shown when macOS returned scan results but blanked every name. Network names
/// are gated behind Location Services authorization on macOS 15 and later.
static NSString *const NBNamesUnavailableReason =
    @"Network names are hidden. Allow NetBar in Privacy & Security > Location Services.";

/// System Settings deep links. Neither URL leaves the machine.
static NSString *const NBWiFiSettingsURLString =
    @"x-apple.systempreferences:com.apple.wifi-settings-extension";
static NSString *const NBPrivacySettingsURLString =
    @"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices";

/// Replacement when `-[CWInterface wlanChannel]` returned nil.
static const NSInteger NBUnknownChannel = 0;

#pragma mark - Helpers

static NSError *NBMakeBridgeError(NBWiFiBridgeError code, NSString *description, NSError *_Nullable underlying) {
    NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [NSMutableDictionary dictionary];
    userInfo[NSLocalizedDescriptionKey] = description;
    if (underlying != nil) {
        userInfo[NSUnderlyingErrorKey] = underlying;
    }
    return [NSError errorWithDomain:NBWiFiBridgeErrorDomain code:code userInfo:userInfo];
}

/// `YES` when `interface` is powered on or is associated with a network.
static BOOL NBInterfaceLooksActive(CWInterface *_Nullable interface) {
    if (interface == nil) {
        return NO;
    }
    return interface.powerOn || interface.rssiValue != 0 || interface.ssid != nil;
}

/// Picks the Wi-Fi interface NetBar should describe.
///
/// Preference order: an interface that is on or associated, the interface
/// CWWiFiClient considers default, the conventional `en0`, then the first one
/// the system listed. Returns nil only on a machine without Wi-Fi hardware.
static CWInterface *_Nullable NBResolveInterface(void) {
    CWWiFiClient *client = CWWiFiClient.sharedWiFiClient;

    for (NSString *name in client.interfaceNames) {
        CWInterface *candidate = [client interfaceWithName:name];
        if (NBInterfaceLooksActive(candidate)) {
            return candidate;
        }
    }

    CWInterface *defaultInterface = client.interface;
    if (defaultInterface != nil) {
        return defaultInterface;
    }

    CWInterface *conventionalInterface = [client interfaceWithName:NBFallbackInterfaceName];
    if (conventionalInterface != nil) {
        return conventionalInterface;
    }

    return client.interfaces.firstObject;
}

/// Security classification, strongest first so a transitional network reads as its modern tier.
/// WPA3 before WPA2 before WPA before WEP; enterprise suites fold into `NBWiFiSecurityEnterprise`.
static NBWiFiSecurity NBWiFiSecurityFromNetwork(CWNetwork *network) {
    if ([network supportsSecurity:kCWSecurityWPA3Personal] || [network supportsSecurity:kCWSecurityWPA3Enterprise]
        || [network supportsSecurity:kCWSecurityWPA3Transition] || [network supportsSecurity:kCWSecurityOWE]
        || [network supportsSecurity:kCWSecurityOWETransition]) {
        return NBWiFiSecurityWPA3;
    }
    if ([network supportsSecurity:kCWSecurityWPA2Enterprise] || [network supportsSecurity:kCWSecurityEnterprise]
        || [network supportsSecurity:kCWSecurityWPAEnterprise]
        || [network supportsSecurity:kCWSecurityWPAEnterpriseMixed]) {
        return NBWiFiSecurityEnterprise;
    }
    if ([network supportsSecurity:kCWSecurityWPA2Personal] || [network supportsSecurity:kCWSecurityWPAPersonalMixed]
        || [network supportsSecurity:kCWSecurityPersonal]) {
        return NBWiFiSecurityWPA2;
    }
    if ([network supportsSecurity:kCWSecurityWPAPersonal]) {
        return NBWiFiSecurityWPA;
    }
    if ([network supportsSecurity:kCWSecurityWEP] || [network supportsSecurity:kCWSecurityDynamicWEP]) {
        return NBWiFiSecurityWEP;
    }
    return NBWiFiSecurityOpen;
}

/// Newest physical layer the network advertises. `-[CWNetwork supportsPHYMode:]` answers YES for
/// every mode at or below the network's real one, so the search runs newest first.
static NBWiFiPHYMode NBWiFiPHYModeFromNetwork(CWNetwork *network) {
    static const CWPHYMode modesNewestFirst[] = {
        kCWPHYMode11be, kCWPHYMode11ax, kCWPHYMode11ac, kCWPHYMode11n,
        kCWPHYMode11g, kCWPHYMode11b, kCWPHYMode11a,
    };
    static const NBWiFiPHYMode equivalentsNewestFirst[] = {
        NBWiFiPHYMode80211be, NBWiFiPHYMode80211ax, NBWiFiPHYMode80211ac, NBWiFiPHYMode80211n,
        NBWiFiPHYMode80211g, NBWiFiPHYMode80211b, NBWiFiPHYMode80211a,
    };
    const NSUInteger modeCount = sizeof(modesNewestFirst) / sizeof(modesNewestFirst[0]);
    for (NSUInteger index = 0; index < modeCount; index++) {
        if ([network supportsPHYMode:modesNewestFirst[index]]) {
            return equivalentsNewestFirst[index];
        }
    }
    return NBWiFiPHYModeUnknown;
}

/// Maps ESSIDs to the name of the preferred-network profile that owns them.
///
/// Profiles are keyed by `ssidData` rather than by `ssid` string: identical
/// bytes are the same ESSID regardless of how the frame encoded the name, and
/// two profiles can only share a key when one is a byte-for-byte duplicate.
static NSDictionary<NSData *, NSString *> *NBMapServiceNamesBySSIDData(CWInterface *interface) {
    NSMutableDictionary<NSData *, NSString *> *namesBySSIDData = [NSMutableDictionary dictionary];
    for (CWNetworkProfile *profile in interface.configuration.networkProfiles) {
        NSData *serviceNameData = profile.ssidData;
        NSString *serviceName = profile.ssid;
        if (serviceNameData.length == 0 || serviceName.length == 0) {
            continue;
        }
        if (namesBySSIDData[serviceNameData] == nil) {
            namesBySSIDData[serviceNameData] = serviceName;
        }
    }
    return namesBySSIDData;
}

/// Builds one `NBScannedNetwork` from a CoreWLAN scan result.
static NBScannedNetwork *NBScannedNetworkFromNetwork(
    CWNetwork *network,
    NSDictionary<NSData *, NSString *> *serviceNamesBySSIDData,
    NSString *_Nullable currentSSID) {
    NBScannedNetwork *scanned = [[NBScannedNetwork alloc] init];

    NSString *ssid = network.ssid;
    NSData *ssidData = network.ssidData;
    NSString *serviceName = nil;
    if (ssidData.length > 0) {
        serviceName = serviceNamesBySSIDData[ssidData];
    }

    scanned.ssid = ssid;
    scanned.serviceName = serviceName;
    scanned.bssid = network.bssid;
    scanned.rssi = network.rssiValue;
    scanned.security = NBWiFiSecurityFromNetwork(network);
    scanned.phyMode = NBWiFiPHYModeFromNetwork(network);

    CWChannel *channel = network.wlanChannel;
    scanned.channel = channel != nil ? channel.channelNumber : NBUnknownChannel;

    BOOL isCurrentNetwork = ssid.length > 0 && currentSSID.length > 0 && [ssid isEqualToString:currentSSID];
    scanned.known = serviceName != nil || isCurrentNetwork;

    NBHotspotInfo hotspot = NBHotspotParseInformationElements(network.informationElementData);
    scanned.personalHotspot = hotspot.isPersonalHotspot;
    scanned.hotspotNetwork = hotspot.network;
    scanned.hotspotBattery = hotspot.batteryPercent;
    scanned.carriesHotspotInformation = hotspot.carriesHotspotInformation;

    return scanned;
}

#pragma mark - Bridge

@implementation NBWiFiBridge

+ (nullable NSString *)defaultInterfaceName {
    return NBResolveInterface().interfaceName;
}

+ (NBSnapshot *)captureState {
    NBSnapshot *snapshot = [[NBSnapshot alloc] init];
    CWInterface *interface = NBResolveInterface();
    if (interface == nil) {
        // Machines without a Wi-Fi radio: a valid, empty snapshot.
        snapshot.powerOn = NO;
        snapshot.namesAvailable = YES;
        return snapshot;
    }

    snapshot.interfaceName = interface.interfaceName;
    snapshot.powerOn = interface.powerOn;
    snapshot.currentSSID = interface.ssid;
    snapshot.currentBSSID = interface.bssid;
    snapshot.currentRSSI = interface.rssiValue;
    // State use is cheap enough to call synchronously; the connected network is
    // described by its own scan record, so the hotspot fields stay at defaults here.
    snapshot.namesAvailable = YES;
    return snapshot;
}

+ (NBSnapshot *)captureSnapshot {
    NBSnapshot *snapshot = [self captureState];
    CWInterface *interface = NBResolveInterface();
    if (interface == nil || !interface.powerOn) {
        return snapshot;
    }

    NSDictionary<NSData *, NSString *> *serviceNamesBySSIDData = NBMapServiceNamesBySSIDData(interface);
    NSString *currentSSID = interface.ssid;

    NSSet<CWNetwork *> *scanResults = [interface scanForNetworksWithName:nil error:nil];
    NSMutableArray<NBScannedNetwork *> *networks = [NSMutableArray arrayWithCapacity:scanResults.count];
    BOOL allNamesRedacted = scanResults.count > 0;
    for (CWNetwork *network in scanResults) {
        NBScannedNetwork *scanned = NBScannedNetworkFromNetwork(network,
                                                                serviceNamesBySSIDData,
                                                                currentSSID);
        allNamesRedacted = allNamesRedacted && scanned.ssid == nil;
        [networks addObject:scanned];
    }

    [networks sortUsingComparator:^NSComparisonResult(NBScannedNetwork *left, NBScannedNetwork *right) {
        // Strongest signal first; ties keep a deterministic order by BSSID, nil BSSIDs last.
        if (left.rssi != right.rssi) {
            return left.rssi > right.rssi ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left.bssid ?: @"" compare:right.bssid ?: @""];
    }];
    snapshot.networks = networks;

    if (allNamesRedacted) {
        snapshot.namesAvailable = NO;
        snapshot.namesUnavailableReason = NBNamesUnavailableReason;
    }

    [self describe:snapshot connectedNetworkIn:networks];
    return snapshot;
}

/// Copies hotspot metadata of the network the interface is associated with onto `snapshot`.
///
/// The scan record is the only place CoreWLAN exposes information elements, so the
/// current network's entry is located by BSSID. When macOS withholds BSSIDs as well
/// as names, the strongest record is a sound stand-in: the radio always hears the
/// access point it is associated with better than any neighbour.
+ (void)describe:(NBSnapshot *)snapshot connectedNetworkIn:(NSArray<NBScannedNetwork *> *)networks {
    if (networks.count == 0) {
        return;
    }
    BOOL currentBSSIDIsKnown = snapshot.currentBSSID.length > 0;
    for (NBScannedNetwork *network in networks) {
        if (currentBSSIDIsKnown && !(network.bssid != nil && [network.bssid isEqualToString:snapshot.currentBSSID])) {
            continue;
        }
        snapshot.currentIsPersonalHotspot = network.personalHotspot;
        // "Apple personal hotspot" means the frame carried hotspot metadata at all; a phone that
        // shares a 5G connection is still an Apple hotspot even when it reports no cellular type.
        snapshot.currentIsApplePersonalHotspot = network.carriesHotspotInformation;
        snapshot.currentHotspotNetwork = network.hotspotNetwork;
        snapshot.currentHotspotBattery = network.hotspotBattery;
        return;
    }
}

+ (NSArray<NSString *> *)preferredNetworkNames {
    CWInterface *interface = NBResolveInterface();
    if (interface == nil) {
        return @[];
    }

    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    for (CWNetworkProfile *profile in interface.configuration.networkProfiles) {
        NSString *name = profile.ssid;
        if (name.length > 0) {
            [names addObject:name];
        }
    }
    return [names.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

+ (BOOL)setPowerOn:(BOOL)powerOn error:(NSError **)error {
    CWInterface *interface = NBResolveInterface();
    if (interface == nil) {
        if (error != NULL) {
            *error = NBMakeBridgeError(NBWiFiBridgeErrorInterfaceUnavailable,
                                        @"No Wi-Fi interface is available.",
                                        nil);
        }
        return NO;
    }
    if (interface.powerOn == powerOn) {
        return YES;
    }

    NSError *coreWLANError = nil;
    // `-[CWInterface setPower:error:]` carries no deprecation attribute in the macOS 27 SDK and the
    // header lists no replacement, so it is the supported way to toggle the radio. The diagnostic
    // guard is kept deliberately: an SDK that does mark it deprecated must stay warning-free rather
    // than silently breaking the build's -Werror policy.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    BOOL succeeded = [interface setPower:powerOn error:&coreWLANError];
#pragma clang diagnostic pop

    if (succeeded) {
        return YES;
    }
    if (error != NULL) {
        NSString *description = powerOn ? @"Wi-Fi could not be turned on." : @"Wi-Fi could not be turned off.";
        *error = NBMakeBridgeError(NBWiFiBridgeErrorPower, description, coreWLANError);
    }
    return NO;
}

+ (void)openWiFiSettings {
    [self openSettingsURLString:NBWiFiSettingsURLString];
}

+ (void)openPrivacySettings {
    [self openSettingsURLString:NBPrivacySettingsURLString];
}

/// Hands a System Settings pane link to LaunchServices. The link is resolved by
/// the system Settings app; NetBar never launches or talks to anything itself.
+ (void)openSettingsURLString:(NSString *)URLString {
    NSURL *url = [NSURL URLWithString:URLString];
    if (url == nil) {
        return;
    }
    [NSWorkspace.sharedWorkspace openURL:url];
}

@end

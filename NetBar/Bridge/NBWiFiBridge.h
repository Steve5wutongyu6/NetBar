//
//  NBWiFiBridge.h
//  NetBar
//
//  Read-only view over CoreWLAN. Calls are synchronous and must run off the
//  main thread; a scan blocks for up to two seconds.
//
//  Two pieces of data survive macOS redacting network names (which happens when
//  the app is not authorized in Privacy & Security > Location Services):
//  the preferred-network profile names and the Apple hotspot information
//  elements in beacon frames. The bridge reports both so the engine can still
//  group and label networks; everything else that needs a *name* degrades to
//  `namesAvailable == NO`.
//

#import <Foundation/Foundation.h>
#import "NBWiFiModels.h"

NS_ASSUME_NONNULL_BEGIN

/// `NSErrorDomain` of the errors this bridge reports.
FOUNDATION_EXPORT NSString *const NBWiFiBridgeErrorDomain;

typedef NS_ENUM(NSInteger, NBWiFiBridgeError) {
    /// The radio did not accept a new power state.
    NBWiFiBridgeErrorPower = 1,
    /// No Wi-Fi interface could be found on the system.
    NBWiFiBridgeErrorInterfaceUnavailable = 2,
    /// The chosen network disappeared between the scan and the click.
    NBWiFiBridgeErrorNetworkNotFound = 3,
    /// The radio refused the association, usually for a missing password.
    NBWiFiBridgeErrorJoin = 4,
};

@interface NBWiFiBridge : NSObject

/// Interface name of the primary Wi-Fi service, e.g. `en0`.
+ (nullable NSString *)defaultInterfaceName;

/// Captures interface state and performs one scan.
///
/// The scan blocks for up to two seconds. Every scanned network carries its
/// `security` and `phyMode`, its `known` flag and, when a saved profile belongs
/// to it, the profile's `serviceName`.
+ (NBSnapshot *)captureSnapshot;

/// Settles connection state without scanning; cheap enough for event handlers.
+ (NBSnapshot *)captureState;

/// Names of every preferred network in the interface configuration, deduped and
/// sorted case-insensitively. Comes from `-[CWConfiguration networkProfiles]`,
/// so it stays populated even when macOS redacts SSIDs for this process. This is
/// what the app sends to the engine as the "saved networks" list.
+ (NSArray<NSString *> *)preferredNetworkNames;

/// Joins the network with this SSID, starting the system's own association
/// process. Saved networks use the password already in the keychain, so no
/// credential is passed; an unknown secured network returns an error and the
/// caller falls back to the system Wi-Fi pane.
///
/// Blocks while the radio associates, so call it off the main thread.
+ (BOOL)joinNetworkWithSSID:(NSString *)ssid error:(NSError **)error;

/// Turns the Wi-Fi radio on or off. Returns NO and fills `error` on failure.
+ (BOOL)setPowerOn:(BOOL)powerOn error:(NSError **)error;

/// Opens the system Wi-Fi settings pane for the active interface.
+ (void)openWiFiSettings;

/// Opens the Privacy pane; offered when network names are unavailable.
+ (void)openPrivacySettings;

@end

NS_ASSUME_NONNULL_END

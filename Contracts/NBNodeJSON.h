//
//  NBNodeJSON.h
//  NetBar engine <-> app contract, compiled unchanged into the Rust staticlib
//  and the app (via the bridging header). The Rust `netbar_node_json` entry
//  point accepts an NBEngineInput and returns an NBEngineOutput; both are
//  encoded/decoded with NSJSONSerialization in the bridge so the wire format
//  stays independent of toolchain versions.
//

#import <Foundation/Foundation.h>
#import "NBWiFiModels.h"

NS_ASSUME_NONNULL_BEGIN

/// The wire format version both sides implement.
extern const NSInteger NBEngineSchemaVersion;

typedef NS_ENUM(NSInteger, NBItemRole) {
    NBItemRoleHeader = 0,
    NBItemRoleNetwork = 1,
    NBItemRoleOtherNetworks = 2,
    NBItemRoleSettings = 3,
};

typedef NS_ENUM(NSInteger, NBItemSection) {
    NBItemSectionHotspot = 0,
    NBItemSectionKnown = 1,
    NBItemSectionOther = 2,
    NBItemSectionFooter = 3,
};

typedef NS_ENUM(NSInteger, NBDetailKind) {
    NBDetailKindNone = 0,
    NBDetailKindLock = 1,
    NBDetailKindAppleHotspot = 2,
};

typedef NS_ENUM(NSInteger, NBCellIndicator) {
    NBCellIndicatorNone = 0,
    NBCellIndicatorLTE = 1,
    NBCellIndicatorFiveG = 2,
};

/// A network as the bridge reports it. Mirrors the JSON object the app sends.
@interface NBEngineNetwork : NSObject <NSCopying>
@property (nonatomic, copy, nullable) NSString *ssid;
@property (nonatomic, copy, nullable) NSString *serviceName;
@property (nonatomic, copy, nullable) NSString *bssid;
/// Signal strength in dBm.
@property (nonatomic) NSInteger rssi;
@property (nonatomic) NBWiFiSecurity security;
@property (nonatomic) NBWiFiPHYMode phyMode;
@property (nonatomic) NSInteger channel;
@property (nonatomic) BOOL known;
@property (nonatomic) BOOL personalHotspot;
@property (nonatomic) NBHotspotNetwork hotspotNetwork;
/// Battery percentage advertised by an Apple hotspot, 0 when unknown.
@property (nonatomic) NSInteger hotspotBattery;
@end

@interface NBEngineInput : NSObject <NSCopying>
@property (nonatomic, copy) NSArray<NSString *> *preferredNetworks;
@property (nonatomic) NSInteger schemaVersion;
@property (nonatomic) BOOL powerOn;
@property (nonatomic, copy, nullable) NSString *currentSSID;
@property (nonatomic) BOOL connectedNameRedacted;
@property (nonatomic, copy, nullable) NSString *interfaceName;
@property (nonatomic) NSInteger currentRSSI;
@property (nonatomic) BOOL scanning;
/// YES once the user unfolds "Other Networks": the engine then returns every
/// remaining network instead of the two it shows by default.
@property (nonatomic) BOOL revealOther;
@property (nonatomic, copy) NSArray<NBEngineNetwork *> *networks;

/// Wire representation consumed by `netbar_node_json`.
- (nullable NSData *)jsonData;
@end

/// One row of the menu.
@interface NBEngineItem : NSObject
@property (nonatomic) NBItemRole role;
@property (nonatomic) NBItemSection section;
/// Stable identity across refreshes; unique within an output.
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *ssid;
@property (nonatomic) NBWiFiSecurity security;
@property (nonatomic) NSInteger rssi;
@property (nonatomic) BOOL isJoined;
@property (nonatomic) NBDetailKind detailKind;
@property (nonatomic) NBCellIndicator cell;
@property (nonatomic) NSInteger battery;
/// Wi-Fi bars, 0 through 4.
@property (nonatomic) NSInteger strength;
@property (nonatomic) BOOL redacted;
@end

@interface NBEngineOutput : NSObject
@property (nonatomic) NSInteger schemaVersion;
@property (nonatomic, copy, nullable) NSString *statusTitle;
@property (nonatomic) BOOL statusNeedsSetup;
@property (nonatomic, copy) NSArray<NBEngineItem *> *items;
@property (nonatomic) NSInteger hiddenOtherCount;
@property (nonatomic, copy, nullable) NSString *connectedName;
@property (nonatomic) BOOL connectedIsHotspot;
@property (nonatomic) NBCellIndicator connectedCell;
@property (nonatomic) NSInteger connectedBattery;
/// Wi-Fi bars (0...4) for the joined network, used by the status item glyph.
@property (nonatomic) NSInteger connectedStrength;

@end

/// Decodes the engine reply; returns nil when the reply is not a JSON object.
FOUNDATION_EXPORT NBEngineOutput *_Nullable NBEngineOutputFromJSONData(NSData *data);

NS_ASSUME_NONNULL_END

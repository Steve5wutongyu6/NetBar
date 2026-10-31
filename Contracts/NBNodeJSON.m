//
//  NBNodeJSON.m
//  NetBar
//
//  Builds the JSON the Rust engine accepts and decodes the JSON it returns.
//

#import "NBNodeJSON.h"

const NSInteger NBEngineSchemaVersion = 1;

static NSString *const NBKeySchemaVersion = @"schemaVersion";
static NSString *const NBKeyPowerOn = @"powerOn";
static NSString *const NBKeyCurrentSSID = @"currentSSID";
static NSString *const NBKeyConnectedNameRedacted = @"connectedNameRedacted";
static NSString *const NBKeyInterfaceName = @"interfaceName";
static NSString *const NBKeyCurrentRSSI = @"currentRSSI";
static NSString *const NBKeyScanning = @"scanning";
static NSString *const NBKeyRevealOther = @"revealOther";
static NSString *const NBKeyCurrentIsPersonalHotspot = @"currentIsPersonalHotspot";
static NSString *const NBKeyCurrentHotspotNetwork = @"currentHotspotNetwork";
static NSString *const NBKeyCurrentHotspotBattery = @"currentHotspotBattery";
static NSString *const NBKeyNetworks = @"networks";

static NSString *const NBKeyPreferredNetworks = @"preferredNetworks";
static NSString *const NBKeySSID = @"ssid";
static NSString *const NBKeyServiceName = @"serviceName";
static NSString *const NBKeyBSSID = @"bssid";
static NSString *const NBKeyRSSI = @"rssi";
static NSString *const NBKeySecurity = @"security";
static NSString *const NBKeyPHYMode = @"phyMode";
static NSString *const NBKeyChannel = @"channel";
static NSString *const NBKeyKnown = @"known";
static NSString *const NBKeyPersonalHotspot = @"personalHotspot";
static NSString *const NBKeyHotspotNetwork = @"hotspotNetwork";
static NSString *const NBKeyHotspotBattery = @"hotspotBattery";

static NSString *const NBKeyStatusTitle = @"statusTitle";
static NSString *const NBKeyStatusNeedsSetup = @"statusNeedsSetup";
static NSString *const NBKeyItems = @"items";
static NSString *const NBKeyHiddenOtherCount = @"hiddenOtherCount";
static NSString *const NBKeyConnectedName = @"connectedName";
static NSString *const NBKeyConnectedIsHotspot = @"connectedIsHotspot";
static NSString *const NBKeyConnectedCell = @"connectedCell";
static NSString *const NBKeyConnectedBattery = @"connectedBattery";
static NSString *const NBKeyConnectedStrength = @"connectedStrength";

static NSString *const NBKeyRole = @"role";
static NSString *const NBKeySection = @"section";
static NSString *const NBKeyID = @"id";
static NSString *const NBKeyTitle = @"title";
static NSString *const NBKeyIsJoined = @"isJoined";
static NSString *const NBKeyDetailKind = @"detailKind";
static NSString *const NBKeyCell = @"cell";
static NSString *const NBKeyBattery = @"battery";
static NSString *const NBKeyStrength = @"strength";
static NSString *const NBKeyRedacted = @"redacted";

static NSInteger NBInteger(id value)
{
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

static NSString *NBString(id value)
{
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static BOOL NBFlag(id value)
{
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

static NSData *NBJSONData(id object)
{
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
}

#pragma mark - Input

@implementation NBEngineNetwork

- (id)copyWithZone:(NSZone *)zone
{
    NBEngineNetwork *copy = [[NBEngineNetwork allocWithZone:zone] init];
    copy.ssid = self.ssid;
    copy.serviceName = self.serviceName;
    copy.bssid = self.bssid;
    copy.rssi = self.rssi;
    copy.security = self.security;
    copy.phyMode = self.phyMode;
    copy.channel = self.channel;
    copy.known = self.known;
    copy.personalHotspot = self.personalHotspot;
    copy.hotspotNetwork = self.hotspotNetwork;
    copy.hotspotBattery = self.hotspotBattery;
    return copy;
}

- (NSDictionary *)jsonObject
{
    return @{
        NBKeySSID: self.ssid ?: NSNull.null,
        NBKeyServiceName: self.serviceName ?: NSNull.null,
        NBKeyBSSID: self.bssid ?: NSNull.null,
        NBKeyRSSI: @(self.rssi),
        NBKeySecurity: @(self.security),
        NBKeyPHYMode: @(self.phyMode),
        NBKeyChannel: @(self.channel),
        NBKeyKnown: @(self.known),
        NBKeyPersonalHotspot: @(self.personalHotspot),
        NBKeyHotspotNetwork: @(self.hotspotNetwork),
        NBKeyHotspotBattery: @(self.hotspotBattery),
    };
}

@end

@implementation NBEngineInput

- (instancetype)init
{
    self = [super init];
    if (self) {
        _schemaVersion = NBEngineSchemaVersion;
        _networks = @[];
        _preferredNetworks = @[];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    NBEngineInput *copy = [[NBEngineInput allocWithZone:zone] init];
    copy.preferredNetworks = self.preferredNetworks;
    copy.schemaVersion = self.schemaVersion;
    copy.powerOn = self.powerOn;
    copy.currentSSID = self.currentSSID;
    copy.connectedNameRedacted = self.connectedNameRedacted;
    copy.interfaceName = self.interfaceName;
    copy.currentRSSI = self.currentRSSI;
    copy.scanning = self.scanning;
    copy.revealOther = self.revealOther;
    copy.currentIsPersonalHotspot = self.currentIsPersonalHotspot;
    copy.currentHotspotNetwork = self.currentHotspotNetwork;
    copy.currentHotspotBattery = self.currentHotspotBattery;
    copy.networks = self.networks;
    return copy;
}

- (NSData *)jsonData
{
    NSMutableArray *networks = [NSMutableArray arrayWithCapacity:self.networks.count];
    for (NBEngineNetwork *network in self.networks) {
        [networks addObject:[network jsonObject]];
    }
    NSDictionary *object = @{
        NBKeyPreferredNetworks: self.preferredNetworks,
        NBKeySchemaVersion: @(self.schemaVersion),
        NBKeyPowerOn: @(self.powerOn),
        NBKeyCurrentSSID: self.currentSSID ?: NSNull.null,
        NBKeyConnectedNameRedacted: @(self.connectedNameRedacted),
        NBKeyInterfaceName: self.interfaceName ?: NSNull.null,
        NBKeyCurrentRSSI: @(self.currentRSSI),
        NBKeyScanning: @(self.scanning),
        NBKeyRevealOther: @(self.revealOther),
        NBKeyCurrentIsPersonalHotspot: @(self.currentIsPersonalHotspot),
        NBKeyCurrentHotspotNetwork: @(self.currentHotspotNetwork),
        NBKeyCurrentHotspotBattery: @(self.currentHotspotBattery),
        NBKeyNetworks: networks,
    };
    return [NSJSONSerialization isValidJSONObject:object] ? NBJSONData(object) : nil;
}

@end

#pragma mark - Output

@interface NBEngineItem ()
- (instancetype)initWithJSONObject:(NSDictionary *)object;
@end

@implementation NBEngineItem

- (instancetype)initWithJSONObject:(NSDictionary *)object
{
    self = [super init];
    if (self) {
        _role = (NBItemRole)NBInteger(object[NBKeyRole]);
        _section = (NBItemSection)NBInteger(object[NBKeySection]);
        _identifier = NBString(object[NBKeyID]) ?: @"";
        _title = NBString(object[NBKeyTitle]);
        _ssid = NBString(object[NBKeySSID]);
        _security = (NBWiFiSecurity)NBInteger(object[NBKeySecurity]);
        _rssi = NBInteger(object[NBKeyRSSI]);
        _isJoined = NBFlag(object[NBKeyIsJoined]);
        _detailKind = (NBDetailKind)NBInteger(object[NBKeyDetailKind]);
        _cell = (NBCellIndicator)NBInteger(object[NBKeyCell]);
        _battery = NBInteger(object[NBKeyBattery]);
        _strength = NBInteger(object[NBKeyStrength]);
        _redacted = NBFlag(object[NBKeyRedacted]);
    }
    return self;
}

@end

@implementation NBEngineOutput

- (instancetype)init
{
    self = [super init];
    if (self) {
        _schemaVersion = NBEngineSchemaVersion;
        _items = @[];
    }
    return self;
}

NBEngineOutput *NBEngineOutputFromJSONData(NSData *data)
{
    if (data.length == 0) {
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSDictionary *json = object;
    NBEngineOutput *output = [[NBEngineOutput alloc] init];
    output.schemaVersion = NBInteger(json[NBKeySchemaVersion]);
    output.statusTitle = NBString(json[NBKeyStatusTitle]);
    output.statusNeedsSetup = NBFlag(json[NBKeyStatusNeedsSetup]);
    output.hiddenOtherCount = NBInteger(json[NBKeyHiddenOtherCount]);
    output.connectedName = NBString(json[NBKeyConnectedName]);
    output.connectedIsHotspot = NBFlag(json[NBKeyConnectedIsHotspot]);
    output.connectedCell = (NBCellIndicator)NBInteger(json[NBKeyConnectedCell]);
    output.connectedBattery = NBInteger(json[NBKeyConnectedBattery]);
    output.connectedStrength = NBInteger(json[NBKeyConnectedStrength]);

    NSMutableArray<NBEngineItem *> *items = [NSMutableArray array];
    id rawItems = json[NBKeyItems];
    if ([rawItems isKindOfClass:NSArray.class]) {
        for (id rawItem in (NSArray *)rawItems) {
            if ([rawItem isKindOfClass:NSDictionary.class]) {
                [items addObject:[[NBEngineItem alloc] initWithJSONObject:rawItem]];
            }
        }
    }
    output.items = items;
    return output;
}

@end

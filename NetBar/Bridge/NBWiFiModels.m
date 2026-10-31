//
//  NBWiFiModels.m
//  NetBar
//

#import "NBWiFiModels.h"

@implementation NBScannedNetwork

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ ssid=%@ rssi=%ld known=%d hotspot=%d>",
            NSStringFromClass(self.class), self.ssid, (long)self.rssi, self.known, self.personalHotspot];
}

@end

@implementation NBSnapshot

- (instancetype)init
{
    self = [super init];
    if (self) {
        _networks = @[];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<NBSnapshot interface=%@ power=%d ssid=%@ networks=%lu names=%d>",
            self.interfaceName, self.powerOn, self.currentSSID, (unsigned long)self.networks.count,
            self.namesAvailable];
}

@end

//
//  NBWiFiMonitor.m
//  NetBar
//

#import "NBWiFiMonitor.h"

#import <CoreWLAN/CoreWLAN.h>

/// Radio events arrive in bursts — a link change also reports a new signal — so
/// they are coalesced before the handler runs.
static const NSTimeInterval NBCoalesceInterval = 0.25;

@interface NBWiFiMonitor () <CWEventDelegate>
@property (nonatomic, strong) CWWiFiClient *client;
@property (nonatomic, copy, nullable) NBWiFiChangeHandler handler;
@property (nonatomic) BOOL observing;
/// Guarded by `stateLock`: the coalescing flag is touched from the delegate queue
/// and from the main queue the delivery runs on.
@property (nonatomic) BOOL deliveryPending;
@property (nonatomic, strong) NSLock *stateLock;
@end

@implementation NBWiFiMonitor

+ (instancetype)sharedMonitor
{
    static NBWiFiMonitor *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[NBWiFiMonitor alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _client = [CWWiFiClient sharedWiFiClient];
        _stateLock = [[NSLock alloc] init];
    }
    return self;
}

- (void)startObserving:(NBWiFiChangeHandler)handler
{
    self.handler = handler;
    if (self.observing) {
        return;
    }
    self.client.delegate = self;

    NSArray<NSNumber *> *events = @[
        @(CWEventTypePowerDidChange),
        @(CWEventTypeSSIDDidChange),
        @(CWEventTypeBSSIDDidChange),
        @(CWEventTypeLinkDidChange),
        @(CWEventTypeLinkQualityDidChange),
        @(CWEventTypeScanCacheUpdated),
    ];
    for (NSNumber *event in events) {
        NSError *error = nil;
        [self.client startMonitoringEventWithType:(CWEventType)event.integerValue error:&error];
        if (error != nil) {
            // A single unavailable event type is not fatal; the rest still report.
            continue;
        }
    }
    self.observing = YES;
}

- (void)stop
{
    if (!self.observing) {
        return;
    }
    [self.client stopMonitoringAllEventsAndReturnError:nil];
    self.client.delegate = nil;
    self.observing = NO;
    self.handler = nil;
}

#pragma mark - Change reporting

/// Coalesces a burst into one callback.
- (void)reportChange
{
    [self.stateLock lock];
    BOOL alreadyPending = self.deliveryPending;
    self.deliveryPending = YES;
    [self.stateLock unlock];
    if (self.handler == nil || alreadyPending) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NBCoalesceInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) self_ = weakSelf;
        if (self_ == nil) {
            return;
        }
        [self_.stateLock lock];
        self_.deliveryPending = NO;
        [self_.stateLock unlock];
        NBWiFiChangeHandler handler = self_.handler;
        if (handler != nil) {
            handler();
        }
    });
}

#pragma mark - CWEventDelegate

- (void)powerStateDidChangeForWiFiInterfaceWithName:(NSString *)interfaceName
{
    [self reportChange];
}

- (void)ssidDidChangeForWiFiInterfaceWithName:(NSString *)interfaceName
{
    [self reportChange];
}

- (void)bssidDidChangeForWiFiInterfaceWithName:(NSString *)interfaceName
{
    [self reportChange];
}

- (void)linkDidChangeForWiFiInterfaceWithName:(NSString *)interfaceName
{
    [self reportChange];
}

- (void)linkQualityDidChangeForWiFiInterfaceWithName:(NSString *)interfaceName
                                               rssi:(NSInteger)rssi
                                      transmitRate:(double)transmitRate
{
    [self reportChange];
}

- (void)modeDidChangeForWiFiInterfaceWithName:(NSString *)interfaceName
{
    [self reportChange];
}

- (void)scanCacheUpdatedForWiFiInterfaceWithName:(NSString *)interfaceName
{
    [self reportChange];
}

- (void)clientConnectionInterrupted
{
    // The daemon restarted; resubscribe so the status item keeps updating.
    self.observing = NO;
    if (self.handler != nil) {
        NBWiFiChangeHandler handler = self.handler;
        [self startObserving:handler];
    }
}

- (void)clientConnectionInvalidated
{
    self.observing = NO;
}

@end

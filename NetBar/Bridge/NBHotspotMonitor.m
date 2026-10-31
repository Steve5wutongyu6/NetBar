//
//  NBHotspotMonitor.m
//  NetBar
//

#import "NBHotspotMonitor.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const NBSharingFrameworkPath =
    @"/System/Library/PrivateFrameworks/Sharing.framework/Sharing";
static NSString *const NBHotspotSessionClass = @"SFRemoteHotspotSession";
static NSString *const NBHotspotSessionDelegateSelector = @"session:updatedFoundDevices:";

@implementation NBHotspotPeer

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ battery=%ld network=%@ bars=%ld>",
            NSStringFromClass(self.class), self.name, (long)self.batteryPercent,
            self.networkLabel ?: @"?", (long)self.signalBars];
}

@end

@interface NBHotspotMonitor ()
@property (nonatomic, strong) id session;
@property (nonatomic, strong) NSMutableArray<NBHotspotPeer *> *mutablePeers;
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic) BOOL browsing;
@end

@implementation NBHotspotMonitor

+ (instancetype)shared
{
    static NBHotspotMonitor *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[NBHotspotMonitor alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _mutablePeers = [NSMutableArray array];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

#pragma mark - Public

- (NSArray<NBHotspotPeer *> *)peers
{
    [self.lock lock];
    NSArray<NBHotspotPeer *> *copy = [self.mutablePeers copy];
    [self.lock unlock];
    return copy;
}

- (void)start
{
    if (self.browsing) {
        return;
    }
    id session = [self makeSession];
    if (session == nil) {
        return;
    }
    self.session = session;
    ((void (*)(id, SEL))objc_msgSend)(session, sel_registerName("startBrowsing"));
    self.browsing = YES;
}

- (void)stop
{
    if (!self.browsing) {
        return;
    }
    if (self.session != nil) {
        ((void (*)(id, SEL))objc_msgSend)(self.session, sel_registerName("stopBrowsing"));
    }
    self.session = nil;
    self.browsing = NO;
    [self.lock lock];
    [self.mutablePeers removeAllObjects];
    [self.lock unlock];
}

#pragma mark - Session lifecycle

/// Builds a browsing session, or nil when the framework is not available.
- (nullable id)makeSession
{
    static dispatch_once_t once;
    static BOOL loaded;
    dispatch_once(&once, ^{
        loaded = dlopen(NBSharingFrameworkPath.UTF8String, RTLD_LAZY) != NULL;
    });
    if (!loaded) {
        return nil;
    }
    Class sessionClass = NSClassFromString(NBHotspotSessionClass);
    if (sessionClass == Nil) {
        return nil;
    }
    id session = ((id (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(sessionClass,
                                                                              sel_registerName("alloc")),
                                                 sel_registerName("init"));
    if (session == nil) {
        return nil;
    }
    SEL delegateSelector = sel_registerName("setDelegate:");
    if (![session respondsToSelector:delegateSelector]) {
        return nil;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(session, delegateSelector, self);
    return session;
}

/// The framework calls this whenever the set of sharing devices changes.
- (void)session:(id)session updatedFoundDevices:(NSArray *)devices
{
    NSMutableArray<NBHotspotPeer *> *peers = [NSMutableArray arrayWithCapacity:devices.count];
    for (id device in devices) {
        NBHotspotPeer *peer = [self peerFromDevice:device];
        if (peer != nil) {
            [peers addObject:peer];
        }
    }
    [peers sortUsingComparator:^NSComparisonResult(NBHotspotPeer *left, NBHotspotPeer *right) {
        if (left.signalBars != right.signalBars) {
            return left.signalBars > right.signalBars ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left.name compare:right.name];
    }];
    [self.lock lock];
    self.mutablePeers = peers;
    [self.lock unlock];
}

#pragma mark - Device decoding

/// Reads one device. Only the three fields the menu shows are used, and each is
/// read defensively: the framework is private and its shape can change.
- (nullable NBHotspotPeer *)peerFromDevice:(id)device
{
    if (device == nil) {
        return nil;
    }
    NSString *name = [self objectFrom:device selector:"deviceName"];
    if (name.length == 0) {
        return nil;
    }
    NBHotspotPeer *peer = [[NBHotspotPeer alloc] init];
    peer.name = name;

    NSNumber *battery = [self objectFrom:device selector:"batteryLife"];
    // The device reports a percentage; anything else is clamped rather than shown.
    peer.batteryPercent = battery == nil ? 0 : MIN(MAX(battery.integerValue, 0), 100);

    NSNumber *signal = [self objectFrom:device selector:"signalStrength"];
    peer.signalBars = signal == nil ? 0 : MIN(MAX(signal.integerValue, 0), 4);

    peer.networkLabel = [self networkLabelFromDevice:device];
    return peer;
}

/// The generation label, as the device itself names it. The numeric network type
/// is a private enum whose values are not documented, so the label is taken from
/// the device's own description, which spells it out ("network type: 4G").
- (nullable NSString *)networkLabelFromDevice:(id)device
{
    NSString *description = [self objectFrom:device selector:"description"];
    if (![description isKindOfClass:NSString.class]) {
        return nil;
    }
    NSRange range = [description rangeOfString:@"network type: "];
    if (range.location == NSNotFound) {
        return nil;
    }
    NSString *tail = [description substringFromIndex:NSMaxRange(range)];
    NSCharacterSet *terminators = [NSCharacterSet characterSetWithCharactersInString:@",\n"];
    NSRange end = [tail rangeOfCharacterFromSet:terminators];
    NSString *label = end.location == NSNotFound ? tail : [tail substringToIndex:end.location];
    label = [label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    // The description says "network type: (none)" when the phone shares nothing.
    if (label.length == 0 || [label hasPrefix:@"("]) {
        return nil;
    }
    return label;
}

/// Performs a zero-argument object-returning selector when the object has it.
- (nullable id)objectFrom:(id)object selector:(const char *)selectorName
{
    SEL selector = sel_registerName(selectorName);
    if (object == nil || ![object respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

@end

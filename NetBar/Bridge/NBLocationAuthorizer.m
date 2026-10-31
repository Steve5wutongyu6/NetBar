//
//  NBLocationAuthorizer.m
//  NetBar
//

#import "NBLocationAuthorizer.h"

#import <CoreLocation/CoreLocation.h>

NSNotificationName const NBLocationAuthorizationDidChangeNotification =
    @"NBLocationAuthorizationDidChangeNotification";

@interface NBLocationAuthorizer () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *manager;
@property (nonatomic, copy, nullable) void (^pendingCompletion)(NBLocationAuthorization);
@end

@implementation NBLocationAuthorizer

+ (instancetype)sharedAuthorizer
{
    static NBLocationAuthorizer *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[NBLocationAuthorizer alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        // Creating the manager is what registers the app with Location Services,
        // so it happens eagerly: without it the app never shows up in the pane.
        _manager = [[CLLocationManager alloc] init];
        _manager.delegate = self;
        _manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
    }
    return self;
}

- (NBLocationAuthorization)authorization
{
    return [self.class authorizationFromStatus:self.manager.authorizationStatus];
}

- (BOOL)isAuthorized
{
    return self.authorization == NBLocationAuthorizationAuthorized;
}

- (void)requestAuthorizationWithCompletion:(void (^_Nullable)(NBLocationAuthorization))completion
{
    NBLocationAuthorization current = self.authorization;
    if (current != NBLocationAuthorizationNotDetermined) {
        if (completion) {
            completion(current);
        }
        return;
    }
    self.pendingCompletion = completion;
    // The prompt is asynchronous; the delegate callback finishes the request.
    [self.manager requestWhenInUseAuthorization];
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager
{
    NBLocationAuthorization authorization = [self.class authorizationFromStatus:manager.authorizationStatus];
    void (^completion)(NBLocationAuthorization) = self.pendingCompletion;
    self.pendingCompletion = nil;

    [[NSNotificationCenter defaultCenter]
        postNotificationName:NBLocationAuthorizationDidChangeNotification
                      object:self];
    if (completion) {
        completion(authorization);
    }
}

#pragma mark - Helpers

+ (NBLocationAuthorization)authorizationFromStatus:(CLAuthorizationStatus)status
{
    switch (status) {
        // macOS reports its single "authorized" state as AuthorizedAlways; the
        // When-In-Use state does not exist on this platform.
        case kCLAuthorizationStatusAuthorizedAlways:
            return NBLocationAuthorizationAuthorized;
        case kCLAuthorizationStatusDenied:
            return NBLocationAuthorizationDenied;
        case kCLAuthorizationStatusRestricted:
            return NBLocationAuthorizationRestricted;
        case kCLAuthorizationStatusNotDetermined:
            return NBLocationAuthorizationNotDetermined;
    }
    return NBLocationAuthorizationNotDetermined;
}

@end

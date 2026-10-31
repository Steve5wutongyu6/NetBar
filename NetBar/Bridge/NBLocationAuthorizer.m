//
//  NBLocationAuthorizer.m
//  NetBar
//

#import "NBLocationAuthorizer.h"

#import <AppKit/AppKit.h>
#import <CoreLocation/CoreLocation.h>

NSNotificationName const NBLocationAuthorizationDidChangeNotification =
    @"NBLocationAuthorizationDidChangeNotification";

@interface NBLocationAuthorizer () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *manager;
@property (nonatomic, copy, nullable) void (^pendingCompletion)(NBLocationAuthorization);
/// Last state handed to observers, so a repeated report does not look like news.
@property (nonatomic) NBLocationAuthorization reportedAuthorization;
@end

@implementation NBLocationAuthorizer

+ (instancetype)shared
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
        _reportedAuthorization = NBLocationAuthorizationNotDetermined;
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
    // A menu bar accessory is never frontmost, and macOS only shows the privacy
    // prompt for the active app, so ask for the foreground first.
    [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
    // The prompt is asynchronous; the delegate callback finishes the request.
    [self.manager requestWhenInUseAuthorization];
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager
{
    NBLocationAuthorization authorization = [self.class authorizationFromStatus:manager.authorizationStatus];
    BOOL changed = authorization != self.reportedAuthorization;
    self.reportedAuthorization = authorization;

    // The manager reports once on creation and again whenever the answer or the
    // system setting changes. Observers are told about the answer, not about the
    // opening report, so a grant made in System Settings also reaches the menu.
    if (changed && authorization != NBLocationAuthorizationNotDetermined) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:NBLocationAuthorizationDidChangeNotification
                          object:nil];
    }

    // An unanswered prompt keeps its completion for the next callback.
    void (^completion)(NBLocationAuthorization) = self.pendingCompletion;
    if (completion == nil || authorization == NBLocationAuthorizationNotDetermined) {
        return;
    }
    self.pendingCompletion = nil;
    completion(authorization);
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

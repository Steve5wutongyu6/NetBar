//
//  NBLocationAuthorizer.h
//  NetBar
//
//  macOS only hands an app Wi-Fi network names once the app is authorized for
//  Location Services, and an app appears in that list only after it asks for
//  authorization itself. This wraps the one CLLocationManager NetBar needs.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NBLocationAuthorization) {
    /// The user has not been asked yet.
    NBLocationAuthorizationNotDetermined = 0,
    NBLocationAuthorizationDenied,
    NBLocationAuthorizationAuthorized,
    /// Location Services are off system-wide.
    NBLocationAuthorizationRestricted,
};

/// Posted when the authorization changes, after the user answers the prompt.
FOUNDATION_EXPORT NSNotificationName const NBLocationAuthorizationDidChangeNotification;

@interface NBLocationAuthorizer : NSObject

+ (instancetype)sharedAuthorizer;

/// Current state, without prompting.
@property (nonatomic, readonly) NBLocationAuthorization authorization;

/// Whether Wi-Fi names can be read, i.e. whether authorization was granted.
@property (nonatomic, readonly, getter=isAuthorized) BOOL authorized;

/// Asks for authorization once. Subsequent calls only report the current state,
/// because macOS only shows the prompt a single time per app.
- (void)requestAuthorizationWithCompletion:(void (^_Nullable)(NBLocationAuthorization))completion;

@end

NS_ASSUME_NONNULL_END

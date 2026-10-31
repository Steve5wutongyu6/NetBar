//
//  NBWiFiMonitor.h
//  NetBar
//
//  Pushes radio changes instead of waiting to be asked. CoreWLAN reports power,
//  association, link and signal changes, and those are exactly the moments the
//  status item has to redraw, whether or not the menu is open.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Called on the main thread after a burst of radio events settles.
typedef void (^NBWiFiChangeHandler)(void);

@interface NBWiFiMonitor : NSObject

+ (instancetype)sharedMonitor;

/// Starts reporting changes. `handler` runs on the main thread; calling twice
/// replaces the handler.
- (void)startObserving:(NBWiFiChangeHandler)handler;

/// Stops reporting. Safe to call when not observing.
- (void)stop;

@end

NS_ASSUME_NONNULL_END

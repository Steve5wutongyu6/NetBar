//
//  NBSystemWiFiMenu.h
//  NetBar
//
//  Handing a click to the Wi-Fi menu macOS itself puts in the menu bar.
//
//  macOS 27 keeps every status item in one window owned by MenuBarAgent, and the
//  Wi-Fi control lives inside the Control Center item's dropdown. The Accessibility
//  actions those items advertise (\c AXShowMenu, \c AXPress) return success and do
//  nothing at all, so the only route that works is the one the user takes: a real
//  click on the real item. This bridge finds the item through Accessibility and
//  delivers that click as a synthetic mouse event.
//
//  Both halves need the process to be trusted for the Accessibility API; there is
//  no private interface that avoids the permission. Callers therefore check
//  \c isPermitted first and send the user to System Settings when it is NO.
//
//  The calls block for up to two seconds while a menu opens, so they must not run
//  on the main thread.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// What \c openSystemWiFiMenu managed to do.
typedef NS_ENUM(NSInteger, NBSystemWiFiMenuOutcome) {
    /// The system's Wi-Fi menu is on screen.
    NBSystemWiFiMenuOutcomeOpened = 0,
    /// This process is not trusted for the Accessibility API.
    NBSystemWiFiMenuOutcomeNotPermitted = 1,
    /// No status item could be found to click.
    NBSystemWiFiMenuOutcomeNoMenuBarItem = 2,
    /// The menu bar item opened but carried no Wi-Fi control.
    NBSystemWiFiMenuOutcomeNoWiFiControl = 3,
};

@interface NBSystemWiFiMenu : NSObject

/// YES when macOS lets this process drive other applications' interfaces.
+ (BOOL)isPermitted NS_SWIFT_NAME(isPermitted());

/// Asks macOS to show the Accessibility prompt. Returns the current answer.
+ (BOOL)requestPermission NS_SWIFT_NAME(requestPermission());

/// Opens the Wi-Fi menu macOS owns.
///
/// One click when Wi-Fi is its own menu bar item; otherwise the Control Center
/// item is opened first and its Wi-Fi tile clicked inside. Blocks, so call it off
/// the main thread.
/// \c NS_SWIFT_NAME is not decoration: the importer rewrites a leading \c open
/// plus a noun into a bare `open()`, which would rename this out from under the
/// call site.
+ (NBSystemWiFiMenuOutcome)openSystemWiFiMenu NS_SWIFT_NAME(openSystemWiFiMenu());

/// Opens the Accessibility pane of System Settings.
+ (void)openAccessibilitySettings NS_SWIFT_NAME(openAccessibilitySettings());

@end

NS_ASSUME_NONNULL_END

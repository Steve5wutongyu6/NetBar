//
//  NBSystemWiFiMenu.m
//  NetBar
//
//  See the header for why this is a synthetic mouse event and not an
//  Accessibility action. The shape of the walk is:
//
//    MenuBarAgent's AXExtrasMenuBar
//      -> an item named "Wi-Fi"      (only when Wi-Fi is its own menu bar item)
//      -> an item named "Control Center"
//           -> Control Center's dropdown window
//                -> a tile named "Wi-Fi: <network>"
//
//  Every step is a click at the centre of the element's Accessibility frame, so
//  no layout is hard-coded and the menu bar can be rearranged freely.
//

#import "NBSystemWiFiMenu.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

/// How long to wait for a menu to appear before giving up, in 50 ms steps.
static const int NBSystemWiFiMenuWaitAttempts = 40;

#pragma mark - Names

/// Letters and digits only, lowercased, so "Wi‐Fi", "Wi-Fi" and "WiFi" all
/// compare equal regardless of the separator macOS picked.
static NSString *NBNormalized(CFStringRef string) {
    if (string == NULL) { return @""; }
    NSString *lowered = [(__bridge NSString *)string lowercaseString];
    NSMutableString *out = [NSMutableString stringWithCapacity:lowered.length];
    NSCharacterSet *letters = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger index = 0; index < lowered.length; index++) {
        unichar character = [lowered characterAtIndex:index];
        if ([letters characterIsMember:character]) {
            [out appendFormat:@"%C", character];
        }
    }
    return out;
}

static BOOL NBNameIsWiFi(NSString *name) {
    return [name containsString:@"wifi"]
        || [name containsString:@"wlan"]
        || [name containsString:@"\u65e0\u7ebf\u5c40\u57df\u7f51"];
}

static BOOL NBNameIsControlCenter(NSString *name) {
    return [name containsString:@"controlcenter"]
        || [name containsString:@"\u63a7\u5236\u4e2d\u5fc3"];
}

/// The clock is the other item that advertises \c AXPress, so a fallback that
/// picks "the first pressable item" has to be able to rule it out.
static BOOL NBNameIsClock(NSString *name) {
    return [name containsString:@"clock"]
        || [name containsString:@"\u65f6\u949f"]
        || [name containsString:@"\u6642\u9593"];
}

#pragma mark - Accessibility helpers

static pid_t NBPidForBundleIdentifier(NSString *identifier) {
    for (NSRunningApplication *application in NSWorkspace.sharedWorkspace.runningApplications) {
        if ([application.bundleIdentifier isEqualToString:identifier]) {
            return application.processIdentifier;
        }
    }
    return 0;
}

/// The extras menu bar, which is where the right-hand side of the menu bar lives.
/// The owning process changed across releases, so all three known hosts are tried.
static AXUIElementRef NBCopyExtrasMenuBar(void) {
    NSArray<NSString *> *hosts = @[
        @"com.apple.MenuBarAgent",
        @"com.apple.controlcenter",
        @"com.apple.systemuiserver",
    ];
    for (NSString *host in hosts) {
        pid_t pid = NBPidForBundleIdentifier(host);
        if (pid == 0) { continue; }
        AXUIElementRef application = AXUIElementCreateApplication(pid);
        CFTypeRef extras = NULL;
        AXError error = AXUIElementCopyAttributeValue(application, CFSTR("AXExtrasMenuBar"), &extras);
        CFRelease(application);
        if (error == kAXErrorSuccess && extras != NULL) {
            return (AXUIElementRef)extras;
        }
    }
    return NULL;
}

static BOOL NBCopyFrame(AXUIElementRef element, CGRect *frame) {
    CFTypeRef position = NULL;
    CFTypeRef size = NULL;
    BOOL havePosition = NO;
    if (AXUIElementCopyAttributeValue(element, kAXPositionAttribute, &position) == kAXErrorSuccess && position != NULL) {
        CGPoint origin = CGPointZero;
        havePosition = AXValueGetValue((AXValueRef)position, kAXValueCGPointType, &origin);
        if (havePosition) { frame->origin = origin; }
        CFRelease(position);
    }
    if (havePosition
        && AXUIElementCopyAttributeValue(element, kAXSizeAttribute, &size) == kAXErrorSuccess
        && size != NULL) {
        CGSize extent = CGSizeZero;
        if (AXValueGetValue((AXValueRef)size, kAXValueCGSizeType, &extent)) {
            frame->size = extent;
        }
        CFRelease(size);
    }
    return havePosition && frame->size.width > 0 && frame->size.height > 0;
}

/// Depth-first search for the first element whose role or description names it.
static AXUIElementRef NBCopyFindElement(AXUIElementRef root,
                                        BOOL (^test)(NSString *name),
                                        int depth) {
    if (depth > 8) { return NULL; }

    CFStringRef role = NULL;
    CFStringRef description = NULL;
    AXUIElementCopyAttributeValue(root, kAXRoleAttribute, (CFTypeRef *)&role);
    AXUIElementCopyAttributeValue(root, kAXDescriptionAttribute, (CFTypeRef *)&description);

    BOOL matched = test(NBNormalized(role)) || test(NBNormalized(description));
    if (role != NULL) { CFRelease(role); }
    if (description != NULL) { CFRelease(description); }
    if (matched) { return (AXUIElementRef)CFRetain(root); }

    CFArrayRef children = NULL;
    if (AXUIElementCopyAttributeValue(root, kAXChildrenAttribute, (CFTypeRef *)&children) == kAXErrorSuccess
        && children != NULL) {
        for (CFIndex index = 0; index < CFArrayGetCount(children); index++) {
            AXUIElementRef found = NBCopyFindElement(
                (AXUIElementRef)CFArrayGetValueAtIndex(children, index), test, depth + 1);
            if (found != NULL) {
                CFRelease(children);
                return found;
            }
        }
        CFRelease(children);
    }
    return NULL;
}

#pragma mark - Synthetic clicks

/// A press and release at a point. The cursor is left there on purpose: moving it
/// away again can collapse the submenu the click just expanded.
static void NBClickAt(CGPoint point) {
    CGEventRef move = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, point, kCGMouseButtonLeft);
    if (move != NULL) {
        CGEventPost(kCGHIDEventTap, move);
        CFRelease(move);
        usleep(120 * 1000);
    }
    CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, point, kCGMouseButtonLeft);
    if (down != NULL) {
        CGEventPost(kCGHIDEventTap, down);
        CFRelease(down);
        usleep(80 * 1000);
    }
    CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, point, kCGMouseButtonLeft);
    if (up != NULL) {
        CGEventPost(kCGHIDEventTap, up);
        CFRelease(up);
    }
}

static BOOL NBClickCentreOf(AXUIElementRef element) {
    CGRect frame = CGRectNull;
    if (!NBCopyFrame(element, &frame)) { return NO; }
    NBClickAt(CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame)));
    return YES;
}

#pragma mark - Control Center

/// Control Center's dropdown, once it is open, and the Wi-Fi tile inside it.
static AXUIElementRef NBCopyControlCenterWiFiTile(void) {
    pid_t pid = NBPidForBundleIdentifier(@"com.apple.controlcenter");
    if (pid == 0) { return NULL; }

    AXUIElementRef application = AXUIElementCreateApplication(pid);
    for (int attempt = 0; attempt < NBSystemWiFiMenuWaitAttempts; attempt++) {
        CFArrayRef windows = NULL;
        AXError error = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute, (CFTypeRef *)&windows);
        if (error == kAXErrorSuccess && windows != NULL) {
            for (CFIndex index = 0; index < CFArrayGetCount(windows); index++) {
                AXUIElementRef tile = NBCopyFindElement(
                    (AXUIElementRef)CFArrayGetValueAtIndex(windows, index),
                    ^BOOL(NSString *name) { return NBNameIsWiFi(name); },
                    0);
                if (tile != NULL) {
                    CFRelease(windows);
                    CFRelease(application);
                    return tile;
                }
            }
            CFRelease(windows);
        }
        usleep(50 * 1000);
    }
    CFRelease(application);
    return NULL;
}

/// The Control Center item, for the fallback path. It is named, so that is tried
/// first; if a future release renames it, the only other pressable item that is
/// neither the clock nor a sliver of an indicator is taken instead.
static AXUIElementRef NBCopyControlCenterItem(AXUIElementRef extras) {
    AXUIElementRef named = NBCopyFindElement(
        extras, ^BOOL(NSString *name) { return NBNameIsControlCenter(name); }, 0);
    if (named != NULL) { return named; }

    CFArrayRef children = NULL;
    if (AXUIElementCopyAttributeValue(extras, kAXChildrenAttribute, (CFTypeRef *)&children) != kAXErrorSuccess
        || children == NULL) {
        return NULL;
    }
    AXUIElementRef fallback = NULL;
    for (CFIndex index = 0; index < CFArrayGetCount(children); index++) {
        AXUIElementRef candidate = NBCopyFindElement(
            (AXUIElementRef)CFArrayGetValueAtIndex(children, index),
            ^BOOL(NSString *name) { return !NBNameIsClock(name) && name.length > 0; },
            0);
        if (candidate == NULL) { continue; }
        CGRect frame = CGRectNull;
        if (NBCopyFrame(candidate, &frame) && frame.size.width >= 18 && frame.size.height >= 14) {
            fallback = candidate;
            break;
        }
        CFRelease(candidate);
    }
    CFRelease(children);
    return fallback;
}

#pragma mark - Public interface

@implementation NBSystemWiFiMenu

+ (BOOL)isPermitted {
    return AXIsProcessTrusted();
}

+ (BOOL)requestPermission {
    NSDictionary *options = @{ (__bridge id)kAXTrustedCheckOptionPrompt: @YES };
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

+ (void)openAccessibilitySettings {
    NSURL *url = [NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    if (url != nil) {
        [NSWorkspace.sharedWorkspace openURL:url];
    }
}

+ (NBSystemWiFiMenuOutcome)openSystemWiFiMenu {
    if (!AXIsProcessTrusted()) { return NBSystemWiFiMenuOutcomeNotPermitted; }

    AXUIElementRef extras = NBCopyExtrasMenuBar();
    if (extras == NULL) { return NBSystemWiFiMenuOutcomeNoMenuBarItem; }

    // Wi-Fi as its own menu bar item: one click is the whole job.
    AXUIElementRef wifiItem = NBCopyFindElement(
        extras, ^BOOL(NSString *name) { return NBNameIsWiFi(name); }, 0);
    if (wifiItem != NULL) {
        BOOL clicked = NBClickCentreOf(wifiItem);
        CFRelease(wifiItem);
        CFRelease(extras);
        return clicked ? NBSystemWiFiMenuOutcomeOpened : NBSystemWiFiMenuOutcomeNoWiFiControl;
    }

    AXUIElementRef controlCentre = NBCopyControlCenterItem(extras);
    CFRelease(extras);
    if (controlCentre == NULL) { return NBSystemWiFiMenuOutcomeNoMenuBarItem; }

    BOOL opened = NBClickCentreOf(controlCentre);
    CFRelease(controlCentre);
    if (!opened) { return NBSystemWiFiMenuOutcomeNoMenuBarItem; }

    // The dropdown animates in, so the tile is polled for rather than assumed.
    AXUIElementRef tile = NBCopyControlCenterWiFiTile();
    if (tile == NULL) {
        // Leave nothing open behind us if the tile never turned up.
        NBClickAt(CGPointMake(20, 200));
        return NBSystemWiFiMenuOutcomeNoWiFiControl;
    }
    BOOL clicked = NBClickCentreOf(tile);
    CFRelease(tile);
    return clicked ? NBSystemWiFiMenuOutcomeOpened : NBSystemWiFiMenuOutcomeNoWiFiControl;
}

@end

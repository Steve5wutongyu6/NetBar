//
//  NBSystemWiFiMenu.m
//  NetBar
//
//  Opens the Wi-Fi menu macOS owns, without touching the pointer.
//
//  The route is two Accessibility actions:
//
//    MenuBarAgent's AXExtrasMenuBar
//      -> an item named "Wi-Fi"        (only when Wi-Fi is its own menu bar item)
//           AXPress opens its menu directly.
//      -> an item named "Control Center"
//           AXPress opens the dropdown.
//           Inside it, the Wi-Fi tile carries a custom "show details" action,
//           and that is the one that expands the Wi-Fi submenu.
//
//  Two traps this file exists to avoid:
//
//    * AXShowMenu returns success on every one of these items and does nothing.
//      Only AXPress and the custom action have an effect.
//    * AXPress on the Wi-Fi tile is the Wi-Fi *switch*, not the submenu. Pressing
//      it turns the radio off. It is never called here; the tile is only ever
//      driven through "show details".
//
//  Both need the Accessibility grant, so callers check isPermitted first.
//
#import "NBSystemWiFiMenu.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
/// How long to wait for a menu to appear before giving up, in 50 ms steps.
static const int NBSystemWiFiMenuWaitAttempts = 40;
#pragma mark - Names
/// Letters and digits only, lowercased, so "Wi\u2010Fi", "Wi-Fi" and "WiFi" all
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
/// Whether any element under `root` satisfies `test`. Same walk as
/// `NBCopyFindElement`, for callers that only need the answer.
static BOOL NBElementExists(AXUIElementRef root, BOOL (^test)(NSString *name), int depth) {
    if (depth > 8) { return NO; }

    CFStringRef role = NULL;
    CFStringRef description = NULL;
    AXUIElementCopyAttributeValue(root, kAXRoleAttribute, (CFTypeRef *)&role);
    AXUIElementCopyAttributeValue(root, kAXDescriptionAttribute, (CFTypeRef *)&description);
    BOOL matched = test(NBNormalized(role)) || test(NBNormalized(description));
    if (role != NULL) { CFRelease(role); }
    if (description != NULL) { CFRelease(description); }
    if (matched) { return YES; }

    CFArrayRef children = NULL;
    if (AXUIElementCopyAttributeValue(root, kAXChildrenAttribute, (CFTypeRef *)&children) == kAXErrorSuccess
        && children != NULL) {
        for (CFIndex index = 0; index < CFArrayGetCount(children); index++) {
            if (NBElementExists((AXUIElementRef)CFArrayGetValueAtIndex(children, index), test, depth + 1)) {
                CFRelease(children);
                return YES;
            }
        }
        CFRelease(children);
    }
    return NO;
}

/// Runs the tile's own "show details" action, which is what expands a Control
/// Center tile into its submenu. Custom actions reach AX as a block of text, so
/// the name is matched loosely and never fed to AXPress: on the Wi-Fi tile that
/// action is the radio switch.
static BOOL NBPerformShowDetails(AXUIElementRef element) {
    CFArrayRef actions = NULL;
    if (AXUIElementCopyActionNames(element, &actions) != kAXErrorSuccess || actions == NULL) {
        return NO;
    }
    BOOL performed = NO;
    for (int pass = 0; pass < 2 && !performed; pass++) {
        for (CFIndex index = 0; index < CFArrayGetCount(actions); index++) {
            CFStringRef action = CFArrayGetValueAtIndex(actions, index);
            NSString *text = (__bridge NSString *)action;
            BOOL isCustom = [text hasPrefix:@"Name:"];
            BOOL named = [[text lowercaseString] containsString:@"show details"];
            // First pass takes the documented name; the second takes whatever
            // else the tile exposes as a custom action.
            if ((pass == 0 && named) || (pass == 1 && isCustom && !named)) {
                performed = AXUIElementPerformAction(element, action) == kAXErrorSuccess;
                if (performed) { break; }
            }
        }
    }
    CFRelease(actions);
    return performed;
}
#pragma mark - Control Center
/// Whether Control Center's dropdown is already on screen.
static BOOL NBControlCenterIsOpen(void) {
    CFArrayRef windows = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (windows == NULL) { return NO; }
    BOOL open = NO;
    for (CFIndex index = 0; index < CFArrayGetCount(windows) && !open; index++) {
        CFDictionaryRef window = CFArrayGetValueAtIndex(windows, index);
        int layer = 0;
        CFNumberGetValue(CFDictionaryGetValue(window, kCGWindowLayer), kCFNumberIntType, &layer);
        if (layer < 100) { continue; }
        CFStringRef owner = CFDictionaryGetValue(window, kCGWindowOwnerName);
        if (owner != NULL && CFStringCompare(owner, CFSTR("Control Center"), 0) == kCFCompareEqualTo) {
            open = YES;
        }
    }
    CFRelease(windows);
    return open;
}
/// Closes Control Center's dropdown, used only to undo an attempt that failed
/// partway so the next click starts from a known state.
static void NBCloseControlCenter(void) {
    // Escape only closes it, and only while it is open, so the loop waits for the
    // window to actually go away instead of firing blindly.
    for (int press = 0; press < 3 && NBControlCenterIsOpen(); press++) {
        CGEventRef down = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)53, true);
        if (down != NULL) { CGEventPost(kCGHIDEventTap, down); CFRelease(down); }
        CGEventRef up = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)53, false);
        if (up != NULL) { CGEventPost(kCGHIDEventTap, up); CFRelease(up); }
        usleep(150 * 1000);
    }
}

/// Whether the Wi-Fi submenu is already expanded. Control Center draws those
/// section headings in English on every system this was measured on, and the
/// name is normalised before it is compared.
static BOOL NBWiFiSubmenuIsOpen(void) {
    pid_t pid = NBPidForBundleIdentifier(@"com.apple.controlcenter");
    if (pid == 0) { return NO; }

    AXUIElementRef application = AXUIElementCreateApplication(pid);
    CFArrayRef windows = NULL;
    BOOL open = NO;
    if (AXUIElementCopyAttributeValue(application, kAXWindowsAttribute, (CFTypeRef *)&windows) == kAXErrorSuccess
        && windows != NULL) {
        for (CFIndex index = 0; index < CFArrayGetCount(windows) && !open; index++) {
            open = NBElementExists(
                (AXUIElementRef)CFArrayGetValueAtIndex(windows, index),
                ^BOOL(NSString *name) {
                    return [name containsString:@"knownnetwork"] || [name containsString:@"othernetwork"];
                },
                0);
        }
        CFRelease(windows);
    }
    CFRelease(application);
    return open;
}

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
/// The Control Center item, for the two-step path. It is named, so that is tried
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
        CFTypeRef position = NULL;
        CFTypeRef size = NULL;
        CGRect frame = CGRectNull;
        BOOL measured = NO;
        if (AXUIElementCopyAttributeValue(candidate, kAXPositionAttribute, &position) == kAXErrorSuccess
            && position != NULL) {
            CGPoint origin = CGPointZero;
            measured = AXValueGetValue((AXValueRef)position, kAXValueCGPointType, &origin);
            frame.origin = origin;
            CFRelease(position);
        }
        if (measured
            && AXUIElementCopyAttributeValue(candidate, kAXSizeAttribute, &size) == kAXErrorSuccess
            && size != NULL) {
            CGSize extent = CGSizeZero;
            AXValueGetValue((AXValueRef)size, kAXValueCGSizeType, &extent);
            frame.size = extent;
            CFRelease(size);
        }
        if (measured && frame.size.width >= 18 && frame.size.height >= 14) {
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

    // Already showing: driving it again would collapse it, because every one of
    // these actions toggles. The answer is read twice, because a menu on its way
    // out still reports that it is there.
    if (NBWiFiSubmenuIsOpen()) {
        usleep(250 * 1000);
        if (NBWiFiSubmenuIsOpen()) { return NBSystemWiFiMenuOutcomeOpened; }
    }

    // Two passes. The first trusts the dropdown's reported state; if the tile is
    // not there after all, the second starts from a menu that is definitely
    // closed and opens it again. Without that, a window caught mid-animation
    // looks open, the press is skipped, and the attempt dies on an empty poll.
    for (int pass = 0; pass < 2; pass++) {
        if (pass > 0) { NBCloseControlCenter(); }

        AXUIElementRef extras = NBCopyExtrasMenuBar();
        if (extras == NULL) { return NBSystemWiFiMenuOutcomeNoMenuBarItem; }

        if (pass == 0) {
            // Wi-Fi as its own menu bar item: pressing it is the whole job.
            AXUIElementRef wifiItem = NBCopyFindElement(
                extras, ^BOOL(NSString *name) { return NBNameIsWiFi(name); }, 0);
            if (wifiItem != NULL) {
                BOOL pressed = AXUIElementPerformAction(wifiItem, kAXPressAction) == kAXErrorSuccess;
                CFRelease(wifiItem);
                CFRelease(extras);
                return pressed ? NBSystemWiFiMenuOutcomeOpened : NBSystemWiFiMenuOutcomeNoWiFiControl;
            }
        }

        if (!NBControlCenterIsOpen()) {
            AXUIElementRef controlCentre = NBCopyControlCenterItem(extras);
            CFRelease(extras);
            if (controlCentre == NULL) { return NBSystemWiFiMenuOutcomeNoMenuBarItem; }
            BOOL pressed = AXUIElementPerformAction(controlCentre, kAXPressAction) == kAXErrorSuccess;
            CFRelease(controlCentre);
            if (!pressed) { return NBSystemWiFiMenuOutcomeNoMenuBarItem; }
            for (int attempt = 0; attempt < 20 && !NBControlCenterIsOpen(); attempt++) {
                usleep(50 * 1000);
            }
        } else {
            CFRelease(extras);
        }

        // The dropdown animates in, so the tile is polled for rather than assumed.
        AXUIElementRef tile = NBCopyControlCenterWiFiTile();
        if (tile == NULL) { continue; }
        BOOL expanded = NBPerformShowDetails(tile);
        CFRelease(tile);
        if (!expanded) { continue; }

        // "show details" reports success whether or not the submenu opens, so the
        // result is read back instead of trusted.
        for (int attempt = 0; attempt < NBSystemWiFiMenuWaitAttempts; attempt++) {
            if (NBWiFiSubmenuIsOpen()) { return NBSystemWiFiMenuOutcomeOpened; }
            usleep(50 * 1000);
        }
    }

    NBCloseControlCenter();
    return NBSystemWiFiMenuOutcomeNoWiFiControl;
}
@end
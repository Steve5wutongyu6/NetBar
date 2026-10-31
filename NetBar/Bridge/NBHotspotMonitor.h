//
//  NBHotspotMonitor.h
//  NetBar
//
//  The Cellular side of a Personal Hotspot row — battery, generation and signal
//  bars — is not in the Wi-Fi beacon. The system gets it over Continuity, through
//  the Sharing framework's remote-hotspot session, and that is what this wraps.
//
//  The framework is loaded by name at runtime: NetBar links it loosely so a
//  machine without it still runs, and so the app keeps building against the
//  public SDK alone.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One nearby device that is sharing its connection.
@interface NBHotspotPeer : NSObject
/// The device name, which is also the SSID of the hotspot it advertises.
@property (nonatomic, copy) NSString *name;
/// Battery percentage the device reported, or 0 when it reported none.
@property (nonatomic) NSInteger batteryPercent;
/// "4G", "5G" and so on, as the system itself labels the generation.
@property (nonatomic, copy, nullable) NSString *networkLabel;
/// Signal bars, 0 through 4; 0 when the device reported none.
@property (nonatomic) NSInteger signalBars;
@end

@interface NBHotspotMonitor : NSObject

+ (instancetype)sharedMonitor;

/// Devices seen by the current browse, strongest first. Empty when the monitor
/// is not running or nothing is in range.
@property (nonatomic, readonly) NSArray<NBHotspotPeer *> *peers;

/// Starts browsing over Continuity. Safe to call repeatedly.
- (void)start;

/// Stops browsing, which is what keeps the radio and the phone quiet.
- (void)stop;

@end

NS_ASSUME_NONNULL_END

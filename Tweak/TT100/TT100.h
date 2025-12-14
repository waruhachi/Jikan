#import <IOKit/IOKitLib.h>
#import <UIKit/UIKit.h>
#import <dirent.h>
#import <mach/mach_port.h>
#import <roothide.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *_Nullable TT100PLSQLPath(void);

FOUNDATION_EXPORT NSString *const TT100BatteryInfoUpdatedNotification;
FOUNDATION_EXPORT NSString *const TT100InternalDidRefreshBatteryInfoNotification;
FOUNDATION_EXPORT NSString *const JikanChargingStateChangedNotification;

@interface TT100 : NSObject

+ (instancetype)sharedInstance;
- (void)_refreshBatteryInfo;
+ (NSDictionary *_Nullable)fetchBatteryInfo;
+ (NSString *)estimatedTT100;
+ (NSString *)estimatedTT100WithBatteryInfo:(NSDictionary *_Nullable)batteryInfo;
+ (void)startMonitoring;
+ (NSDictionary<NSString *, NSNumber *> *)loadHistoryFromPLSQL;
+ (NSDictionary<NSString *, NSNumber *> *)cachedHistoryBuckets;

/// Returns a stable charger class string used for DB bucketing (e.g. "wired_20w", "wireless_7w").
/// If `outIsWireless` is non-NULL, it is set to whether the charger appears to be wireless.
+ (NSString *)chargerClassWithBatteryInfo:(NSDictionary *_Nullable)batteryInfo outIsWireless:(BOOL *_Nullable)outIsWireless;

@end

NS_ASSUME_NONNULL_END

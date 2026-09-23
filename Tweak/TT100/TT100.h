#import <IOKit/IOKitLib.h>
#import <UIKit/UIKit.h>
#import <dirent.h>
#import <mach/mach_port.h>
#import <roothide.h>

#import "../../Localization/JikanLocalization.h"

FOUNDATION_EXPORT NSString * TT100PLSQLPath(void);

FOUNDATION_EXPORT NSString *const TT100BatteryInfoUpdatedNotification;
FOUNDATION_EXPORT NSString *const TT100InternalDidRefreshBatteryInfoNotification;
FOUNDATION_EXPORT NSString *const JikanChargingStateChangedNotification;

@interface TT100 : NSObject

+ (instancetype)sharedInstance;
- (void)_refreshBatteryInfo;
+ (NSDictionary *)fetchBatteryInfo;
+ (NSString *)estimatedTT100;
+ (NSString *)estimatedTT100WithBatteryInfo:(NSDictionary *)batteryInfo;
+ (BOOL)hasEstimateWithBatteryInfo:(NSDictionary *)batteryInfo;
+ (BOOL)isFullyChargedWithBatteryInfo:(NSDictionary *)batteryInfo displayPercent:(NSInteger *)outPercent;
+ (NSInteger)targetPercent;
+ (BOOL)isTargetReachedWithBatteryInfo:(NSDictionary *)batteryInfo displayPercent:(NSInteger *)outPercent;
+ (NSDictionary *)latestSnapshot;
+ (void)startMonitoring;
+ (void)stopMonitoring;
+ (NSString *)chargerIdentityWithBatteryInfo:(NSDictionary *)batteryInfo;
+ (NSDictionary<NSString *, NSNumber *> *)loadHistoryFromPLSQL;
+ (NSDictionary<NSString *, NSNumber *> *)cachedHistoryBuckets;

+ (double)effectiveChargingWattageWithBatteryInfo:(NSDictionary *)batteryInfo;

+ (NSString *)chargerClassWithBatteryInfo:(NSDictionary *)batteryInfo outIsWireless:(BOOL *)outIsWireless;

@end

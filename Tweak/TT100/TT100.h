#import <IOKit/IOKitLib.h>
#import <UIKit/UIKit.h>
#import <dirent.h>
#import <mach/mach_port.h>
#import <roothide.h>

#import "../../Localization/JikanLocalization.h"

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
+ (BOOL)hasEstimateWithBatteryInfo:(NSDictionary *_Nullable)batteryInfo;
+ (BOOL)isFullyChargedWithBatteryInfo:(NSDictionary *_Nullable)batteryInfo displayPercent:(NSInteger *_Nullable)outPercent;
+ (NSInteger)targetPercent;
+ (BOOL)isTargetReachedWithBatteryInfo:(NSDictionary *_Nullable)batteryInfo displayPercent:(NSInteger *_Nullable)outPercent;
+ (NSDictionary *_Nullable)latestSnapshot;
+ (void)startMonitoring;
+ (void)stopMonitoring;
+ (NSString *)chargerIdentityWithBatteryInfo:(NSDictionary *_Nullable)batteryInfo;
+ (NSDictionary<NSString *, NSNumber *> *)loadHistoryFromPLSQL;
+ (NSDictionary<NSString *, NSNumber *> *)cachedHistoryBuckets;

+ (double)effectiveChargingWattageWithBatteryInfo:(NSDictionary *_Nullable)batteryInfo;

+ (NSString *)chargerClassWithBatteryInfo:(NSDictionary *_Nullable)batteryInfo outIsWireless:(BOOL *_Nullable)outIsWireless;

@end

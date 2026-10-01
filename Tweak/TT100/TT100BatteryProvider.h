#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <mach/mach_port.h>
#import <roothide.h>

#import "TT100BatteryValues.h"

@interface TT100BatteryProvider : NSObject
+ (NSDictionary *)fetchBatteryInfo;
+ (double)displaySOCWithBatteryInfo:(NSDictionary *)batteryInfo;
+ (BOOL)isFullyChargedWithBatteryInfo:(NSDictionary *)batteryInfo displayPercent:(NSInteger *)outPercent;
+ (NSString *)chargerClassWithBatteryInfo:(NSDictionary *)batteryInfo outIsWireless:(BOOL *)outIsWireless;
+ (NSString *)chargerIdentityWithBatteryInfo:(NSDictionary *)batteryInfo;
+ (double)effectiveChargingWattageWithBatteryInfo:(NSDictionary *)batteryInfo;
@end

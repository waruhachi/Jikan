#import <Foundation/Foundation.h>
#import <limits.h>

#import "../../Localization/JikanLocalization.h"
#import "TT100BatteryProvider.h"
#import "TT100Database.h"
#import "TT100LegacyHistory.h"

@interface TT100HistoryEstimator : NSObject
+ (NSString *)estimatedTimeWithBatteryInfo:(NSDictionary *)batteryInfo targetPercent:(NSInteger)targetPercent;
+ (double)estimatedSecondsWithBatteryInfo:(NSDictionary *)batteryInfo targetPercent:(NSInteger)targetPercent;
+ (NSDictionary<NSString *, NSNumber *> *)estimatedSecondsWithBatteryInfo:(NSDictionary *)batteryInfo targets:(NSArray<NSNumber *> *)targets;
+ (NSString *)formattedTimeForSeconds:(double)seconds;
@end

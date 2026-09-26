#import <Foundation/Foundation.h>

@interface TT100AppleEstimator : NSObject
- (void)observeBatteryInfo:(NSDictionary *)batteryInfo;
- (NSDictionary *)resultForBatteryInfo:(NSDictionary *)batteryInfo target:(NSInteger)target;
- (void)reset;
@end

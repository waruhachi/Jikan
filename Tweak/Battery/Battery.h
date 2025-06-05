#include <UIKit/UIKit.h>

@interface BatteryChargerEstimator : NSObject

/// Estimates time (in seconds) until full charge, based on the provided batteryInfo dictionary.
/// Returns -1 if any required data is missing or if charging is infeasible.
+ (NSTimeInterval)estimatedSecondsToFullWithBatteryInfo:(NSDictionary *)batteryInfo;

@end

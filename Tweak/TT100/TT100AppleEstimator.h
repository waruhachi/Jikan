#import <CommonCrypto/CommonDigest.h>
#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>
#import <math.h>
#import <roothide.h>
#import <time.h>

#import "../../Shared/JikanAppleFeatures.h"
#import "../../Shared/JikanEstimateSettings.h"
#import "TT100BatteryProvider.h"
#import "TT100InputPowerProvider.h"

@interface TT100AppleEstimator : NSObject
- (void)observeBatteryInfo:(NSDictionary *)batteryInfo;
- (NSDictionary *)resultForBatteryInfo:(NSDictionary *)batteryInfo target:(NSInteger)target;
- (void)reset;
@end

#import <Foundation/Foundation.h>
#import <math.h>

#import "../../Shared/JikanInputPowerProtocol.h"

@interface TT100InputPowerProvider : NSObject
// Call only from the estimator's worker queue. Failure never supplies a default.
+ (NSDictionary *)readSample;
+ (NSNumber *)milliwattsFromSample:(NSDictionary *)sample batteryInfo:(NSDictionary *)batteryInfo;
@end

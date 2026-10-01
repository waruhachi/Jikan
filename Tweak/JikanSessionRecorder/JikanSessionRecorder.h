#import <Foundation/Foundation.h>
#import <time.h>

#import "../TT100/TT100.h"
#import "../TT100/TT100Database.h"

@interface JikanSessionRecorder : NSObject
- (void)consumeSnapshot:(NSDictionary *)snapshot charging:(BOOL)charging;
- (void)finishWithBatteryInfo:(NSDictionary *)batteryInfo;
@end

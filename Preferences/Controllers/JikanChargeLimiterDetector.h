#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <roothide.h>

#import "JikanSliderSettings.h"

@interface JikanChargeLimiterDetector : NSObject
- (void)detectLimitWithCompletion:(void (^)(NSNumber *limit))completion;
- (void)cancel;
@end

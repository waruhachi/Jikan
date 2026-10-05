#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <mach/mach.h>
#import <math.h>
#import <stdint.h>
#import <string.h>
#import <unistd.h>

@interface JikanSMCReader : NSObject
+ (NSDictionary *)readInputPower;
@end

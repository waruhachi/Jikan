#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <math.h>
#import <stdint.h>

#import "JikanEstimateSettings.h"

FOUNDATION_EXPORT NSArray<NSNumber *> *JikanAppleFeatures(NSDictionary *properties, NSInteger target, NSInteger startSOC, NSInteger elapsed, NSString **failure);
// An explicit measured input override, in mW; never mutates registry properties.
FOUNDATION_EXPORT NSArray<NSNumber *> *JikanAppleFeaturesWithInputPower(NSDictionary *properties, NSInteger target, NSInteger startSOC, NSInteger elapsed, NSNumber *inputPower, NSString **failure);

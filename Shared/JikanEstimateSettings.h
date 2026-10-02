#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <math.h>

FOUNDATION_EXPORT NSString *const JikanEstimateSourceKey;
FOUNDATION_EXPORT NSString *const JikanEstimateAppleTargetKey;
FOUNDATION_EXPORT NSString *const JikanEstimateAppleSyncedKey;

FOUNDATION_EXPORT NSString *JikanEstimateSource(NSUserDefaults *preferences);
FOUNDATION_EXPORT NSInteger JikanEstimateTarget(NSUserDefaults *preferences, NSString *source);
FOUNDATION_EXPORT BOOL JikanAppleTargetIsSupported(NSInteger target);
FOUNDATION_EXPORT NSNumber *JikanAppleTargetFromValue(id value);
FOUNDATION_EXPORT NSNumber *JikanAppleSliderTargetFromValue(id value);

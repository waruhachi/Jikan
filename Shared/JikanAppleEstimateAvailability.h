#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const JikanAppleAvailabilityChangedNotification;
// Published by SpringBoard. Settings never probes IORegistry itself.
FOUNDATION_EXPORT NSDictionary *JikanAppleEstimateAvailability(void);
FOUNDATION_EXPORT NSString *JikanAppleRecommendation(NSDictionary *availability, NSInteger target);
// Pure state transition, shared with the host regression tests.
FOUNDATION_EXPORT NSDictionary *JikanAppleAvailabilityByUpdating(NSDictionary *previous, NSDictionary *batteryInfo, NSDictionary *result, NSInteger target, NSTimeInterval now);
FOUNDATION_EXPORT void JikanPublishAppleEstimateAvailability(NSDictionary *batteryInfo, NSDictionary *result, NSInteger target);
FOUNDATION_EXPORT void JikanRecordAppleEstimateStatus(NSDictionary *snapshot);
FOUNDATION_EXPORT NSString *JikanRecentAppleEstimateFailure(void);

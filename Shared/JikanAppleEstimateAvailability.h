#import <Foundation/Foundation.h>

// Recent availability for the Algorithm footer uses a separate defaults domain.
FOUNDATION_EXPORT void JikanRecordAppleEstimateStatus(NSDictionary *snapshot);
FOUNDATION_EXPORT NSString *JikanRecentAppleEstimateFailure(void);
// A full, currently usable native-input feature vector for the 100% Apple model.
// This is a conservative availability check; absence while unplugged is not
// evidence that the hardware can never expose the readings.
FOUNDATION_EXPORT BOOL JikanAppleHasRequiredNativeInputs(void);

#import <Foundation/Foundation.h>
#import <math.h>

FOUNDATION_EXPORT NSString *const JikanPillPortraitXPercentKey;
FOUNDATION_EXPORT NSString *const JikanPillPortraitYPercentKey;
FOUNDATION_EXPORT NSString *const JikanPillLandscapeXPercentKey;
FOUNDATION_EXPORT NSString *const JikanPillLandscapeYPercentKey;
FOUNDATION_EXPORT NSString *const JikanPreviewXAxisLockKey;
FOUNDATION_EXPORT NSString *const JikanPreviewYAxisLockKey;

typedef struct {
	double x;
	double y;
	BOOL hasCustomPosition;
} JikanPillPosition;

FOUNDATION_EXPORT JikanPillPosition JikanReadPillPosition(NSUserDefaults *preferences, BOOL landscape);
FOUNDATION_EXPORT void JikanSavePillPosition(NSUserDefaults *preferences, BOOL landscape, double x, double y);
FOUNDATION_EXPORT void JikanResetPillPosition(NSUserDefaults *preferences);
FOUNDATION_EXPORT NSDictionary<NSString *, NSNumber *> *JikanPillPositionSliderDefaults(void);

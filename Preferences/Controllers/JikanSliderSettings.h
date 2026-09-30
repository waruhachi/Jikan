#import <Foundation/Foundation.h>
#import <math.h>

#import "../../Shared/JikanPositionSettings.h"

@interface JikanSliderDescriptor : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *preferenceKey;
@property (nonatomic, copy, readonly) NSString *titleKey;
@property (nonatomic, copy, readonly) NSString *fallbackTitle;
@property (nonatomic, assign, readonly) double minimum;
@property (nonatomic, assign, readonly) double maximum;
@end

FOUNDATION_EXPORT NSArray<JikanSliderDescriptor *> *JikanEditableSliders(void);
FOUNDATION_EXPORT NSDictionary<NSString *, NSNumber *> *JikanSliderDefaults(void);
FOUNDATION_EXPORT BOOL JikanParseNumber(NSString *text, NSLocale *locale, double *result);
FOUNDATION_EXPORT NSNumber *JikanNormalizedSliderValue(id value, NSString *key);

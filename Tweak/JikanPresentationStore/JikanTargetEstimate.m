#import "JikanTargetEstimate.h"
#import "../../Localization/JikanLocalization.h"
#import <math.h>

@implementation JikanTargetEstimate
- (instancetype)initWithDictionary:(NSDictionary *)dictionary targetPercent:(NSInteger)targetPercent {
	if ((self = [super init])) {
		_targetPercent = targetPercent;
		_timeString = [dictionary[@"timeString"] isKindOfClass:NSString.class] ? [dictionary[@"timeString"] copy] : JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
		_status = [dictionary[@"estimateStatus"] isKindOfClass:NSString.class] ? [dictionary[@"estimateStatus"] copy] : @"unavailable";
		id seconds = dictionary[@"remainingSeconds"];
		_remainingSeconds = [seconds isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)seconds) != CFBooleanGetTypeID() && isfinite([seconds doubleValue]) && [seconds doubleValue] > 0 ? [seconds doubleValue] : -1;
		_targetReached = [dictionary[@"targetReached"] respondsToSelector:@selector(boolValue)] && [dictionary[@"targetReached"] boolValue];
		_hasEstimate = !_targetReached && _remainingSeconds > 0 && [dictionary[@"hasEstimate"] respondsToSelector:@selector(boolValue)] && [dictionary[@"hasEstimate"] boolValue];
	}
	return self;
}
@end

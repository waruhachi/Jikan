#import "JikanPillContent.h"

@implementation JikanPillContent

- (instancetype)initWithPrimaryText:(NSString *)primaryText secondaryText:(NSString *)secondaryText progress:(double)progress chargingSpeed:(NSString *)chargingSpeed {
	self = [super init];
	if (self) {
		_primaryText = [primaryText copy] ?: @"";
		_secondaryText = [secondaryText copy] ?: @"";
		_chargingSpeed = [chargingSpeed copy] ?: @"normal";
		_progress = isfinite(progress) ? MAX(0.0, MIN(1.0, progress)) : 0.0;
	}
	return self;
}

+ (NSString *)estimateSubtitleForTargetPercent:(NSInteger)target {
	if (target < 100) return [NSString stringWithFormat:JikanLocalizedString(@"jikan.platter.label.until_target", @"until %ld%% charged"), (long)target];
	return JikanLocalizedString(@"jikan.platter.label.until_fully_charged", @"until fully charged");
}

+ (NSString *)formattedWattage:(double)watts {
	if (isfinite(watts) && watts >= 0) {
		NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
		formatter.locale = [NSLocale currentLocale];
		formatter.numberStyle = NSNumberFormatterDecimalStyle;
		formatter.minimumFractionDigits = 1;
		formatter.maximumFractionDigits = 1;
		NSString *number = [formatter stringFromNumber:@(watts)];
		if (number) return [NSString stringWithFormat:@"%@ W", number];
	}
	return JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
}

+ (instancetype)previewContentForTargetPercent:(NSInteger)target {
	return [[self alloc] initWithPrimaryText:JikanLocalizedString(@"jikan.platter.preview.eta", @"1 hr 23 min")
							   secondaryText:[self estimateSubtitleForTargetPercent:target]
									progress:0.72
							   chargingSpeed:@"normal"];
}

@end

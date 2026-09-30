#import "JikanSliderSettings.h"

static NSString *const kPillBackgroundOpacityKey = @"pillBackgroundOpacityPercent";
static NSString *const kBatteryEstimateTargetKey = @"batteryEstimateTargetPercent";

@interface JikanSliderDescriptor ()
- (instancetype)initWithIdentifier:(NSString *)identifier preferenceKey:(NSString *)key titleKey:(NSString *)titleKey fallbackTitle:(NSString *)title minimum:(double)minimum;
@end

@implementation JikanSliderDescriptor

- (instancetype)initWithIdentifier:(NSString *)identifier preferenceKey:(NSString *)key titleKey:(NSString *)titleKey fallbackTitle:(NSString *)title minimum:(double)minimum {
	if ((self = [super init])) {
		_identifier = [identifier copy];
		_preferenceKey = [key copy];
		_titleKey = [titleKey copy];
		_fallbackTitle = [title copy];
		_minimum = minimum;
		_maximum = 100.0;
	}
	return self;
}

@end

NSArray<JikanSliderDescriptor *> *JikanEditableSliders(void) {
	static NSArray<JikanSliderDescriptor *> *descriptors;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		descriptors = @[
			[[JikanSliderDescriptor alloc] initWithIdentifier:@"pillBackgroundOpacitySlider" preferenceKey:kPillBackgroundOpacityKey titleKey:@"jikan.prefs.slider.opacity.title" fallbackTitle:@"Pill Background Opacity" minimum:0],
			[[JikanSliderDescriptor alloc] initWithIdentifier:@"batteryEstimateTargetSlider" preferenceKey:kBatteryEstimateTargetKey titleKey:@"jikan.prefs.slider.estimate_target.title" fallbackTitle:@"Estimate Target" minimum:1],
			[[JikanSliderDescriptor alloc] initWithIdentifier:@"pillPosXPortraitSlider" preferenceKey:JikanPillPortraitXPercentKey titleKey:@"jikan.prefs.slider.portrait_x.title" fallbackTitle:@"Portrait X" minimum:0],
			[[JikanSliderDescriptor alloc] initWithIdentifier:@"pillPosYPortraitSlider" preferenceKey:JikanPillPortraitYPercentKey titleKey:@"jikan.prefs.slider.portrait_y.title" fallbackTitle:@"Portrait Y" minimum:0],
			[[JikanSliderDescriptor alloc] initWithIdentifier:@"pillPosXLandscapeSlider" preferenceKey:JikanPillLandscapeXPercentKey titleKey:@"jikan.prefs.slider.landscape_x.title" fallbackTitle:@"Landscape X" minimum:0],
			[[JikanSliderDescriptor alloc] initWithIdentifier:@"pillPosYLandscapeSlider" preferenceKey:JikanPillLandscapeYPercentKey titleKey:@"jikan.prefs.slider.landscape_y.title" fallbackTitle:@"Landscape Y" minimum:0]
		];
	});
	return descriptors;
}

NSDictionary<NSString *, NSNumber *> *JikanSliderDefaults(void) {
	NSMutableDictionary<NSString *, NSNumber *> *defaults = [JikanPillPositionSliderDefaults() mutableCopy];
	defaults[kPillBackgroundOpacityKey] = @100;
	defaults[kBatteryEstimateTargetKey] = @100;
	return defaults;
}

BOOL JikanParseNumber(NSString *text, NSLocale *locale, double *result) {
	if (![text isKindOfClass:NSString.class]) return NO;
	NSString *input = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!input.length) return NO;
	NSNumberFormatter *formatter = [NSNumberFormatter new];
	formatter.locale = locale;
	formatter.numberStyle = NSNumberFormatterDecimalStyle;
	formatter.usesGroupingSeparator = NO;
	formatter.lenient = NO;
	NSString *decimal = formatter.decimalSeparator;
	NSString *unsignedInput = input;
	if ([input hasPrefix:@"+"] || [input hasPrefix:@"-"]) unsignedInput = [input substringFromIndex:1];
	NSArray<NSString *> *parts = [unsignedInput componentsSeparatedByString:decimal];
	if (parts.count > 2) return NO;
	NSUInteger digitCount = 0;
	for (NSString *part in parts) {
		if ([part rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) return NO;
		digitCount += part.length;
	}
	if (!digitCount) return NO;
	NSNumber *number = [formatter numberFromString:input];
	if (!number || !isfinite(number.doubleValue)) return NO;
	if (result) *result = number.doubleValue;
	return YES;
}

NSNumber *JikanNormalizedSliderValue(id value, NSString *key) {
	NSNumber *fallback = JikanSliderDefaults()[key];
	if (!fallback) return nil;
	double raw = fallback.doubleValue;
	if ([value isKindOfClass:NSNumber.class]) raw = [value doubleValue];
	else if ([value isKindOfClass:NSString.class]) {
		JikanParseNumber(value, [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"], &raw);
	}
	if (!isfinite(raw)) raw = fallback.doubleValue;
	double minimum = [key isEqualToString:kBatteryEstimateTargetKey] ? 1.0 : 0.0;
	return @((NSInteger)llround(MAX(minimum, MIN(100.0, raw))));
}

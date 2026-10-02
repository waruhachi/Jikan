#import "JikanEstimateSettings.h"

NSString *const JikanEstimateSourceKey = @"batteryEstimateSource";
NSString *const JikanEstimateAppleTargetKey = @"batteryEstimateAppleTargetPercent";
NSString *const JikanEstimateAppleSyncedKey = @"batteryEstimateAppleSyncedWithChargeLimiter";

NSString *JikanEstimateSource(NSUserDefaults *preferences) {
	id value = [preferences objectForKey:JikanEstimateSourceKey];
	return [value isKindOfClass:NSString.class] && [value isEqualToString:@"jikan"] ? @"jikan" : @"apple";
}

BOOL JikanAppleTargetIsSupported(NSInteger target) {
	return target == 80 || target == 85 || target == 90 || target == 95 || target == 100;
}

NSNumber *JikanAppleTargetFromValue(id value) {
	if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
	double number = [value doubleValue];
	if (!isfinite(number) || floor(number) != number || !JikanAppleTargetIsSupported((NSInteger)number)) return nil;
	return @((NSInteger)number);
}

NSNumber *JikanAppleSliderTargetFromValue(id value) {
	if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
	double number = [value doubleValue];
	if (!isfinite(number)) return nil;
	return @(80 + 5 * (NSInteger)llround((MAX(80.0, MIN(100.0, number)) - 80.0) / 5.0));
}

NSInteger JikanEstimateTarget(NSUserDefaults *preferences, NSString *source) {
	if ([source isEqualToString:@"apple"]) {
		return [JikanAppleTargetFromValue([preferences objectForKey:JikanEstimateAppleTargetKey]) ?: @100 integerValue];
	}
	id value = [preferences objectForKey:@"batteryEstimateTargetPercent"];
	double number = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 100;
	if (!isfinite(number)) number = 100;
	return (NSInteger)llround(MAX(1.0, MIN(100.0, number)));
}

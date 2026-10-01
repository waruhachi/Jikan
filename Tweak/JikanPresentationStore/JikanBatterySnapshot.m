#import "JikanBatterySnapshot.h"

static id JikanImmutableValue(id value) {
	if ([value isKindOfClass:NSDictionary.class]) {
		NSMutableDictionary *copy = [NSMutableDictionary dictionary];
		for (id key in value) copy[key] = JikanImmutableValue(value[key]);
		return [copy copy];
	}
	if ([value isKindOfClass:NSArray.class]) {
		NSMutableArray *copy = [NSMutableArray array];
		for (id item in value) [copy addObject:JikanImmutableValue(item)];
		return [copy copy];
	}
	return [value conformsToProtocol:@protocol(NSCopying)] ? [value copy] : value;
}

static BOOL JikanExternalPowerConnected(NSDictionary *batteryInfo) {
	id external = batteryInfo[@"ExternalConnected"];
	if ([external respondsToSelector:@selector(boolValue)]) return [external boolValue];
	id charging = batteryInfo[@"IsCharging"];
	if ([charging respondsToSelector:@selector(boolValue)]) return [charging boolValue];
	id fullyCharged = batteryInfo[@"FullyCharged"];
	if ([fullyCharged respondsToSelector:@selector(boolValue)] && [fullyCharged boolValue]) return YES;
	NSDictionary *adapter = [batteryInfo[@"AdapterDetails"] isKindOfClass:NSDictionary.class] ? batteryInfo[@"AdapterDetails"] : nil;
	for (NSString *key in @[@"Current", @"Voltage"]) {
		id value = adapter[key];
		if ([value respondsToSelector:@selector(doubleValue)] && fabs([value doubleValue]) > 0.0) return YES;
	}
	return NO;
}

static double JikanTargetSOC(NSDictionary *batteryInfo, NSString *source) {
	if ([source isEqualToString:@"apple"]) {
		id value = batteryInfo[@"CurrentCapacity"];
		return [value isKindOfClass:NSNumber.class] ? [value doubleValue] : NAN;
	}
	id current = batteryInfo[@"CurrentCapacity"];
	id maximum = batteryInfo[@"MaxCapacity"];
	if (![maximum isKindOfClass:NSNumber.class] || !isfinite([maximum doubleValue]) || [maximum doubleValue] <= 0 || ![current isKindOfClass:NSNumber.class]) {
		current = batteryInfo[@"AppleRawCurrentCapacity"];
		maximum = batteryInfo[@"AppleRawMaxCapacity"];
	}
	if (![current isKindOfClass:NSNumber.class] || ![maximum isKindOfClass:NSNumber.class] || !isfinite([current doubleValue]) || !isfinite([maximum doubleValue]) || [maximum doubleValue] <= 0) return NAN;
	return MAX(0.0, MIN(100.0, [current doubleValue] / [maximum doubleValue] * 100.0));
}

@implementation JikanBatterySnapshot

- (instancetype)initWithDictionary:(NSDictionary *)dictionary settings:(JikanPresentationSettings *)settings {
	self = [super init];
	if (self) {
		NSMutableDictionary *values = [([dictionary isKindOfClass:NSDictionary.class] ? JikanImmutableValue(dictionary) : @{}) mutableCopy];
		_batteryInfo = [values[@"batteryInfo"] isKindOfClass:NSDictionary.class] ? values[@"batteryInfo"] : @{};
		_timeString = [values[@"timeString"] isKindOfClass:NSString.class] ? values[@"timeString"] : JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
		_estimateSource = settings.estimateSource;
		_targetPercent = settings.targetPercent;
		_estimateStatus = [values[@"estimateStatus"] isKindOfClass:NSString.class] ? values[@"estimateStatus"] : @"unavailable";
		_chargingSpeed = [values[@"chargingSpeed"] isKindOfClass:NSString.class] ? values[@"chargingSpeed"] : @"normal";
		_externalPowerConnected = JikanExternalPowerConnected(_batteryInfo);
		id charging = _batteryInfo[@"IsCharging"];
		_charging = [charging respondsToSelector:@selector(boolValue)] ? [charging boolValue] : _externalPowerConnected;
		_hasEstimate = [values[@"hasEstimate"] respondsToSelector:@selector(boolValue)] && [values[@"hasEstimate"] boolValue];
		_targetReached = [values[@"targetReached"] respondsToSelector:@selector(boolValue)] && [values[@"targetReached"] boolValue];
		_fullyCharged = [values[@"isFullyCharged"] respondsToSelector:@selector(boolValue)] && [values[@"isFullyCharged"] boolValue];
		NSInteger percent = [values[@"displayPercent"] respondsToSelector:@selector(integerValue)] ? [values[@"displayPercent"] integerValue] : 0;
		_displayPercent = MAX(0, MIN(100, percent));
		values[@"batteryInfo"] = _batteryInfo;
		values[@"timeString"] = _timeString;
		values[@"estimateSource"] = _estimateSource;
		values[@"targetPercent"] = @(_targetPercent);
		values[@"estimateStatus"] = _estimateStatus;
		values[@"chargingSpeed"] = _chargingSpeed;
		values[@"externalPowerConnected"] = @(_externalPowerConnected);
		values[@"isCharging"] = @(_charging);
		values[@"hasEstimate"] = @(_hasEstimate);
		values[@"targetReached"] = @(_targetReached);
		values[@"isFullyCharged"] = @(_fullyCharged);
		values[@"displayPercent"] = @(_displayPercent);
		_dictionary = [values copy];
	}
	return self;
}

- (JikanBatterySnapshot *)snapshotWithoutEstimateForSettings:(JikanPresentationSettings *)settings {
	NSMutableDictionary *values = [_dictionary mutableCopy];
	double soc = JikanTargetSOC(_batteryInfo, settings.estimateSource);
	values[@"timeString"] = JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
	values[@"hasEstimate"] = @NO;
	values[@"targetReached"] = @(_fullyCharged || (isfinite(soc) && soc >= settings.targetPercent));
	values[@"estimateStatus"] = @"unavailable";
	values[@"sessionStartEstimated"] = @NO;
	values[@"modelRevision"] = @"";
	return [[JikanBatterySnapshot alloc] initWithDictionary:values settings:settings];
}

@end

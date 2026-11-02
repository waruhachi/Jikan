#import "JikanAppleEstimateAvailability.h"
#import "JikanEstimateSettings.h"
#import <sys/utsname.h>

NSString *const JikanAppleAvailabilityChangedNotification = @"moe.waru.jikan.apple-availability.changed";
static NSString *const JikanEstimateStatusSuite = @"moe.waru.jikan.estimate-status";

static NSString *JikanAvailabilityEnvironment(void) {
	struct utsname device;
	uname(&device);
	return [NSString stringWithFormat:@"1:%s:%s", device.machine, device.version];
}

NSDictionary *JikanAppleEstimateAvailability(void) {
	NSUserDefaults *status = [[NSUserDefaults alloc] initWithSuiteName:JikanEstimateStatusSuite];
	[status synchronize];
	NSDictionary *record = [status dictionaryForKey:@"availability"];
	return [record[@"environment"] isEqual:JikanAvailabilityEnvironment()] ? record : @{};
}

NSString *JikanAppleRecommendation(NSDictionary *availability, NSInteger target) {
	if ([availability[@"supportedTargets"] containsObject:@(target)]) return @"apple";
	if ([availability[@"unavailableTargets"] containsObject:@(target)]) return @"jikan";
	return nil;
}

NSDictionary *JikanAppleAvailabilityByUpdating(NSDictionary *previous, NSDictionary *batteryInfo, NSDictionary *result, NSInteger target, NSTimeInterval now) {
	NSMutableDictionary *record = [previous mutableCopy] ?: [NSMutableDictionary dictionary];
	NSDictionary *inputs = [result[@"measuredInputs"] isKindOfClass:NSDictionary.class] ? result[@"measuredInputs"] : result;
	NSString *status = [inputs[@"status"] isKindOfClass:NSString.class] ? inputs[@"status"] : @"unknown";
	NSString *power = inputs[@"powerSource"] ?: inputs[@"inputPowerSource"] ?: @"unavailable";
	NSArray *missing = [inputs[@"missingFeatures"] isKindOfClass:NSArray.class] ? inputs[@"missingFeatures"] : @[];
	if (!missing.count && [status hasPrefix:@"input_power_"]) missing = @[@"PowerTelemetryData.SystemPowerIn"];
	NSMutableSet *supported = [NSMutableSet setWithArray:previous[@"supportedTargets"] ?: @[]];
	NSMutableSet *unavailable = [NSMutableSet setWithArray:previous[@"unavailableTargets"] ?: @[]];
	record[@"target"] = @(target);
	record[@"status"] = status;
	record[@"powerSource"] = power;
	record[@"missingFeatures"] = missing;
	record[@"timestamp"] = @(now);
	BOOL charging = [batteryInfo[@"ExternalConnected"] boolValue] && [batteryInfo[@"IsCharging"] boolValue];
	BOOL measured = [status isEqual:@"available"] && ([@[@"native", @"smc"] containsObject:power]);
	NSArray *inputFailures = @[@"missing_feature_dictionary", @"missing_required_feature", @"missing_amperage_or_voltage", @"missing_input_power", @"invalid_input_power", @"input_power_unavailable", @"input_power_smc_unavailable", @"input_power_access_denied", @"input_power_unsupported_path"];
	BOOL failed = charging && [inputFailures containsObject:status];
	if (charging && measured) {
		[supported addObject:@(target)];
		[unavailable removeObject:@(target)];
	}
	if (failed && ![supported containsObject:@(target)]) {
		NSTimeInterval checkedAt = [inputs[@"checkedAt"] isKindOfClass:NSNumber.class] ? [inputs[@"checkedAt"] doubleValue] : now;
		BOOL sameRun = [previous[@"failureTarget"] isEqual:@(target)] && [previous[@"failureStatus"] isEqual:status] && now >= [previous[@"lastFailure"] doubleValue] && now - [previous[@"lastFailure"] doubleValue] <= 60;
		NSUInteger count = sameRun ? [previous[@"failureCount"] unsignedIntegerValue] : 0;
		NSTimeInterval first = sameRun ? [previous[@"firstFailure"] doubleValue] : now;
		// Cached approximate predictions must not count as fresh sensor checks.
		if (!sameRun || checkedAt > [previous[@"lastInputCheck"] doubleValue]) count++;
		record[@"failureTarget"] = @(target);
		record[@"failureStatus"] = status;
		record[@"failureCount"] = @(count);
		record[@"firstFailure"] = @(first);
		record[@"lastFailure"] = @(now);
		record[@"lastInputCheck"] = @(checkedAt);
		if (count >= 3 && now - first >= 30) [unavailable addObject:@(target)];
	} else {
		[record removeObjectsForKeys:@[@"failureTarget", @"failureStatus", @"failureCount", @"firstFailure", @"lastFailure", @"lastInputCheck"]];
	}
	record[@"supportedTargets"] = [[supported allObjects] sortedArrayUsingSelector:@selector(compare:)];
	record[@"unavailableTargets"] = [[unavailable allObjects] sortedArrayUsingSelector:@selector(compare:)];
	return [record copy];
}

void JikanPublishAppleEstimateAvailability(NSDictionary *batteryInfo, NSDictionary *result, NSInteger target) {
	NSCAssert(NSThread.isMainThread, @"Only SpringBoard's accepted refresh publishes availability");
	NSUserDefaults *status = [[NSUserDefaults alloc] initWithSuiteName:JikanEstimateStatusSuite];
	NSDictionary *previous = JikanAppleEstimateAvailability();
	NSMutableDictionary *record = [JikanAppleAvailabilityByUpdating(previous, batteryInfo, result, target, NSDate.date.timeIntervalSince1970) mutableCopy];
	record[@"environment"] = JikanAvailabilityEnvironment();
	[status setObject:record forKey:@"availability"];
	[status synchronize];
	NSArray *keys = @[@"supportedTargets", @"unavailableTargets", @"target", @"status", @"powerSource", @"missingFeatures"];
	if (![[previous dictionaryWithValuesForKeys:keys] isEqual:[record dictionaryWithValuesForKeys:keys]]) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanAppleAvailabilityChangedNotification, NULL, NULL, YES);
	}
}

void JikanRecordAppleEstimateStatus(NSDictionary *snapshot) {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ queue = dispatch_queue_create("moe.waru.jikan.estimate-status", DISPATCH_QUEUE_SERIAL); });
	dispatch_async(queue, ^{
		NSUserDefaults *status = [[NSUserDefaults alloc] initWithSuiteName:JikanEstimateStatusSuite];
		NSString *algorithm = snapshot[@"estimateSource"] ?: @"";
		NSString *failure = snapshot[@"estimateStatus"] ?: @"";
		NSString *powerSource = snapshot[@"inputPowerSource"] ?: @"";
		NSArray *missingFeatures = [snapshot[@"missingFeatures"] isKindOfClass:NSArray.class] ? snapshot[@"missingFeatures"] : @[];
		NSDictionary *previous = [status dictionaryForKey:@"latest"];
		NSTimeInterval now = [NSDate date].timeIntervalSince1970;
		if ([previous[@"algorithm"] isEqual:algorithm] && [previous[@"status"] isEqual:failure] &&
			[previous[@"powerSource"] isEqual:powerSource] && [previous[@"missingFeatures"] isEqual:missingFeatures] && now - [previous[@"timestamp"] doubleValue] < 300) return;
		[status setObject:@{@"algorithm": algorithm,
			@"status": failure,
			@"missingFeatures": missingFeatures,
			@"powerSource": powerSource,
			@"timestamp": @(now)}
				   forKey:@"latest"];
		[status synchronize];
	});
}

NSString *JikanRecentAppleEstimateFailure(void) {
	NSDictionary *latest = JikanAppleEstimateAvailability();
	NSTimeInterval age = NSDate.date.timeIntervalSince1970 - [latest[@"timestamp"] doubleValue];
	if (!latest.count || age < 0 || age > 360) return nil;
	NSString *failure = latest[@"status"];
	NSArray *missingReadings = @[@"missing_power_state", @"missing_feature_dictionary", @"missing_required_feature", @"missing_amperage_or_voltage", @"missing_input_power", @"invalid_input_power"];
	return [failure hasPrefix:@"input_power_"] || [missingReadings containsObject:failure] ? failure : nil;
}

#import "JikanAppleEstimateAvailability.h"

static NSString *const JikanEstimateStatusSuite = @"moe.waru.jikan.estimate-status";

void JikanRecordAppleEstimateStatus(NSDictionary *snapshot) {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ queue = dispatch_queue_create("moe.waru.jikan.estimate-status", DISPATCH_QUEUE_SERIAL); });
	dispatch_async(queue, ^{
		NSUserDefaults *status = [[NSUserDefaults alloc] initWithSuiteName:JikanEstimateStatusSuite];
		NSString *algorithm = snapshot[@"estimateSource"] ?: @"";
		NSString *failure = snapshot[@"estimateStatus"] ?: @"";
		NSString *powerSource = snapshot[@"inputPowerSource"] ?: @"";
		NSDictionary *previous = [status dictionaryForKey:@"latest"];
		NSTimeInterval now = [NSDate date].timeIntervalSince1970;
		if ([previous[@"algorithm"] isEqual:algorithm] && [previous[@"status"] isEqual:failure] &&
			[previous[@"powerSource"] isEqual:powerSource] && now - [previous[@"timestamp"] doubleValue] < 300) return;
		[status setObject:@{@"algorithm": algorithm,
			@"status": failure,
			@"powerSource": powerSource,
			@"timestamp": @(now)}
				   forKey:@"latest"];
		[status synchronize];
	});
}

NSString *JikanRecentAppleEstimateFailure(void) {
	NSUserDefaults *status = [[NSUserDefaults alloc] initWithSuiteName:JikanEstimateStatusSuite];
	NSDictionary *latest = [status dictionaryForKey:@"latest"];
	NSTimeInterval age = [NSDate date].timeIntervalSince1970 - [latest[@"timestamp"] doubleValue];
	if (![latest[@"algorithm"] isEqual:@"apple"] || age < 0 || age > 360) return nil;
	NSString *failure = latest[@"status"];
	if (![failure isKindOfClass:NSString.class]) return nil;
	NSArray *missingReadings = @[@"missing_power_state", @"missing_feature_dictionary", @"missing_required_feature", @"missing_amperage_or_voltage", @"missing_input_power", @"invalid_input_power"];
	if ([failure hasPrefix:@"input_power_"] || [missingReadings containsObject:failure]) return failure;
	return nil;
}

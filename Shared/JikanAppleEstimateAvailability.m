#import "JikanAppleEstimateAvailability.h"
#import "JikanAppleFeatures.h"
#import <IOKit/IOKitLib.h>

static NSString *const JikanEstimateStatusSuite = @"moe.waru.jikan.estimate-status";

static NSDictionary *JikanApplePowerSourceProperties(void) {
	io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPMPowerSource"));
	if (!service) return nil;
	CFMutableDictionaryRef raw = NULL;
	kern_return_t kr = IORegistryEntryCreateCFProperties(service, &raw, kCFAllocatorDefault, 0);
	IOObjectRelease(service);
	if (kr != KERN_SUCCESS || !raw) return nil;
	return CFBridgingRelease(raw);
}

BOOL JikanAppleHasRequiredNativeInputs(void) {
	NSDictionary *properties = JikanApplePowerSourceProperties();
	if (!properties) return NO;
	// TTL (100%) needs two additional battery fields beyond TT80. Validate the
	// complete existing feature mapping so the default matches usable inference.
	return JikanAppleFeatures(properties, 100, 0, 0, NULL) != nil;
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

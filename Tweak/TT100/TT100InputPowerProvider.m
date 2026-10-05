#import "TT100InputPowerProvider.h"

@implementation TT100InputPowerProvider

+ (NSDictionary *)readSample {
	NSAssert(!NSThread.isMainThread, @"Input-power requests must not block the UI");
	NSXPCConnection *connection = (NSXPCConnection *)[(id<JikanMachServiceConnection>)[NSXPCConnection alloc] initWithMachServiceName:JikanInputPowerServiceName options:NSXPCConnectionPrivileged];
	connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(JikanInputPowerProtocol)];
	[connection resume];
	dispatch_semaphore_t completed = dispatch_semaphore_create(0);
	// Late replies must not race a timed-out caller or change its returned sample.
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	void (^finish)(NSDictionary *) = ^(NSDictionary *sample) {
		@synchronized(result) {
			if (!result[@"sample"]) result[@"sample"] = sample;
		}
		dispatch_semaphore_signal(completed);
	};
	id<JikanInputPowerProtocol> proxy = [connection remoteObjectProxyWithErrorHandler:^(__unused NSError *error) {
		finish(@{@"status": @"input_power_helper_unavailable"});
	}];
	[proxy readInputPowerWithReply:^(NSDictionary *sample) {
		finish([sample isKindOfClass:NSDictionary.class] ? sample : @{@"status": @"input_power_invalid_sample"});
	}];
	BOOL timedOut = dispatch_semaphore_wait(completed, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) != 0;
	NSDictionary *sample;
	@synchronized(result) {
		sample = timedOut ? @{@"status": @"input_power_timeout"} : [result[@"sample"] copy];
	}
	[connection invalidate];
	return sample ?: @{@"status": @"input_power_helper_unavailable"};
}

+ (NSNumber *)milliwattsFromSample:(NSDictionary *)sample batteryInfo:(NSDictionary *)batteryInfo {
	if (![sample[@"status"] isEqual:@"available"] || ![sample[@"source"] isEqual:@"smc"]) return nil;
	NSNumber *power = sample[@"milliwatts"], *timestamp = sample[@"timestamp"];
	if (![power isKindOfClass:NSNumber.class] || ![timestamp isKindOfClass:NSNumber.class]) return nil;
	double age = [NSDate date].timeIntervalSince1970 - timestamp.doubleValue;
	if (!isfinite(age) || age < 0 || age > 3 || !isfinite(power.doubleValue) || power.doubleValue <= 0 || power.doubleValue > 240000) return nil;
	if (![batteryInfo[@"ExternalConnected"] boolValue] || ![batteryInfo[@"IsCharging"] boolValue] ||
		![sample[@"adapter"] isEqual:batteryInfo[@"AdapterDetails"]]) return nil;
	NSDictionary *adapter = batteryInfo[@"AdapterDetails"];
	if (![adapter[@"IsWireless"] isKindOfClass:NSNumber.class] || [adapter[@"IsWireless"] boolValue] || [batteryInfo[@"IsWirelessCharging"] boolValue]) return nil;
	return power;
}

@end

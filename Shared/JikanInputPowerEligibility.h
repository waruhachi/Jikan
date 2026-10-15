#import <Foundation/Foundation.h>
#import <math.h>

// Older power sources (including iOS 14 iPads) can omit IsWireless entirely.
// Missing flags alone do not prove a wireless path. The reader must still
// verify the wired input port and measured power before accepting a sample.
static inline BOOL JikanCanMeasureWiredInputPower(NSDictionary *state) {
	if (![state isKindOfClass:NSDictionary.class] || ![state[@"ExternalConnected"] boolValue] || ![state[@"IsCharging"] boolValue]) return NO;
	NSDictionary *adapter = state[@"AdapterDetails"];
	if (![adapter isKindOfClass:NSDictionary.class]) return NO;
	for (NSString *key in @[@"IsWirelessCharging", @"IsWireless", @"WirelessCharging"]) {
		id flag = state[key];
		if ([flag isKindOfClass:NSNumber.class] && [flag boolValue]) return NO;
	}
	for (NSString *key in @[@"IsWireless", @"WirelessCharging"]) {
		id flag = adapter[key];
		if ([flag isKindOfClass:NSNumber.class] && [flag boolValue]) return NO;
	}
	return YES;
}

// Explicitly opt-in approximation. AdapterDetails reports a capability/limit,
// never measured instantaneous USB input power. Keep this source distinguishable
// from native and SMC readings in all results and diagnostics.
static inline NSNumber *JikanEstimatedAdapterInputMilliwatts(NSDictionary *state) {
	if (!JikanCanMeasureWiredInputPower(state)) return nil;
	NSDictionary *adapter = state[@"AdapterDetails"];
	id rating = adapter[@"Watts"];
	double watts = [rating isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)rating) != CFBooleanGetTypeID() ? [rating doubleValue] : NAN;
	if (!isfinite(watts) || watts <= 0) {
		id voltage = adapter[@"AdapterVoltage"], current = adapter[@"Current"];
		if (![voltage isKindOfClass:NSNumber.class] || ![current isKindOfClass:NSNumber.class] ||
			CFGetTypeID((__bridge CFTypeRef)voltage) == CFBooleanGetTypeID() || CFGetTypeID((__bridge CFTypeRef)current) == CFBooleanGetTypeID()) return nil;
		watts = [voltage doubleValue] * [current doubleValue] * 0.000001;
	}
	if (!isfinite(watts) || watts <= 0 || watts > 240.0) return nil;
	return @(watts * 1000.0);
}

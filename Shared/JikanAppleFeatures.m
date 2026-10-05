#import "JikanAppleFeatures.h"

static NSNumber *JikanFeatureNumber(NSDictionary *dictionary, NSString *key) {
	id value = [dictionary isKindOfClass:NSDictionary.class] ? dictionary[key] : nil;
	if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() || !isfinite([value doubleValue])) return nil;
	return value;
}

static NSNumber *JikanFirstFeatureNumber(NSDictionary *dictionary, NSString *key) {
	id array = [dictionary isKindOfClass:NSDictionary.class] ? dictionary[key] : nil;
	if (![array isKindOfClass:NSArray.class] || [array count] == 0) return nil;
	id value = [array firstObject];
	return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]) ? value : nil;
}

NSArray<NSNumber *> *JikanAppleFeatures(NSDictionary *properties, NSInteger target, NSInteger startSOC, NSInteger elapsed, NSString **failure) {
	return JikanAppleFeaturesWithInputPower(properties, target, startSOC, elapsed, nil, failure);
}

NSArray<NSNumber *> *JikanAppleFeaturesWithInputPower(NSDictionary *properties, NSInteger target, NSInteger startSOC, NSInteger elapsed, NSNumber *inputPower, NSString **failure) {
	if (!JikanAppleTargetIsSupported(target) || startSOC < 0 || startSOC > 100 || elapsed < 0) {
		if (failure) *failure = @"invalid_session";
		return nil;
	}
	NSDictionary *adapter = properties[@"AdapterDetails"];
	NSDictionary *battery = properties[@"BatteryData"];
	NSDictionary *telemetry = properties[@"PowerTelemetryData"];
	if (![adapter isKindOfClass:NSDictionary.class] || ![battery isKindOfClass:NSDictionary.class]) {
		if (failure) *failure = @"missing_feature_dictionary";
		return nil;
	}
	NSNumber *watts = JikanFeatureNumber(adapter, @"Watts");
	if (!watts) {
		NSNumber *voltage = JikanFeatureNumber(adapter, @"AdapterVoltage");
		NSNumber *current = JikanFeatureNumber(adapter, @"Current");
		if (voltage && current) watts = @(voltage.doubleValue * current.doubleValue * 0.000001);
	}
	NSNumber *family = JikanFeatureNumber(adapter, @"FamilyCode");
	NSNumber *temperature = JikanFeatureNumber(properties, @"Temperature");
	NSNumber *cycles = JikanFeatureNumber(properties, @"CycleCount");
	NSNumber *soc = JikanFeatureNumber(properties, @"CurrentCapacity");
	NSNumber *capacity = JikanFeatureNumber(properties, @"NominalChargeCapacity");
	NSNumber *qmax = JikanFirstFeatureNumber(battery, @"Qmax");
	NSNumber *dod = JikanFirstFeatureNumber(battery, @"PresentDOD");
	NSNumber *design = JikanFeatureNumber(properties, @"DesignCapacity");
	NSNumber *power = JikanFeatureNumber(telemetry, @"SystemPowerIn");
	// Invalid native values are errors, not permission to substitute a sensor.
	BOOL nativePowerPresent = [telemetry isKindOfClass:NSDictionary.class] && telemetry[@"SystemPowerIn"] != nil;
	if (!nativePowerPresent) power = JikanFeatureNumber(@{@"power": inputPower ?: NSNull.null}, @"power");
	if (!watts || !family || !temperature || !cycles || !soc || !capacity || !qmax || !dod || !design || !isfinite(watts.doubleValue) || watts.doubleValue <= 0 ||
		floor(family.doubleValue) != family.doubleValue || family.doubleValue < INT32_MIN || family.doubleValue > UINT32_MAX ||
		soc.doubleValue < 0 || soc.doubleValue > 100) {
		if (failure) *failure = @"missing_required_feature";
		return nil;
	}
	BOOL ttl = target != 80;
	NSNumber *amperage = ttl ? JikanFeatureNumber(properties, @"InstantAmperage") : nil;
	NSNumber *batteryVoltage = ttl ? JikanFeatureNumber(properties, @"Voltage") : nil;
	if (ttl && (!amperage || !batteryVoltage)) {
		if (failure) *failure = @"missing_amperage_or_voltage";
		return nil;
	}
	if (!power || power.doubleValue <= 0 || !isfinite((float)(power.doubleValue * 0.001))) {
		if (failure) *failure = nativePowerPresent ? @"invalid_input_power" : @"missing_input_power";
		return nil;
	}
	NSMutableArray<NSNumber *> *features = [NSMutableArray arrayWithObjects:watts, temperature, cycles, soc, capacity, qmax, dod, design, @((float)(power.doubleValue * 0.001)), @(elapsed), nil];
	if (ttl) {
		[features addObjectsFromArray:@[amperage, batteryVoltage, @(startSOC), @(target)]];
	}
	id wireless = adapter[@"IsWireless"];
	[features addObject:@([wireless isKindOfClass:NSNumber.class] && [wireless boolValue] ? 1 : 0)];
	static const uint32_t codes[14] = {
		0xe0004000, 0xe0004002, 0xe0004003, 0xe0004004, 0xe0004005,
		0xe0004006, 0xe0004007, 0xe0004008, 0xe0004009, 0xe000400a,
		0xe0024003, 0xe0024006, 0xe0024007, 0xe0024008};
	uint32_t currentFamily = (uint32_t)family.intValue;
	for (NSUInteger i = 0; i < 14; i++) [features addObject:@(currentFamily == codes[i] ? 1 : 0)];
	return features;
}

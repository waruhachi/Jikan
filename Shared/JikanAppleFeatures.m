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

static BOOL JikanAdapterFamilyCode(NSNumber *value, uint32_t *code) {
	if (!value || !code || !isfinite(value.doubleValue) || floor(value.doubleValue) != value.doubleValue) return NO;
	uint64_t raw = value.unsignedLongLongValue;
	// Older power sources may sign-extend 32-bit adapter IDs when exporting
	// them as unsigned 64-bit values (e.g. 0xffffffffe0004000).
	if ((value.doubleValue >= INT32_MIN && value.doubleValue <= UINT32_MAX) ||
		((raw >> 32) == UINT32_MAX && ((uint32_t)raw & 0x80000000U))) {
		*code = (uint32_t)raw;
		return YES;
	}
	return NO;
}

static NSNumber *JikanNominalCapacity(NSDictionary *properties) {
	// The newer registry exports NCC directly. Always preserve that reading.
	NSNumber *nominal = JikanFeatureNumber(properties, @"NominalChargeCapacity");
	if (nominal) return nominal;

	// Older power sources can expose the battery's raw full-charge capacity
	// instead. Only accept it when its magnitude agrees with DesignCapacity
	// (both in mAh); a percentage-scale MaxCapacity is not interchangeable.
	NSNumber *rawMax = JikanFeatureNumber(properties, @"AppleRawMaxCapacity");
	NSNumber *design = JikanFeatureNumber(properties, @"DesignCapacity");
	if (!rawMax || !design || design.doubleValue <= 0) return nil;
	double fraction = rawMax.doubleValue / design.doubleValue;
	if (fraction < 0.25 || fraction > 1.30) return nil;
	NSNumber *rawCurrent = JikanFeatureNumber(properties, @"AppleRawCurrentCapacity");
	if (rawCurrent && (rawCurrent.doubleValue < 0 || rawCurrent.doubleValue > rawMax.doubleValue * 1.1)) return nil;
	return rawMax;
}

NSArray<NSNumber *> *JikanAppleFeatures(NSDictionary *properties, NSInteger target, NSInteger startSOC, NSInteger elapsed, NSString **failure) {
	return JikanAppleFeaturesWithInputPower(properties, target, startSOC, elapsed, nil, failure);
}

NSArray<NSNumber *> *JikanAppleFeaturesWithInputPower(NSDictionary *properties, NSInteger target, NSInteger startSOC, NSInteger elapsed, NSNumber *inputPower, NSString **failure) {
	return JikanAppleFeaturesWithDiagnostics(properties, target, startSOC, elapsed, inputPower, failure, nil);
}

NSArray<NSNumber *> *JikanAppleFeaturesWithDiagnostics(NSDictionary *properties, NSInteger target, NSInteger startSOC, NSInteger elapsed, NSNumber *inputPower, NSString **failure, NSArray<NSString *> **missingFeatures) {
	if (missingFeatures) *missingFeatures = nil;
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
	uint32_t familyCode = 0;
	BOOL familyValid = JikanAdapterFamilyCode(family, &familyCode);
	NSNumber *temperature = JikanFeatureNumber(properties, @"Temperature");
	NSNumber *cycles = JikanFeatureNumber(properties, @"CycleCount");
	NSNumber *soc = JikanFeatureNumber(properties, @"CurrentCapacity");
	NSNumber *capacity = JikanNominalCapacity(properties);
	NSNumber *qmax = JikanFirstFeatureNumber(battery, @"Qmax");
	NSNumber *dod = JikanFirstFeatureNumber(battery, @"PresentDOD");
	NSNumber *design = JikanFeatureNumber(properties, @"DesignCapacity");
	NSNumber *power = JikanFeatureNumber(telemetry, @"SystemPowerIn");
	// Invalid native values are errors, not permission to substitute a sensor.
	BOOL nativePowerPresent = [telemetry isKindOfClass:NSDictionary.class] && telemetry[@"SystemPowerIn"] != nil;
	if (!nativePowerPresent) power = JikanFeatureNumber(@{@"power": inputPower ?: NSNull.null}, @"power");
	NSMutableArray<NSString *> *missing = [NSMutableArray array];
	if (!watts || !isfinite(watts.doubleValue) || watts.doubleValue <= 0) [missing addObject:@"AdapterDetails.Watts (or AdapterVoltage + Current)"];
	if (!familyValid) [missing addObject:@"AdapterDetails.FamilyCode"];
	if (!temperature) [missing addObject:@"Temperature"];
	if (!cycles) [missing addObject:@"CycleCount"];
	if (!soc || soc.doubleValue < 0 || soc.doubleValue > 100) [missing addObject:@"CurrentCapacity"];
	if (!capacity) [missing addObject:@"NominalChargeCapacity (or compatible AppleRawMaxCapacity)"];
	if (!qmax) [missing addObject:@"BatteryData.Qmax[0]"];
	if (!dod) [missing addObject:@"BatteryData.PresentDOD[0]"];
	if (!design) [missing addObject:@"DesignCapacity"];
	if (missing.count) {
		if (missingFeatures) *missingFeatures = [missing copy];
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
	for (NSUInteger i = 0; i < 14; i++) [features addObject:@(familyCode == codes[i] ? 1 : 0)];
	return features;
}

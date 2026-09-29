#import "JikanStackSettings.h"

NSString *const JikanStackItemsKey = @"stackItems";
NSString *const JikanTemperatureUnitKey = @"temperatureUnit";
NSString *const JikanStackEstimate = @"estimate";
NSString *const JikanStackWattage = @"wattage";
NSString *const JikanStackTemperature = @"temperature";
NSString *const JikanStackVoltage = @"voltage";

static NSNumber *JikanBatteryNumber(NSDictionary *batteryInfo, NSString *key) {
	id value = [batteryInfo isKindOfClass:NSDictionary.class] ? batteryInfo[key] : nil;
	if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() || !isfinite([value doubleValue])) return nil;
	return value;
}

NSArray<NSString *> *JikanNormalizeStackItems(id value) {
	NSMutableArray<NSString *> *result = [NSMutableArray arrayWithObject:JikanStackEstimate];
	if (![value isKindOfClass:NSArray.class]) return result;
	NSSet<NSString *> *allowed = [NSSet setWithArray:@[JikanStackWattage, JikanStackTemperature, JikanStackVoltage]];
	for (id item in (NSArray *)value) {
		if ([item isKindOfClass:NSString.class] && [allowed containsObject:item] && ![result containsObject:item]) [result addObject:item];
	}
	return result;
}

NSArray<NSString *> *JikanStackItems(NSUserDefaults *preferences) {
	id saved = [preferences objectForKey:JikanStackItemsKey];
	if (saved) return JikanNormalizeStackItems(saved);
	return [preferences boolForKey:@"tapToShowWattage"] ? @[JikanStackEstimate, JikanStackWattage] : @[JikanStackEstimate];
}

NSString *JikanTemperatureUnit(NSUserDefaults *preferences) {
	id value = [preferences objectForKey:JikanTemperatureUnitKey];
	return [value isEqual:@"celsius"] || [value isEqual:@"fahrenheit"] ? value : @"system";
}

NSString *JikanResolvedTemperatureUnit(NSUserDefaults *preferences) {
	NSString *choice = JikanTemperatureUnit(preferences);
	if (![choice isEqualToString:@"system"]) return choice;

	NSString *const *key = (NSString *const *)dlsym(RTLD_DEFAULT, "NSLocaleTemperatureUnit");
	id systemValue = key && *key ? [[NSLocale autoupdatingCurrentLocale] objectForKey:*key] : nil;
	if (![systemValue isKindOfClass:NSString.class]) {
		systemValue = [[NSUserDefaults standardUserDefaults] persistentDomainForName:NSGlobalDomain][@"AppleTemperatureUnit"];
	}
	if ([systemValue isEqual:@"Fahrenheit"]) return @"fahrenheit";
	if ([systemValue isEqual:@"Celsius"]) return @"celsius";
	return [[[NSLocale autoupdatingCurrentLocale] objectForKey:NSLocaleCountryCode] isEqual:@"US"] ? @"fahrenheit" : @"celsius";
}

static NSString *JikanDecimalString(double value, NSUInteger fractionDigits) {
	NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
	formatter.locale = [NSLocale currentLocale];
	formatter.numberStyle = NSNumberFormatterDecimalStyle;
	formatter.minimumFractionDigits = fractionDigits;
	formatter.maximumFractionDigits = fractionDigits;
	formatter.usesGroupingSeparator = NO;
	return [formatter stringFromNumber:@(value)];
}

NSString *JikanFormattedBatteryTemperature(NSDictionary *batteryInfo, NSString *unit) {
	NSNumber *reading = JikanBatteryNumber(batteryInfo, @"Temperature");
	if (!reading || reading.doubleValue < -2000.0 || reading.doubleValue > 8000.0) return nil;
	double celsius = reading.doubleValue / 100.0;
	BOOL fahrenheit = [unit isEqualToString:@"fahrenheit"];
	double display = fahrenheit ? celsius * 1.8 + 32.0 : celsius;
	NSString *number = JikanDecimalString(display, 1);
	return number ? [NSString stringWithFormat:@"%@°%@", number, fahrenheit ? @"F" : @"C"] : nil;
}

NSString *JikanFormattedBatteryVoltage(NSDictionary *batteryInfo) {
	NSNumber *reading = JikanBatteryNumber(batteryInfo, @"Voltage");
	if (!reading || reading.doubleValue < 2500.0 || reading.doubleValue > 5000.0) return nil;
	NSString *number = JikanDecimalString(reading.doubleValue / 1000.0, 2);
	return number ? [NSString stringWithFormat:@"%@ V", number] : nil;
}

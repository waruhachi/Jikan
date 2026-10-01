#import "TT100BatteryProvider.h"

@implementation TT100BatteryProvider

+ (double)displaySOCWithBatteryInfo:(NSDictionary *)batteryInfo {
	double maximum = TT100Number(batteryInfo, @"MaxCapacity").doubleValue;
	NSNumber *current = TT100Number(batteryInfo, @"CurrentCapacity");
	if (!isfinite(maximum) || maximum <= 0 || !current) {
		maximum = TT100Number(batteryInfo, @"AppleRawMaxCapacity").doubleValue;
		current = TT100Number(batteryInfo, @"AppleRawCurrentCapacity");
	}
	if (!isfinite(maximum) || maximum <= 0 || !current || !isfinite(current.doubleValue)) return NAN;
	return MAX(0, MIN(100, current.doubleValue / maximum * 100.0));
}

static double TT100WattsFromCurrentVoltage(double current, double voltage) {
	if (!isfinite(current) || !isfinite(voltage)) return 0;
	current = fabs(current);
	voltage = fabs(voltage);
	if (current <= 0 || voltage <= 0) return 0;

	double amps = current;
	if (amps > 20.0) amps = amps / 1000.0;

	double volts = voltage;
	if (volts > 100.0) volts = volts / 1000.0;

	if (amps <= 0 || volts <= 0) return 0;
	return amps * volts;
}

static BOOL TT100IsPlausibleAmps(double amps) {
	return isfinite(amps) && amps > 0.01 && amps <= 12.0;
}

static BOOL TT100IsPlausibleVolts(double volts) {
	return isfinite(volts) && volts >= 2.5 && volts <= 30.0;
}

static double TT100WattsFromKeys(NSDictionary *dict, NSString *currentKey, NSString *voltageKey) {
	if (![dict isKindOfClass:[NSDictionary class]]) return 0;
	double current = fabs([TT100Number(dict, currentKey) doubleValue]);
	double voltage = fabs([TT100Number(dict, voltageKey) doubleValue]);
	if (!isfinite(current) || !isfinite(voltage) || current <= 0 || voltage <= 0) return 0;

	double amps = current;
	if (amps > 20.0) amps /= 1000.0;
	double volts = voltage;
	if (volts > 100.0) volts /= 1000.0;

	if (!TT100IsPlausibleAmps(amps) || !TT100IsPlausibleVolts(volts)) return 0;
	return TT100WattsFromCurrentVoltage(current, voltage);
}

+ (NSString *)chargerClassWithBatteryInfo:(NSDictionary *)batteryInfo outIsWireless:(BOOL *)outIsWireless {
	BOOL isWireless = NO;
	BOOL hasWireless = NO;

	if (![batteryInfo isKindOfClass:[NSDictionary class]]) {
		if (outIsWireless) *outIsWireless = NO;
		return @"unknown";
	}

	NSDictionary *adapter = [batteryInfo[@"AdapterDetails"] isKindOfClass:[NSDictionary class]] ? batteryInfo[@"AdapterDetails"] : nil;

	for (NSString *key in @[@"IsWirelessCharging", @"IsWireless", @"WirelessCharging"]) {
		BOOL has = NO;
		BOOL value = TT100Bool(batteryInfo, key, &has);
		if (has) {
			hasWireless = YES;
			isWireless = value;
			break;
		}
	}
	if (!hasWireless) isWireless = TT100Bool(adapter, @"IsWireless", NULL);

	double watts = 0;
	for (NSString *key in @[@"Wattage", @"Watts", @"Power"]) {
		double value = TT100Number(adapter, key).doubleValue;
		if (isfinite(value) && value > 0 && value <= 240) {
			watts = value;
			break;
		}
	}
	if (watts <= 0) watts = TT100WattsFromKeys(adapter, @"MaxCurrent", @"MaxVoltage");

	NSString *prefix = isWireless ? @"wireless" : @"wired";
	NSString *tier = @"unknown";

	if (watts > 0) {
		if (isWireless) {
			if (watts >= 13.5) tier = @"15w";
			else if (watts >= 9.0)
				tier = @"10w";
			else if (watts >= 6.8)
				tier = @"7w";
			else if (watts >= 4.5)
				tier = @"5w";
			else
				tier = @"lt5w";
		} else {
			if (watts >= 26.0) tier = @"27w";
			else if (watts >= 18.0)
				tier = @"20w";
			else if (watts >= 14.0)
				tier = @"15w";
			else if (watts >= 11.0)
				tier = @"12w";
			else if (watts >= 8.5)
				tier = @"9w";
			else if (watts >= 6.5)
				tier = @"7w";
			else if (watts >= 4.5)
				tier = @"5w";
			else
				tier = @"lt5w";
		}
	}

	if (outIsWireless) *outIsWireless = isWireless;
	if ([tier isEqualToString:@"unknown"]) return isWireless ? @"wireless_unknown" : @"unknown";
	return [NSString stringWithFormat:@"%@_%@", prefix, tier];
}

+ (NSString *)chargerIdentityWithBatteryInfo:(NSDictionary *)batteryInfo {
	NSString *chargerClass = [self chargerClassWithBatteryInfo:batteryInfo outIsWireless:NULL];
	NSDictionary *adapter = [batteryInfo isKindOfClass:[NSDictionary class]] && [batteryInfo[@"AdapterDetails"] isKindOfClass:[NSDictionary class]] ? batteryInfo[@"AdapterDetails"] : nil;
	NSMutableArray *parts = [NSMutableArray arrayWithObject:chargerClass];
	for (NSString *key in @[@"SerialNumber", @"AdapterID", @"ID", @"Manufacturer", @"Model", @"Name"]) {
		id value = adapter[key];
		if (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]]) continue;
		NSString *text = [value description];
		if (text.length) [parts addObject:[NSString stringWithFormat:@"%@:%lu:%@", key, (unsigned long)text.length, text]];
	}
	return [parts componentsJoinedByString:@"|"];
}

+ (double)effectiveChargingWattageWithBatteryInfo:(NSDictionary *)batteryInfo {
	if (![batteryInfo isKindOfClass:[NSDictionary class]]) return NAN;
	NSNumber *connected = TT100Number(batteryInfo, @"ExternalConnected");
	if (connected && !connected.boolValue) return 0;
	double voltage = TT100Number(batteryInfo, @"Voltage").doubleValue;
	if (!isfinite(voltage) || voltage < 2500.0 || voltage > 30000.0) return NAN;
	for (NSString *key in @[@"InstantAmperage", @"Amperage"]) {
		NSNumber *reading = TT100Number(batteryInfo, key);
		if (!reading) continue;
		double current = reading.doubleValue;
		if (!isfinite(current) || fabs(current) > 12000.0) continue;
		return MAX(0.0, current) * voltage * 0.000001;
	}
	return NAN;
}

+ (NSDictionary *)fetchBatteryInfo {
	mach_port_t masterPort = MACH_PORT_NULL;
	io_service_t service = IO_OBJECT_NULL;
	CFMutableDictionaryRef matchingDict = IOServiceMatching("IOPMPowerSource");
	CFMutableDictionaryRef properties = NULL;
	kern_return_t kr = IOMasterPort(MACH_PORT_NULL, &masterPort);
	if (kr != KERN_SUCCESS || masterPort == MACH_PORT_NULL) {
		return nil;
	}
	service = IOServiceGetMatchingService(masterPort, matchingDict);
	if (service) {
		IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0);
		IOObjectRelease(service);
	} else {
		mach_port_deallocate(mach_task_self(), masterPort);
		return nil;
	}
	mach_port_deallocate(mach_task_self(), masterPort);
	if (properties) {
		NSDictionary *result = [NSDictionary dictionaryWithDictionary:(__bridge NSDictionary *)properties];
		CFRelease(properties);
#if DEBUG
		@try {
			static dispatch_once_t onceToken;
			dispatch_once(&onceToken, ^{
				NSString *logPath = jbroot(@"/tmp/Jikan.txt");
				NSString *logString;
				if ([NSJSONSerialization isValidJSONObject:result]) {
					NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
					logString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
				} else {
					logString = [result description];
				}
				[logString writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
			});
		}
		@catch (__unused NSException *e) {
		}
#endif
		return result;
	}
	return nil;
}

+ (BOOL)isFullyChargedWithBatteryInfo:(NSDictionary *)batteryInfo displayPercent:(NSInteger *)outPercent {
	double soc = [self displaySOCWithBatteryInfo:batteryInfo];
	BOOL full = TT100Bool(batteryInfo, @"FullyCharged", NULL) || (isfinite(soc) && soc >= 100.0);
	if (outPercent) *outPercent = isfinite(soc) ? (NSInteger)llround(soc) : (full ? 100 : 0);
	return full;
}

@end

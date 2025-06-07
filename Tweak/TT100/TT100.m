#import "TT100.h"
#import <IOKit/IOKitLib.h>
#import <mach/mach_port.h>

@implementation TT100

+ (instancetype)sharedInstance {
	static TT100 *sharedInstance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedInstance = [[self alloc] init];
	});
	return sharedInstance;
}

- (void)_refreshBatteryInfo {
	NSDictionary *batteryInfo = [TT100 fetchBatteryInfo];
	NSString *timeString = [TT100 estimatedTT100WithBatteryInfo:batteryInfo];
	NSDictionary *userInfo = @{ @"batteryInfo": batteryInfo ?: @{}, @"timeString": timeString ?: @"N/A" };
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:@"TT100BatteryInfoUpdated" object:self userInfo:userInfo];
	});
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
		@try {
			NSString *logPath = @"/tmp/Jikan.txt";
			NSString *logString;
			if ([NSJSONSerialization isValidJSONObject:result]) {
				NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
				logString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
			} else {
				logString = [result description];
			}
			[logString writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
		} @catch (__unused NSException *e) {}
		return result;
	}
	return nil;
}

+ (NSString *)estimatedTT100WithBatteryInfo:(NSDictionary *)batteryInfo {
	if (![batteryInfo isKindOfClass:[NSDictionary class]]) {
		return @"N/A";
	}

	double rawMax_mAh = -1;
	double rawCurrent_mAh = -1;

	NSNumber *designCap = batteryInfo[@"DesignCapacity"];
	NSNumber *percentMax = batteryInfo[@"MaxCapacity"];
	NSNumber *percentCurr = batteryInfo[@"CurrentCapacity"];
	NSNumber *rawMaxNum = batteryInfo[@"AppleRawMaxCapacity"];
	NSNumber *rawCurrNum = batteryInfo[@"AppleRawCurrentCapacity"];

	if (rawCurrNum && rawMaxNum) {
		rawMax_mAh = [rawMaxNum doubleValue];
		rawCurrent_mAh = [rawCurrNum doubleValue];
	} else if (percentCurr && percentMax && designCap) {
		double pctCurr = 0.0;
		if ([percentMax doubleValue] != 0.0) {
			pctCurr = [percentCurr doubleValue] / [percentMax doubleValue];
		}
		double design_mAh = [designCap doubleValue];

		rawMax_mAh = design_mAh;
		rawCurrent_mAh = pctCurr * design_mAh;
	}

	if (rawCurrNum && rawMaxNum && percentCurr) {
		if ([rawCurrNum doubleValue] == [rawMaxNum doubleValue] && [percentCurr intValue] == 100) {
			return @"Fully Charged";
		}
	}

	if (rawCurrent_mAh < 0 || rawMax_mAh <= 0 || rawCurrent_mAh >= rawMax_mAh) {
		return @"N/A";
	}

	double remaining_mAh = rawMax_mAh - rawCurrent_mAh;

	double chargingCurrent_mA = 0;
	NSDictionary *chargerData = batteryInfo[@"ChargerData"];
	if ([chargerData isKindOfClass:[NSDictionary class]]) {
		NSNumber *chCurr = chargerData[@"ChargingCurrent"];
		if (chCurr && [chCurr doubleValue] > 0) {
			chargingCurrent_mA = [chCurr doubleValue];
		}
	}
	if (chargingCurrent_mA <= 0) {
		NSNumber *ampNum = batteryInfo[@"Amperage"];
		if (ampNum && [ampNum doubleValue] > 0) {
			chargingCurrent_mA = [ampNum doubleValue];
		}
	}
	if (chargingCurrent_mA <= 0) {
		NSDictionary *adapterDetails = batteryInfo[@"AdapterDetails"];
		if ([adapterDetails isKindOfClass:[NSDictionary class]]) {
			NSNumber *adapterCurr = adapterDetails[@"Current"];
			if (adapterCurr && [adapterCurr doubleValue] > 0) {
				chargingCurrent_mA = [adapterCurr doubleValue];
			}
		}
	}
	if (chargingCurrent_mA <= 0) {
		return @"N/A";
	}

	NSNumber *tempNum = batteryInfo[@"Temperature"];
	if (tempNum) {
		double tempC = [tempNum doubleValue] / 100.0;
		if (tempC < 0.0 || tempC > 45.0) {
			chargingCurrent_mA *= 0.5;
		}
	}

	NSDictionary *adapterDetails = batteryInfo[@"AdapterDetails"];
	if ([adapterDetails isKindOfClass:[NSDictionary class]]) {
		NSNumber *isWireless = adapterDetails[@"IsWireless"];
		if (isWireless && [isWireless boolValue]) {
			chargingCurrent_mA *= 0.85;
		}
	}
	if (chargingCurrent_mA <= 0) {
		return @"N/A";
	}

	double hoursToFull = remaining_mAh / chargingCurrent_mA;
	double secondsToFull = hoursToFull * 3600.0;

	if (!(secondsToFull > 0) || !isfinite(secondsToFull)) {
		return @"N/A";
	}

	int hours = (int)(secondsToFull / 3600.0);
	int totalMinutes = (int)((secondsToFull + 59) / 60);
	int minutes = totalMinutes % 60;

	if (hours > 0 && minutes > 0) {
		return [NSString stringWithFormat:@"%d hr %d min", hours, minutes];
	} else if (hours > 0) {
		return [NSString stringWithFormat:@"%d hr", hours];
	} else if (minutes > 0) {
		return [NSString stringWithFormat:@"%d min", minutes];
	} else {
		return @"<1 min";
	}
}

+ (NSString *)estimatedTT100 {
	NSDictionary *batteryInfo = [self fetchBatteryInfo];
	return [self estimatedTT100WithBatteryInfo:batteryInfo];
}

@end

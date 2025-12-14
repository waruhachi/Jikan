#import "TT100.h"
#import "TT100Database.h"

NSString *const TT100BatteryInfoUpdatedNotification = @"TT100BatteryInfoUpdated";
NSString *const TT100InternalDidRefreshBatteryInfoNotification = @"TT100InternalDidRefreshBatteryInfo";
NSString *const JikanChargingStateChangedNotification = @"JikanChargingStateChanged";

NSString *TT100PLSQLPath(void) {
	static NSString *cachedPath = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSString *baseDir = jbroot(@"/var/containers/Shared/SystemGroup/");
		NSString *suffix = jbroot(@"/Library/BatteryLife/CurrentPowerlog.PLSQL");
		DIR *dir = opendir([baseDir UTF8String]);
		if (!dir) return;
		struct dirent *entry;
		while ((entry = readdir(dir)) != NULL) {
			if (entry->d_type == DT_DIR) {
				NSString *name = [NSString stringWithUTF8String:entry->d_name];
				if ([name hasPrefix:@"."]) continue;
				NSString *candidate = [baseDir stringByAppendingPathComponent:name];
				candidate = [candidate stringByAppendingString:suffix];
				if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
					cachedPath = jbroot(candidate);
					break;
				}
			}
		}
		closedir(dir);
	});
	return cachedPath;
}

@implementation TT100

static NSNumber *TT100Number(NSDictionary *dict, NSString *key) {
	id v = dict[key];
	return [v isKindOfClass:[NSNumber class]] ? (NSNumber *)v : nil;
}

static BOOL TT100Bool(NSDictionary *dict, NSString *key, BOOL *outHasValue) {
	NSNumber *n = TT100Number(dict, key);
	if (n) {
		if (outHasValue) *outHasValue = YES;
		return n.boolValue;
	}
	if (outHasValue) *outHasValue = NO;
	return NO;
}

static double TT100WattsFromCurrentVoltage(double current, double voltage) {
	// Heuristics: AdapterDetails often provides Current (mA) and Voltage (mV).
	if (!isfinite(current) || !isfinite(voltage)) return 0;
	current = fabs(current);
	voltage = fabs(voltage);
	if (current <= 0 || voltage <= 0) return 0;

	// Convert current to amps
	double amps = current;
	if (amps > 20.0) amps = amps / 1000.0;	// likely mA
	// Convert voltage to volts
	double volts = voltage;
	if (volts > 100.0) volts = volts / 1000.0;	// likely mV

	if (amps <= 0 || volts <= 0) return 0;
	return amps * volts;
}

+ (NSString *)chargerClassWithBatteryInfo:(NSDictionary *)batteryInfo outIsWireless:(BOOL *)outIsWireless {
	BOOL isWireless = NO;
	BOOL hasWireless = NO;

	if (![batteryInfo isKindOfClass:[NSDictionary class]]) {
		if (outIsWireless) *outIsWireless = NO;
		return @"unknown";
	}

	NSDictionary *adapter = [batteryInfo[@"AdapterDetails"] isKindOfClass:[NSDictionary class]] ? batteryInfo[@"AdapterDetails"] : nil;

	// Wireless detection: try a few common keys (varies by iOS / power source).
	BOOL tmpHas = NO;
	if (TT100Bool(batteryInfo, @"IsWirelessCharging", &tmpHas) || TT100Bool(batteryInfo, @"IsWireless", &tmpHas) || TT100Bool(batteryInfo, @"WirelessCharging", &tmpHas)) {
		if (tmpHas) {
			hasWireless = YES;
			isWireless = TT100Bool(batteryInfo, @"IsWirelessCharging", NULL) || TT100Bool(batteryInfo, @"IsWireless", NULL) || TT100Bool(batteryInfo, @"WirelessCharging", NULL);
		}
	}
	if (!hasWireless && adapter) {
		BOOL has = NO;
		BOOL v = TT100Bool(adapter, @"IsWireless", &has);
		if (has) {
			hasWireless = YES;
			isWireless = v;
		}
	}

	// Wattage detection.
	double watts = 0;
	if (adapter) {
		NSNumber *w = TT100Number(adapter, @"Wattage");
		if (!w) w = TT100Number(adapter, @"Watts");
		if (!w) w = TT100Number(adapter, @"Power");
		if (w) watts = fabs(w.doubleValue);
	}
	if (watts <= 0 && adapter) {
		double cur = fabs([TT100Number(adapter, @"Current") doubleValue]);
		double volt = fabs([TT100Number(adapter, @"Voltage") doubleValue]);
		watts = TT100WattsFromCurrentVoltage(cur, volt);
	}

	// If we still don't have watts, approximate from batteryInfo amperage/voltage if present.
	if (watts <= 0) {
		double cur = fabs([TT100Number(batteryInfo, @"Amperage") doubleValue]);
		double volt = fabs([TT100Number(batteryInfo, @"Voltage") doubleValue]);
		double approx = TT100WattsFromCurrentVoltage(cur, volt);
		if (approx > 0) watts = approx;
	}

	NSString *prefix = isWireless ? @"wireless" : @"wired";
	NSString *tier = @"unknown";

	// Buckets are intentionally coarse and stable to prevent DB fragmentation.
	if (watts > 0) {
		if (isWireless) {
			if (watts >= 13.5) tier = @"15w";
			else if (watts >= 9.0)
				tier = @"10w";
			else if (watts >= 6.8)
				tier = @"7w";  // "7.5W" class
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
	if ([tier isEqualToString:@"unknown"]) return @"unknown";
	return [NSString stringWithFormat:@"%@_%@", prefix, tier];
}

+ (instancetype)sharedInstance {
	static TT100 *sharedInstance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedInstance = [[self alloc] init];
	});
	return sharedInstance;
}

static NSTimer *tt100PollingTimer = nil;

+ (void)startMonitoring {
	if (tt100PollingTimer) {
		[tt100PollingTimer invalidate];
		tt100PollingTimer = nil;
	}
	tt100PollingTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
														 target:[self sharedInstance]
													   selector:@selector(_refreshBatteryInfo)
													   userInfo:nil
														repeats:YES];
}

- (void)_refreshBatteryInfo {
	NSDictionary *batteryInfo = [TT100 fetchBatteryInfo];

	extern BOOL isCharging;
	if (isCharging && batteryInfo) {
		[[NSNotificationCenter defaultCenter] postNotificationName:TT100InternalDidRefreshBatteryInfoNotification object:nil userInfo:@{@"batteryInfo": batteryInfo}];
	}
	NSString *timeString = [TT100 estimatedTT100WithBatteryInfo:batteryInfo];

	NSDictionary *userInfo = @{@"batteryInfo": batteryInfo ?: @{}, @"timeString": timeString ?: @"N/A"};
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:TT100BatteryInfoUpdatedNotification object:self userInfo:userInfo];
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

static NSDate *TT100ParseDate(NSString *dateString) {
	static NSDateFormatter *fmt = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		fmt = [[NSDateFormatter alloc] init];
		fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
		fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
	});
	return [fmt dateFromString:dateString];
}

+ (NSDictionary<NSString *, NSNumber *> *)loadHistoryFromPLSQL {
	NSError *err = nil;
	NSString *sql = [NSString stringWithContentsOfFile:TT100PLSQLPath() encoding:NSUTF8StringEncoding error:&err];
	if (!sql.length) {
		NSLog(@"[TT100] Could not read PL/SQL file: %@", err);
		return @{};
	}

	NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"INSERT INTO\\s+battery_history\\s*\\(\\s*pct\\s*,\\s*seconds(?:\\s*,\\s*timestamp)?\\s*\\)\\s*VALUES\\s*\\(\\s*(\\d+)\\s*,\\s*([0-9]+\\.?[0-9]*)(?:\\s*,\\s*'([0-9:-\\s]+)')?\\s*\\)" options:NSRegularExpressionCaseInsensitive error:&err];
	if (!re) {
		NSLog(@"[TT100] Regex error: %@", err);
		return @{};
	}
	NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *perBucket = [NSMutableDictionary new];
	NSArray<NSTextCheckingResult *> *matches = [re matchesInString:sql options:0 range:NSMakeRange(0, sql.length)];
	NSDate *now = [NSDate date];
	NSTimeInterval maxAge = 30 * 24 * 3600;
	for (NSTextCheckingResult *m in matches) {
		NSString *pctStr = [sql substringWithRange:[m rangeAtIndex:1]];
		NSString *secStr = [sql substringWithRange:[m rangeAtIndex:2]];
		double seconds = secStr.doubleValue;

		if (seconds < 10 || seconds > 3600) continue;
		NSDate *ts = nil;
		if ([m numberOfRanges] > 3 && [m rangeAtIndex:3].location != NSNotFound) {
			NSString *dateStr = [sql substringWithRange:[m rangeAtIndex:3]];
			ts = TT100ParseDate(dateStr);
		}

		if (ts && [now timeIntervalSinceDate:ts] > maxAge) continue;
		NSMutableArray *arr = perBucket[pctStr];
		if (!arr) arr = perBucket[pctStr] = [NSMutableArray new];
		[arr addObject:@{@"seconds": @(seconds), @"date": ts ?: [NSNull null]}];
	}

	NSMutableDictionary<NSString *, NSNumber *> *buckets = [NSMutableDictionary new];
	for (NSString *pctStr in perBucket) {
		NSArray *arr = perBucket[pctStr];
		double sum = 0, totalWeight = 0;
		for (NSDictionary *entry in arr) {
			double seconds = [entry[@"seconds"] doubleValue];
			NSDate *ts = entry[@"date"] == [NSNull null] ? nil : entry[@"date"];
			double weight = 1.0;
			if (ts) {
				double daysAgo = [[NSDate date] timeIntervalSinceDate:ts] / (24 * 3600.0);

				weight = fmax(0.5, 1.0 - daysAgo / 60.0);
			}
			sum += seconds * weight;
			totalWeight += weight;
		}
		if (totalWeight > 0) {
			buckets[pctStr] = @(sum / totalWeight);
		}
	}
	return buckets;
}

+ (NSDictionary<NSString *, NSNumber *> *)cachedHistoryBuckets {
	static NSDictionary<NSString *, NSNumber *> *cached = nil;
	static NSDate *cachedMTime = nil;
	static dispatch_queue_t q;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		q = dispatch_queue_create("com.tt100.plsql-cache", DISPATCH_QUEUE_SERIAL);
	});

	__block NSDictionary<NSString *, NSNumber *> *out = nil;
	dispatch_sync(q, ^{
		NSString *path = TT100PLSQLPath();
		NSDate *mtime = nil;
		if (path.length) {
			NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
			mtime = attrs[NSFileModificationDate];
		}

		BOOL needsReload = (cached == nil);
		if (!needsReload && mtime && cachedMTime) {
			needsReload = ([mtime compare:cachedMTime] == NSOrderedDescending);
		}

		if (needsReload) {
			cached = [self loadHistoryFromPLSQL];
			cachedMTime = mtime;
		}
		out = cached ?: @{};
	});
	return out;
}

+ (NSString *)estimatedTT100WithBatteryInfo:(NSDictionary *)batteryInfo {
	if (![batteryInfo isKindOfClass:[NSDictionary class]]) return NSLocalizedString(@"N/A", @"Not available");

	double rawMax_mAh = -1, rawCurr_mAh = -1;
	NSNumber *designCap = batteryInfo[@"DesignCapacity"];
	NSNumber *pctMax = batteryInfo[@"MaxCapacity"];
	NSNumber *pctCurr = batteryInfo[@"CurrentCapacity"];
	NSNumber *rawMaxNum = batteryInfo[@"AppleRawMaxCapacity"];
	NSNumber *rawCurrNum = batteryInfo[@"AppleRawCurrentCapacity"];

	if (rawMaxNum && rawCurrNum) {
		rawMax_mAh = rawMaxNum.doubleValue;
		rawCurr_mAh = rawCurrNum.doubleValue;
	} else if (designCap && pctMax && pctCurr) {
		double design = designCap.doubleValue;
		double frac = pctCurr.doubleValue / pctMax.doubleValue;
		rawMax_mAh = design;
		rawCurr_mAh = frac * design;
	}
	if (rawCurr_mAh < 0 || rawMax_mAh <= 0 || rawCurr_mAh >= rawMax_mAh) {
		return NSLocalizedString(@"N/A", @"Not available");
	}

	double soc = NAN;
	if (pctMax && pctCurr && pctMax.doubleValue > 0) {
		soc = (pctCurr.doubleValue / pctMax.doubleValue) * 100.0;
	} else {
		soc = (rawCurr_mAh / rawMax_mAh) * 100.0;
	}
	if (!isfinite(soc)) return NSLocalizedString(@"N/A", @"Not available");
	if (soc < 0) soc = 0;
	if (soc > 100.0) soc = 100.0;
	if (soc >= 100.0) return NSLocalizedString(@"N/A", @"Not available");

	double frac = soc - floor(soc);
	NSInteger lower = (NSInteger)floor(soc);
	NSInteger upper = (NSInteger)ceil(soc);
	if (lower < 0) lower = 0;
	if (upper < 0) upper = 0;
	if (lower > 99) lower = 99;
	if (upper > 99) upper = 99;

	double median[100];
	double iqr[100];
	int sampleCounts[100];
	BOOL isWireless = NO;
	NSString *chargerClass = [self chargerClassWithBatteryInfo:batteryInfo outIsWireless:&isWireless];
	BOOL haveDB = NO;
	if (chargerClass.length && ![chargerClass isEqualToString:@"unknown"]) {
		haveDB = [[TT100Database shared] fetchPercentStatsForChargerClass:chargerClass intoMedian:median iqr:iqr sampleCounts:sampleCounts];
	}
	if (!haveDB) {
		haveDB = [[TT100Database shared] fetchPercentStatsForChargerClass:@"unknown" intoMedian:median iqr:iqr sampleCounts:sampleCounts];
	}
	NSDictionary<NSString *, NSNumber *> *buckets = haveDB ? nil : [self cachedHistoryBuckets];
	double logEstimate = 0;
	BOOL usedBuckets = NO;
	BOOL missingBucket = NO;

	double *medianPtr = median;
	__unused double *iqrPtr = iqr;
	double (^bucketSeconds)(NSInteger) = ^double(NSInteger percent) {
		if (percent < 0 || percent >= 100) return NAN;
		if (haveDB) {
			double v = medianPtr[percent];
			return isnan(v) ? NAN : v;
		} else {
			NSNumber *n = buckets[@(percent).stringValue];
			return n ? n.doubleValue : NAN;
		}
	};

	double interpolated = 0;
	double lowerSec = bucketSeconds(lower);
	double upperSec = bucketSeconds(upper);
	if (!isnan(lowerSec) && !isnan(upperSec)) {
		interpolated = lowerSec * (1.0 - frac) + upperSec * frac;
		usedBuckets = YES;
		logEstimate += interpolated;
	} else if (!isnan(lowerSec)) {
		interpolated = lowerSec;
		usedBuckets = YES;
		logEstimate += interpolated;
		missingBucket = YES;
	} else if (!isnan(upperSec)) {
		interpolated = upperSec;
		usedBuckets = YES;
		logEstimate += interpolated;
		missingBucket = YES;
	} else {
		missingBucket = YES;
	}

	for (NSInteger pct = upper + 1; pct < 100; pct++) {
		double sec = bucketSeconds(pct);
		if (!isnan(sec)) {
			logEstimate += sec;
		} else {
			missingBucket = YES;
			break;
		}
	}

	double liveEstimate = 0;
	NSDictionary *adapter = batteryInfo[@"AdapterDetails"];
	double adapterCurr = fabs([adapter[@"Current"] doubleValue]);
	if (adapterCurr <= 0) adapterCurr = fabs([batteryInfo[@"Amperage"] doubleValue]);
	if (adapterCurr > 1e-6) {
		liveEstimate = ((rawMax_mAh - rawCurr_mAh) / adapterCurr) * 3600.0;
	}

	double remainingSeconds = 0;
	if (usedBuckets && logEstimate > 0 && !missingBucket) {
		remainingSeconds = logEstimate;
	} else if (usedBuckets && logEstimate > 0 && liveEstimate > 0) {
		remainingSeconds = 0.7 * logEstimate + 0.3 * liveEstimate;
	} else if (liveEstimate > 0) {
		remainingSeconds = liveEstimate;
	} else {
		return NSLocalizedString(@"N/A", @"Not available");
	}

	int hrs = (int)(remainingSeconds / 3600.0);
	int mins = (int)round(fmod(remainingSeconds, 3600.0) / 60.0);
	if (mins >= 60) {
		hrs++;
		mins -= 60;
	}

	if (hrs > 0 && mins > 0) {
		return [NSString stringWithFormat:NSLocalizedString(@"%d hr %d min", @"hours and minutes"), hrs, mins];
	} else if (hrs > 0) {
		return [NSString stringWithFormat:NSLocalizedString(@"%d hr", @"hours"), hrs];
	} else if (mins > 0) {
		return [NSString stringWithFormat:NSLocalizedString(@"%d min", @"minutes"), mins];
	} else {
		return NSLocalizedString(@"<1 min", @"less than one minute");
	}
}

+ (NSString *)estimatedTT100 {
	NSDictionary *batteryInfo = [self fetchBatteryInfo];
	return [self estimatedTT100WithBatteryInfo:batteryInfo];
}

@end

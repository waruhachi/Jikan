#import <limits.h>
#import <math.h>

#import "TT100.h"
#import "TT100Database.h"

NSString *const TT100BatteryInfoUpdatedNotification = @"TT100BatteryInfoUpdated";
NSString *const TT100InternalDidRefreshBatteryInfoNotification = @"TT100InternalDidRefreshBatteryInfo";
NSString *const JikanChargingStateChangedNotification = @"JikanChargingStateChanged";

NSString *TT100PLSQLPath(void) {
	static NSString *cachedPath = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSString *baseDir = jbroot(@"/var/containers/Shared/SystemGroup");
		NSString *relativeSuffix = @"Library/BatteryLife/CurrentPowerlog.PLSQL";
		DIR *dir = opendir([baseDir UTF8String]);
		if (!dir) return;
		struct dirent *entry;
		while ((entry = readdir(dir)) != NULL) {
			if (entry->d_type == DT_DIR) {
				NSString *name = [NSString stringWithUTF8String:entry->d_name];
				if ([name hasPrefix:@"."]) continue;
				NSString *candidate = [baseDir stringByAppendingPathComponent:name];
				candidate = [candidate stringByAppendingPathComponent:relativeSuffix];
				if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
					cachedPath = candidate;
					break;
				}
			}
		}
		closedir(dir);
	});
	return cachedPath;
}

@interface TT100 ()
+ (NSString *)_estimatedTT100WithBatteryInfo:(NSDictionary *)batteryInfo targetPercent:(NSInteger)targetPercent;
@end

@implementation TT100

static NSNumber *TT100Number(NSDictionary *dict, NSString *key) {
	if (![dict isKindOfClass:[NSDictionary class]]) return nil;
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

static double TT100DisplaySOC(NSDictionary *batteryInfo) {
	double maximum = TT100Number(batteryInfo, @"MaxCapacity").doubleValue;
	NSNumber *current = TT100Number(batteryInfo, @"CurrentCapacity");
	if (!isfinite(maximum) || maximum <= 0 || !current) {
		maximum = TT100Number(batteryInfo, @"AppleRawMaxCapacity").doubleValue;
		current = TT100Number(batteryInfo, @"AppleRawCurrentCapacity");
	}
	if (!isfinite(maximum) || maximum <= 0 || !current || !isfinite(current.doubleValue)) return NAN;
	return MAX(0, MIN(100, current.doubleValue / maximum * 100.0));
}

static NSInteger TT100EstimateTargetPercent(void) {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"moe.waru.jikan.preferences"];
	NSInteger target = 100;
	if ([prefs objectForKey:@"batteryEstimateTargetPercent"]) {
		target = [prefs integerForKey:@"batteryEstimateTargetPercent"];
	}
	if (target < 1) target = 1;
	if (target > 100) target = 100;
	return target;
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

static double TT100ExtractWattage(NSDictionary *batteryInfo) {
	return [TT100 effectiveChargingWattageWithBatteryInfo:batteryInfo];
}

static NSString *TT100ChargingSpeed(NSDictionary *batteryInfo, BOOL isWireless) {
#pragma unused(isWireless)
	double watts = TT100ExtractWattage(batteryInfo);
	if (!isfinite(watts) || watts <= 0) return @"normal";
	return (watts < 5.0) ? @"slow" : @"normal";
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
	if (![batteryInfo isKindOfClass:[NSDictionary class]]) return 0;
	NSDictionary *adapter = [batteryInfo[@"AdapterDetails"] isKindOfClass:[NSDictionary class]] ? batteryInfo[@"AdapterDetails"] : nil;

	double watts = TT100WattsFromKeys(batteryInfo, @"InstantAmperage", @"Voltage");
	if (watts > 0) return watts;

	watts = TT100WattsFromKeys(batteryInfo, @"Amperage", @"Voltage");
	if (watts > 0) return watts;

	watts = TT100WattsFromKeys(adapter, @"Current", @"Voltage");
	if (watts > 0) return watts;

	NSNumber *w = TT100Number(adapter, @"Wattage");
	if (!w) w = TT100Number(adapter, @"Watts");
	if (!w) w = TT100Number(adapter, @"Power");
	double ratedWatts = fabs(w.doubleValue);
	if (!isfinite(ratedWatts) || ratedWatts <= 0 || ratedWatts > 240.0) return 0;
	return ratedWatts;
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
static dispatch_queue_t tt100RefreshQueue;
static NSDictionary *tt100LatestSnapshot;
static BOOL tt100Monitoring;
static BOOL tt100RefreshInFlight;
static BOOL tt100RefreshPending;
static NSUInteger tt100Generation;

+ (NSDictionary *)latestSnapshot {
	NSAssert([NSThread isMainThread], @"latestSnapshot must be read on the main thread");
	return tt100LatestSnapshot;
}

+ (void)startMonitoring {
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{ [self startMonitoring]; });
		return;
	}
	if (tt100Monitoring) return;
	tt100Monitoring = YES;
	tt100Generation++;
	tt100PollingTimer = [NSTimer timerWithTimeInterval:15.0 target:[self sharedInstance] selector:@selector(_refreshBatteryInfo) userInfo:nil repeats:YES];
	tt100PollingTimer.tolerance = 1.0;
	[[NSRunLoop mainRunLoop] addTimer:tt100PollingTimer forMode:NSRunLoopCommonModes];
	[[self sharedInstance] _refreshBatteryInfo];
}

+ (void)stopMonitoring {
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{ [self stopMonitoring]; });
		return;
	}
	tt100Monitoring = NO;
	tt100Generation++;
	[tt100PollingTimer invalidate];
	tt100PollingTimer = nil;
	tt100RefreshPending = NO;
	tt100LatestSnapshot = nil;
}

- (void)_refreshBatteryInfo {
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{ [self _refreshBatteryInfo]; });
		return;
	}
	if (!tt100Monitoring) return;
	if (tt100RefreshInFlight) {
		tt100RefreshPending = YES;
		return;
	}
	static dispatch_once_t once;
	dispatch_once(&once, ^{ tt100RefreshQueue = dispatch_queue_create("moe.waru.jikan.refresh", DISPATCH_QUEUE_SERIAL); });
	tt100RefreshInFlight = YES;
	tt100RefreshPending = NO;
	NSUInteger generation = tt100Generation;
	dispatch_async(tt100RefreshQueue, ^{
		@autoreleasepool {
			NSDictionary *batteryInfo = [TT100 fetchBatteryInfo];
			NSInteger target = [TT100 targetPercent];
			NSString *timeString = [TT100 _estimatedTT100WithBatteryInfo:batteryInfo targetPercent:target];
			BOOL hasEstimate = ![timeString isEqualToString:JikanLocalizedString(@"jikan.tt100.value.na", @"N/A")];
			NSInteger percent = 0;
			BOOL fullyCharged = [TT100 isFullyChargedWithBatteryInfo:batteryInfo displayPercent:&percent];
			BOOL targetReached = fullyCharged || (isfinite(TT100DisplaySOC(batteryInfo)) && TT100DisplaySOC(batteryInfo) >= target);
			BOOL wireless = NO;
			NSString *chargerClass = [TT100 chargerClassWithBatteryInfo:batteryInfo outIsWireless:&wireless];
			NSDictionary *snapshot = @{
				@"batteryInfo": batteryInfo ?: @{},
				@"timeString": timeString,
				@"hasEstimate": @(hasEstimate && !targetReached),
				@"isFullyCharged": @(fullyCharged),
				@"targetReached": @(targetReached),
				@"displayPercent": @(percent),
				@"targetPercent": @(target),
				@"chargingSpeed": TT100ChargingSpeed(batteryInfo, wireless),
				@"chargerClass": chargerClass,
				@"chargerIdentity": [TT100 chargerIdentityWithBatteryInfo:batteryInfo]
			};
			dispatch_async(dispatch_get_main_queue(), ^{
				if (tt100Monitoring && generation == tt100Generation) {
					tt100LatestSnapshot = snapshot;
					[[NSNotificationCenter defaultCenter] postNotificationName:TT100InternalDidRefreshBatteryInfoNotification object:self userInfo:snapshot];
					if (tt100Monitoring && generation == tt100Generation) {
						[[NSNotificationCenter defaultCenter] postNotificationName:TT100BatteryInfoUpdatedNotification object:self userInfo:snapshot];
					}
				}
				tt100RefreshInFlight = NO;
				if (tt100Monitoring && tt100RefreshPending) [self _refreshBatteryInfo];
			});
		}
	});
}

+ (BOOL)hasEstimateWithBatteryInfo:(NSDictionary *)batteryInfo {
	NSString *estimate = [self estimatedTT100WithBatteryInfo:batteryInfo];
	if (![estimate isKindOfClass:[NSString class]]) return NO;
	return ![estimate isEqualToString:JikanLocalizedString(@"jikan.tt100.value.na", @"N/A")];
}

+ (NSInteger)targetPercent {
	return TT100EstimateTargetPercent();
}

+ (BOOL)isFullyChargedWithBatteryInfo:(NSDictionary *)batteryInfo displayPercent:(NSInteger *)outPercent {
	double soc = TT100DisplaySOC(batteryInfo);
	BOOL full = TT100Bool(batteryInfo, @"FullyCharged", NULL) || (isfinite(soc) && soc >= 100.0);
	if (outPercent) *outPercent = isfinite(soc) ? (NSInteger)llround(soc) : (full ? 100 : 0);
	return full;
}

+ (BOOL)isTargetReachedWithBatteryInfo:(NSDictionary *)batteryInfo displayPercent:(NSInteger *)outPercent {
	NSInteger percent = 0;
	BOOL full = [self isFullyChargedWithBatteryInfo:batteryInfo displayPercent:&percent];
	if (outPercent) *outPercent = percent;
	return full || (isfinite(TT100DisplaySOC(batteryInfo)) && TT100DisplaySOC(batteryInfo) >= [self targetPercent]);
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
	return [self _estimatedTT100WithBatteryInfo:batteryInfo targetPercent:[self targetPercent]];
}

+ (NSString *)_estimatedTT100WithBatteryInfo:(NSDictionary *)batteryInfo targetPercent:(NSInteger)targetPercent {
	NSString *unavailable = JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
	if (![batteryInfo isKindOfClass:[NSDictionary class]]) return unavailable;
	BOOL hasCharging = NO;
	BOOL charging = TT100Bool(batteryInfo, @"IsCharging", &hasCharging);
	if (hasCharging && !charging) return unavailable;
	double soc = TT100DisplaySOC(batteryInfo);
	if (!isfinite(soc) || soc >= targetPercent || TT100Bool(batteryInfo, @"FullyCharged", NULL)) return unavailable;
	double rawMax = TT100Number(batteryInfo, @"AppleRawMaxCapacity").doubleValue;
	double rawCurrent = TT100Number(batteryInfo, @"AppleRawCurrentCapacity").doubleValue;
	if (!isfinite(rawMax) || rawMax <= 0 || !TT100Number(batteryInfo, @"AppleRawCurrentCapacity")) {
		rawMax = TT100Number(batteryInfo, @"DesignCapacity").doubleValue;
		rawCurrent = rawMax * soc / 100.0;
	}
	double current = fabs(TT100Number(batteryInfo, @"InstantAmperage").doubleValue);
	if (!isfinite(current) || current <= 0) current = fabs(TT100Number(batteryInfo, @"Amperage").doubleValue);
	double liveSecondsPerPercent = NAN;
	if (isfinite(rawMax) && isfinite(rawCurrent) && rawMax > rawCurrent && rawCurrent >= 0 && isfinite(current) && current > 0) {
		liveSecondsPerPercent = ((rawMax - rawCurrent) / (100.0 - soc)) / current * 3600.0;
	}

	double estimate[100], uncertainty[100], updated[100];
	int counts[100];
	NSString *chargerClass = [self chargerClassWithBatteryInfo:batteryInfo outIsWireless:NULL];
	BOOL haveDB = [[TT100Database shared] fetchPercentStatsForChargerClass:chargerClass intoEstimate:estimate uncertainty:uncertainty sampleCounts:counts lastUpdated:updated];
	if (!haveDB && ![chargerClass isEqualToString:@"unknown"]) {
		haveDB = [[TT100Database shared] fetchPercentStatsForChargerClass:@"unknown" intoEstimate:estimate uncertainty:uncertainty sampleCounts:counts lastUpdated:updated];
	}
	NSDictionary *buckets = haveDB ? nil : [self cachedHistoryBuckets];
	double remainingSeconds = 0;
	for (NSInteger percent = (NSInteger)floor(soc); percent < targetPercent; percent++) {
		double fraction = MIN((double)percent + 1.0, (double)targetPercent) - MAX((double)percent, soc);
		double seconds = haveDB ? estimate[percent] : [buckets[@(percent).stringValue] doubleValue];
		if (!isfinite(seconds) || seconds <= 0 || (haveDB && counts[percent] <= 0)) seconds = liveSecondsPerPercent;
		if (!isfinite(seconds) || seconds <= 0) return unavailable;
		remainingSeconds += seconds * fraction;
	}
	if (!isfinite(remainingSeconds) || remainingSeconds <= 0 || remainingSeconds > INT_MAX) return unavailable;

	int hrs = (int)(remainingSeconds / 3600.0);
	int mins = (int)round(fmod(remainingSeconds, 3600.0) / 60.0);
	if (mins >= 60) {
		hrs++;
		mins -= 60;
	}

	if (hrs > 0 && mins > 0) {
		return [NSString stringWithFormat:JikanLocalizedString(@"jikan.tt100.format.hr_min", @"%d hr %d min"), hrs, mins];
	} else if (hrs > 0) {
		return [NSString stringWithFormat:JikanLocalizedString(@"jikan.tt100.format.hr", @"%d hr"), hrs];
	} else if (mins > 0) {
		return [NSString stringWithFormat:JikanLocalizedString(@"jikan.tt100.format.min", @"%d min"), mins];
	} else {
		return JikanLocalizedString(@"jikan.tt100.format.lt1min", @"<1 min");
	}
}

+ (NSString *)estimatedTT100 {
	NSDictionary *batteryInfo = [self fetchBatteryInfo];
	return [self estimatedTT100WithBatteryInfo:batteryInfo];
}

@end

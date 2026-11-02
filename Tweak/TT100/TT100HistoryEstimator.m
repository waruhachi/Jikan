#import "TT100HistoryEstimator.h"

@implementation TT100HistoryEstimator

+ (NSString *)formattedTimeForSeconds:(double)seconds {
	NSString *unavailable = JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
	if (!isfinite(seconds) || seconds <= 0 || seconds > INT_MAX) return unavailable;
	int hrs = (int)(seconds / 3600.0);
	int mins = (int)round(fmod(seconds, 3600.0) / 60.0);
	if (mins >= 60) {
		hrs++;
		mins -= 60;
	}
	if (hrs > 0 && mins > 0) return [NSString stringWithFormat:JikanLocalizedString(@"jikan.tt100.format.hr_min", @"%d hr %d min"), hrs, mins];
	if (hrs > 0) return [NSString stringWithFormat:JikanLocalizedString(@"jikan.tt100.format.hr", @"%d hr"), hrs];
	if (mins > 0) return [NSString stringWithFormat:JikanLocalizedString(@"jikan.tt100.format.min", @"%d min"), mins];
	return JikanLocalizedString(@"jikan.tt100.format.lt1min", @"<1 min");
}

+ (NSString *)estimatedTimeWithBatteryInfo:(NSDictionary *)batteryInfo targetPercent:(NSInteger)targetPercent {
	return [self formattedTimeForSeconds:[self estimatedSecondsWithBatteryInfo:batteryInfo targetPercent:targetPercent]];
}

+ (double)estimatedSecondsWithBatteryInfo:(NSDictionary *)batteryInfo targetPercent:(NSInteger)targetPercent {
	return [[self estimatedSecondsWithBatteryInfo:batteryInfo targets:@[@(targetPercent)]][@(targetPercent).stringValue] doubleValue];
}

+ (NSDictionary<NSString *, NSNumber *> *)estimatedSecondsWithBatteryInfo:(NSDictionary *)batteryInfo targets:(NSArray<NSNumber *> *)targets {
	NSMutableDictionary *results = [NSMutableDictionary dictionary];
	NSInteger highestTarget = 0;
	for (NSNumber *target in targets) {
		results[target.stringValue] = @(NAN);
		if (target.integerValue >= 1 && target.integerValue <= 100) highestTarget = MAX(highestTarget, target.integerValue);
	}
	if (![batteryInfo isKindOfClass:[NSDictionary class]]) return results;
	BOOL hasCharging = NO;
	BOOL charging = TT100Bool(batteryInfo, @"IsCharging", &hasCharging);
	if (hasCharging && !charging) return results;
	double soc = [TT100BatteryProvider displaySOCWithBatteryInfo:batteryInfo];
	if (!isfinite(soc) || soc < 0 || soc >= highestTarget || TT100Bool(batteryInfo, @"FullyCharged", NULL)) return results;
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
	NSString *chargerClass = [TT100BatteryProvider chargerClassWithBatteryInfo:batteryInfo outIsWireless:NULL];
	BOOL haveDB = [[TT100Database shared] fetchPercentStatsForChargerClass:chargerClass intoEstimate:estimate uncertainty:uncertainty sampleCounts:counts lastUpdated:updated];
	if (!haveDB && ![chargerClass isEqualToString:@"unknown"]) {
		haveDB = [[TT100Database shared] fetchPercentStatsForChargerClass:@"unknown" intoEstimate:estimate uncertainty:uncertainty sampleCounts:counts lastUpdated:updated];
	}
	NSDictionary *buckets = haveDB ? nil : [TT100LegacyHistory cachedHistoryBuckets];
	double cumulative[101];
	for (NSInteger i = 0; i <= 100; i++) cumulative[i] = NAN;
	double remainingSeconds = 0;
	for (NSInteger percent = (NSInteger)floor(soc); percent < highestTarget; percent++) {
		double fraction = percent + 1.0 - MAX((double)percent, soc);
		double seconds = haveDB ? estimate[percent] : [buckets[@(percent).stringValue] doubleValue];
		if (!isfinite(seconds) || seconds <= 0 || (haveDB && counts[percent] <= 0)) seconds = liveSecondsPerPercent;
		if (!isfinite(seconds) || seconds <= 0) break;
		remainingSeconds += seconds * fraction;
		if (!isfinite(remainingSeconds) || remainingSeconds > INT_MAX) break;
		cumulative[percent + 1] = remainingSeconds;
	}
	for (NSNumber *target in targets) {
		NSInteger value = target.integerValue;
		if (value >= 1 && value <= 100 && value > soc && isfinite(cumulative[value]) && cumulative[value] > 0) results[target.stringValue] = @(cumulative[value]);
	}
	return [results copy];
}

@end

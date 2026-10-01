#import "TT100.h"

@interface TT100 ()
+ (NSString *)_estimatedTT100WithBatteryInfo:(NSDictionary *)batteryInfo targetPercent:(NSInteger)targetPercent;
@end

@implementation TT100

static NSInteger TT100EstimateTargetPercent(void) {
	if ([NSThread isMainThread]) return [JikanPresentationStore sharedInstance].state.settings.targetPercent;
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	return JikanEstimateTarget(prefs, JikanEstimateSource(prefs));
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

+ (NSDictionary *)fetchBatteryInfo {
	return [TT100BatteryProvider fetchBatteryInfo];
}

+ (NSString *)chargerClassWithBatteryInfo:(NSDictionary *)batteryInfo outIsWireless:(BOOL *)outIsWireless {
	return [TT100BatteryProvider chargerClassWithBatteryInfo:batteryInfo outIsWireless:outIsWireless];
}

+ (NSString *)chargerIdentityWithBatteryInfo:(NSDictionary *)batteryInfo {
	return [TT100BatteryProvider chargerIdentityWithBatteryInfo:batteryInfo];
}

+ (double)effectiveChargingWattageWithBatteryInfo:(NSDictionary *)batteryInfo {
	return [TT100BatteryProvider effectiveChargingWattageWithBatteryInfo:batteryInfo];
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
static BOOL tt100Monitoring;
static BOOL tt100RefreshInFlight;
static BOOL tt100RefreshPending;
static NSUInteger tt100Generation;
static CFRunLoopSourceRef tt100PowerSource = NULL;
static TT100AppleEstimator *tt100AppleEstimator;
static NSString *tt100LastAppleStatus;
static NSInteger tt100LastAppleTarget;
static NSInteger tt100LastAppleSession;

static void TT100PowerChanged(void *context) {
#pragma unused(context)
	[[TT100 sharedInstance] _refreshBatteryInfo];
}

+ (NSDictionary *)latestSnapshot {
	NSAssert([NSThread isMainThread], @"latestSnapshot must be read on the main thread");
	return [JikanPresentationStore sharedInstance].state.snapshot.dictionary;
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
	tt100PowerSource = IOPSNotificationCreateRunLoopSource(TT100PowerChanged, NULL);
	if (tt100PowerSource) CFRunLoopAddSource(CFRunLoopGetMain(), tt100PowerSource, kCFRunLoopCommonModes);
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
	if (tt100PowerSource) {
		CFRunLoopRemoveSource(CFRunLoopGetMain(), tt100PowerSource, kCFRunLoopCommonModes);
		CFRelease(tt100PowerSource);
		tt100PowerSource = NULL;
	}
	tt100RefreshPending = NO;
	[[JikanPresentationStore sharedInstance] clearBatterySnapshot];
	if (tt100RefreshQueue) dispatch_async(tt100RefreshQueue, ^{ [tt100AppleEstimator reset]; });
}

+ (void)preferencesDidChange {
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{ [self preferencesDidChange]; });
		return;
	}
	tt100Generation++;
	[[JikanPresentationStore sharedInstance] reloadPreferences];
	if (tt100Monitoring) [[self sharedInstance] _refreshBatteryInfo];
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
	JikanPresentationStore *presentationStore = [JikanPresentationStore sharedInstance];
	JikanPresentationState *presentation = presentationStore.state;
	dispatch_async(tt100RefreshQueue, ^{
		@autoreleasepool {
			NSDictionary *batteryInfo = [TT100 fetchBatteryInfo];
			NSString *source = presentation.settings.estimateSource;
			NSInteger target = presentation.settings.targetPercent;
			if (!tt100AppleEstimator) tt100AppleEstimator = [TT100AppleEstimator new];
			[tt100AppleEstimator observeBatteryInfo:batteryInfo];
			NSDictionary *appleResult = [source isEqualToString:@"apple"] ? [tt100AppleEstimator resultForBatteryInfo:batteryInfo target:target] : nil;
			if (appleResult && (![appleResult[@"status"] isEqualToString:tt100LastAppleStatus] || tt100LastAppleTarget != target || tt100LastAppleSession != [appleResult[@"session"] integerValue])) {
				tt100LastAppleStatus = appleResult[@"status"];
				tt100LastAppleTarget = target;
				tt100LastAppleSession = [appleResult[@"session"] integerValue];
				NSLog(@"[Jikan] Apple estimate status: %@, target: %ld%%, remaining: %.1f seconds, approximate session start: %@", tt100LastAppleStatus, (long)target, [appleResult[@"seconds"] doubleValue], [appleResult[@"sessionStartEstimated"] boolValue] ? @"yes" : @"no");
			} else if (!appleResult) {
				tt100LastAppleStatus = nil;
			}
			BOOL hasEstimate = appleResult ? [appleResult[@"status"] isEqualToString:@"available"] : NO;
			NSString *timeString = appleResult ? [TT100HistoryEstimator formattedTimeForSeconds:[appleResult[@"seconds"] doubleValue]] : [TT100 _estimatedTT100WithBatteryInfo:batteryInfo targetPercent:target];
			if (!appleResult) hasEstimate = ![timeString isEqualToString:JikanLocalizedString(@"jikan.tt100.value.na", @"N/A")];
			NSInteger percent = 0;
			BOOL fullyCharged = [TT100 isFullyChargedWithBatteryInfo:batteryInfo displayPercent:&percent];
			double targetSOC = [source isEqualToString:@"apple"] ? TT100Number(batteryInfo, @"CurrentCapacity").doubleValue : [TT100BatteryProvider displaySOCWithBatteryInfo:batteryInfo];
			BOOL targetReached = fullyCharged || (isfinite(targetSOC) && targetSOC >= target);
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
				@"estimateSource": source,
				@"estimateStatus": appleResult[@"status"] ?: (hasEstimate ? @"available" : @"unavailable"),
				@"sessionStartEstimated": @([appleResult[@"sessionStartEstimated"] boolValue]),
				@"modelRevision": appleResult[@"revision"] ?: @"",
				@"chargingSpeed": TT100ChargingSpeed(batteryInfo, wireless),
				@"chargerClass": chargerClass,
				@"chargerIdentity": [TT100 chargerIdentityWithBatteryInfo:batteryInfo]
			};
			dispatch_async(dispatch_get_main_queue(), ^{
				if (tt100Monitoring && generation == tt100Generation) {
					BOOL published = [presentationStore publishBatteryDictionary:snapshot generation:presentation.estimateGeneration publisher:self];
					if (published && tt100Monitoring && generation == tt100Generation) {
						if ([snapshot[@"estimateStatus"] isEqualToString:@"waiting_for_first_prediction"]) {
							dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
								if (tt100Monitoring && generation == tt100Generation) [self _refreshBatteryInfo];
							});
						}
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
	return [TT100BatteryProvider isFullyChargedWithBatteryInfo:batteryInfo displayPercent:outPercent];
}

+ (BOOL)isTargetReachedWithBatteryInfo:(NSDictionary *)batteryInfo displayPercent:(NSInteger *)outPercent {
	NSInteger percent = 0;
	BOOL full = [self isFullyChargedWithBatteryInfo:batteryInfo displayPercent:&percent];
	if (outPercent) *outPercent = percent;
	return full || (isfinite([TT100BatteryProvider displaySOCWithBatteryInfo:batteryInfo]) && [TT100BatteryProvider displaySOCWithBatteryInfo:batteryInfo] >= [self targetPercent]);
}

+ (NSDictionary<NSString *, NSNumber *> *)loadHistoryFromPLSQL {
	return [TT100LegacyHistory loadHistoryFromPLSQL];
}

+ (NSDictionary<NSString *, NSNumber *> *)cachedHistoryBuckets {
	return [TT100LegacyHistory cachedHistoryBuckets];
}

+ (NSString *)estimatedTT100WithBatteryInfo:(NSDictionary *)batteryInfo {
	JikanPresentationSettings *settings = [NSThread isMainThread] ? [JikanPresentationStore sharedInstance].state.settings : [[JikanPresentationSettings alloc] initWithPreferences:[[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite]];
	if ([settings.estimateSource isEqualToString:@"apple"]) {
		if ([NSThread isMainThread]) return [self latestSnapshot][@"timeString"] ?: JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
		return JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
	}
	return [self _estimatedTT100WithBatteryInfo:batteryInfo targetPercent:settings.targetPercent];
}

+ (NSString *)_estimatedTT100WithBatteryInfo:(NSDictionary *)batteryInfo targetPercent:(NSInteger)targetPercent {
	return [TT100HistoryEstimator estimatedTimeWithBatteryInfo:batteryInfo targetPercent:targetPercent];
}

+ (NSString *)estimatedTT100 {
	NSDictionary *batteryInfo = [self fetchBatteryInfo];
	return [self estimatedTT100WithBatteryInfo:batteryInfo];
}

@end

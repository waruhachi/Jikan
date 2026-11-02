#import <Foundation/Foundation.h>
#import <CoreML/CoreML.h>
#import <time.h>
#import "../Shared/JikanStackSelection.h"
#import "../Shared/JikanEstimateSettings.h"
#import "../Tweak/JikanPresentationStore/JikanPresentationStore.h"
#import "../Tweak/TT100/TT100AppleEstimator.h"
#import "../Tweak/TT100/TT100HistoryEstimator.h"

NSString *JikanLocalizedString(NSString *key, NSString *fallback) { return fallback ?: key; }

@interface MemoryDefaults : NSUserDefaults
@property NSMutableDictionary *values;
@end
@implementation MemoryDefaults
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (void)setObject:(id)value forKey:(NSString *)key { self.values[key] = value; }
- (BOOL)boolForKey:(NSString *)key { return [self.values[key] boolValue]; }
- (double)doubleForKey:(NSString *)key { return [self.values[key] doubleValue]; }
- (NSInteger)integerForKey:(NSString *)key { return [self.values[key] integerValue]; }
@end

static NSUInteger checks;
#define CHECK(...) do { checks++; NSCAssert((__VA_ARGS__), @"Check %lu failed: %s", (unsigned long)checks, #__VA_ARGS__); } while (0)
static JikanStackItem *Main(void) { return JikanNormalizeStackItems(nil).firstObject; }
static JikanStackItem *Reading(NSString *type) { return [[JikanStackItem alloc] initWithIdentifier:type type:type targetPercent:nil]; }
static void Update(JikanStackSelection *selection, NSArray *items, NSArray *reached, BOOL connected, NSUInteger generation) {
	[selection updateItems:items mainTarget:80 reachedTargets:[NSSet setWithArray:reached] connected:connected generation:generation];
}

static void TestSettingsAndSelection(void) {
	NSArray<JikanStackItem *> *legacy = JikanNormalizeStackItems(@[@"wattage", @"estimate", @"temperature", @"wattage", @"voltage", @"unknown"]);
	CHECK(legacy.count == 4);
	CHECK([legacy.firstObject isMainEstimate]);
	CHECK([legacy[1].type isEqual:JikanStackWattage]);
	JikanStackItem *ninety = [JikanStackItem estimateWithTargetPercent:90];
	JikanStackItem *full = [JikanStackItem estimateWithTargetPercent:100];
	NSArray *items = @[Main(), full, Reading(JikanStackWattage), ninety];
	CHECK([JikanNormalizeStackItems(JikanStackPropertyList(items)) isEqual:items]);
	CHECK([JikanStackTargets(items, 80) isEqual:@[@80, @90, @100]]);
	CHECK(JikanEffectiveStackItems(items, 90).count == 3);
	CHECK([ninety.identifier isEqual:JikanNormalizeStackItems(JikanStackPropertyList(items)).lastObject.identifier]);
	NSArray *invalid = JikanNormalizeStackItems(@[@{@"id": @"a", @"type": @"estimate", @"target": @YES}, @{@"id": @"b", @"type": @"estimate", @"target": @90.5}, @{@"id": @"c", @"type": @"estimate", @"target": @101}, @{@"id": @"d", @"type": @"estimate", @"target": @(NAN)}, @42, NSNull.null]);
	CHECK(invalid.count == 1);
	CHECK(JikanNormalizeStackItems(@[ninety, [JikanStackItem estimateWithTargetPercent:90]]).count == 2);
	CHECK([JikanAvailableStackTargets(items, 80, @"apple", nil) isEqual:@[@85, @95]]);
	CHECK([JikanAvailableStackTargets(items, 80, @"apple", ninety.identifier) isEqual:@[@85, @90, @95]]);
	CHECK(JikanAvailableStackTargets(items, 80, @"jikan", nil).count == 97);
	CHECK(![JikanAvailableStackTargets(items, 80, @"apple", ninety.identifier) containsObject:@72]);
	CHECK(![JikanAvailableStackTargets(items, 80, @"jikan", ninety.identifier) containsObject:@80]);

	JikanStackSelection *selection = [JikanStackSelection new];
	Update(selection, items, @[], YES, 0);
	CHECK([selection.selectedIdentifier isEqual:JikanStackEstimate]);
	Update(selection, items, @[@80], YES, 0);
	CHECK([selection.selectedIdentifier isEqual:ninety.identifier]); // percentage order, not Stack order
	Update(selection, items, @[@80, @90], YES, 0);
	CHECK([selection.selectedIdentifier isEqual:full.identifier]);
	[selection selectNextItem];
	CHECK([selection.selectedIdentifier isEqual:JikanStackWattage]);
	Update(selection, items, @[@80, @90, @100], YES, 0);
	CHECK([selection.selectedIdentifier isEqual:JikanStackWattage]); // never interrupt a reading
	[selection selectNextItem];
	CHECK([selection.selectedIdentifier isEqual:ninety.identifier]);
	Update(selection, items, @[@80, @90, @100], YES, 0);
	CHECK([selection.selectedIdentifier isEqual:ninety.identifier]); // manual visit to completed target sticks
	Update(selection, items, @[@80], YES, 0);
	CHECK([selection isTargetCompleted:90]); // no backwards jumps on fluctuation
	Update(selection, items, @[], NO, 0);
	CHECK(![selection isTargetCompleted:90]);
	CHECK([selection.selectedIdentifier isEqual:JikanStackEstimate]);
	[selection selectNextItem];
	NSString *previewSelection = selection.selectedIdentifier;
	Update(selection, items, @[], NO, 0);
	CHECK([selection.selectedIdentifier isEqual:previewSelection]); // unplugged preview survives refreshes
	Update(selection, items, @[], YES, 0);
	CHECK([selection.selectedIdentifier isEqual:JikanStackEstimate]); // reconnect starts from the main estimate
	Update(selection, items, @[@80, @90], YES, 0);
	CHECK([selection.selectedIdentifier isEqual:full.identifier]); // skip multiple crossed targets
	Update(selection, @[Main(), ninety], @[@80, @90], YES, 1);
	CHECK([selection.selectedIdentifier isEqual:JikanStackEstimate]); // selected item removed
	Update(selection, items, @[], NO, 1);
	Update(selection, items, @[@80, @90], YES, 1);
	CHECK([selection.selectedIdentifier isEqual:full.identifier]); // start above main target
	Update(selection, items, @[], NO, 1);
	Update(selection, items, @[], YES, 1);
	Update(selection, items, @[@80], YES, 2);
	CHECK([selection.selectedIdentifier isEqual:JikanStackEstimate]); // settings invalidation cannot fake a crossing
}

static NSDictionary *Battery(double percent, BOOL connected) {
	return @{@"CurrentCapacity": @(percent), @"MaxCapacity": @100, @"ExternalConnected": @(connected), @"IsCharging": @(connected), @"AdapterDetails": @{@"Watts": @20}, @"PowerTelemetryData": @{@"SystemPowerIn": @10000}};
}
static NSDictionary *Snapshot(NSDictionary *battery, NSInteger main, NSDictionary *results, NSString *source) {
	NSDictionary *primary = results[@(main).stringValue] ?: @{};
	NSMutableDictionary *snapshot = [primary mutableCopy];
	[snapshot addEntriesFromDictionary:@{@"batteryInfo": battery, @"targetPercent": @(main), @"estimateSource": source, @"targetEstimates": results, @"displayPercent": battery[@"CurrentCapacity"]}];
	return snapshot;
}
static void TestPresentation(void) {
	MemoryDefaults *prefs = [MemoryDefaults new];
	[prefs setObject:@"jikan" forKey:JikanEstimateSourceKey];
	[prefs setObject:@80 forKey:@"batteryEstimateTargetPercent"];
	[prefs setObject:JikanStackPropertyList(@[Main(), [JikanStackItem estimateWithTargetPercent:100]]) forKey:JikanStackItemsKey];
	JikanPresentationStore *store = [[JikanPresentationStore alloc] initWithPreferences:prefs];
	NSDictionary *results = @{@"80": @{@"targetReached": @YES}, @"100": @{@"targetReached": @NO, @"hasEstimate": @YES, @"remainingSeconds": @600, @"timeString": @"10 min", @"estimateStatus": @"available"}};
	CHECK([store publishBatteryDictionary:Snapshot(Battery(80, YES), 80, results, @"jikan") generation:0 publisher:nil]);
	CHECK(store.state.snapshot.targetReached);
	CHECK(store.state.shouldShowPlatter); // main reached cannot hide unfinished 100%
	CHECK(store.state.snapshot.estimatesByTarget[@100].hasEstimate);
	CHECK(store.state.snapshot.estimatesByTarget[@100].remainingSeconds == 600);
	NSUInteger generation = store.state.estimateGeneration;
	[prefs setObject:JikanStackPropertyList(@[Main(), [JikanStackItem estimateWithTargetPercent:90]]) forKey:JikanStackItemsKey];
	[store reloadPreferences];
	CHECK(store.state.estimateGeneration > generation);
	CHECK(!store.state.snapshot.estimatesByTarget[@90].hasEstimate);
	CHECK(![store publishBatteryDictionary:Snapshot(Battery(80, YES), 80, results, @"jikan") generation:generation publisher:nil]);
	CHECK([store.state.settings.estimateTargets isEqual:@[@80, @90]]);
	CHECK([store.state.settings settingsByUpdatingPosition:(JikanPillPosition){0} landscape:NO].estimateTargets.count == 2);
	[prefs setObject:@YES forKey:@"showAfterFullCharge"];
	[store reloadPreferences];
	NSDictionary *complete = @{@"80": @{@"targetReached": @YES}, @"90": @{@"targetReached": @YES}};
	CHECK([store publishBatteryDictionary:Snapshot(Battery(90, YES), 80, complete, @"jikan") generation:store.state.estimateGeneration publisher:nil]);
	CHECK(store.state.shouldShowPlatter);
	[prefs setObject:@NO forKey:@"showAfterFullCharge"];
	[store reloadPreferences];
	CHECK(!store.state.shouldShowPlatter);
	// Completed milestones stay finished through battery fluctuations, until unplugging.
	NSDictionary *fluctuated = @{@"80": @{@"targetReached": @YES}, @"90": @{@"targetReached": @NO, @"hasEstimate": @YES, @"remainingSeconds": @60, @"timeString": @"1 min"}};
	CHECK([store publishBatteryDictionary:Snapshot(Battery(89, YES), 80, fluctuated, @"jikan") generation:store.state.estimateGeneration publisher:nil]);
	CHECK([store.state.snapshot.completedTargets containsObject:@90]);
	CHECK(!store.state.shouldShowPlatter);
	CHECK([store publishBatteryDictionary:Snapshot(Battery(50, NO), 80, @{}, @"jikan") generation:store.state.estimateGeneration publisher:nil]);
	CHECK(store.state.snapshot.completedTargets.count == 0);
	CHECK([store publishBatteryDictionary:Snapshot(Battery(80, YES), 80, results, @"jikan") generation:store.state.estimateGeneration publisher:nil]);
	CHECK(store.state.shouldShowPlatter); // pending extra still visible even without an estimate
	CHECK(![store.state.snapshot.completedTargets containsObject:@90]);
	// Main fields remain tied to the main target, even when an extra is completed.
	[prefs setObject:@100 forKey:@"batteryEstimateTargetPercent"];
	[prefs setObject:JikanStackPropertyList(@[Main(), [JikanStackItem estimateWithTargetPercent:80]]) forKey:JikanStackItemsKey];
	[store reloadPreferences];
	NSDictionary *mainPending = @{@"80": @{@"targetReached": @YES}, @"100": @{@"targetReached": @NO, @"hasEstimate": @YES, @"remainingSeconds": @1200, @"timeString": @"20 min"}};
	CHECK([store publishBatteryDictionary:Snapshot(Battery(80, YES), 100, mainPending, @"jikan") generation:store.state.estimateGeneration publisher:nil]);
	CHECK(!store.state.snapshot.targetReached);
	CHECK([store.state.snapshot.timeString isEqual:@"20 min"]);
	CHECK(store.state.snapshot.remainingSeconds == 1200);
	CHECK(store.state.settings.targetPercent == 100);
	// Unsupported extra Apple percentages stay configured and explicit.
	[prefs setObject:@"apple" forKey:JikanEstimateSourceKey];
	[prefs setObject:@YES forKey:JikanEstimateAppleEstimatedPowerKey];
	[prefs setObject:@80 forKey:JikanEstimateAppleTargetKey];
	[prefs setObject:JikanStackPropertyList(@[Main(), [JikanStackItem estimateWithTargetPercent:72]]) forKey:JikanStackItemsKey];
	[store reloadPreferences];
	CHECK([store.state.settings.estimateTargets containsObject:@72]);
	CHECK([store.state.snapshot.estimatesByTarget[@72].status isEqual:@"unsupported_target"]);
}

// The cache tests run the real Apple-estimator control flow with deterministic
// features/predictions. They do not validate Apple's model accuracy or USB power.
static NSDictionary *currentBattery;
static NSUInteger sampleReads;
static BOOL helperPowerAvailable = YES;
static NSUInteger historyReads;
static NSInteger missingPercent = -1;
static BOOL historyAvailable = YES;
@implementation TT100BatteryProvider
+ (NSDictionary *)fetchBatteryInfo { return currentBattery; }
+ (double)displaySOCWithBatteryInfo:(NSDictionary *)batteryInfo { return [batteryInfo[@"CurrentCapacity"] doubleValue]; }
+ (NSString *)chargerClassWithBatteryInfo:(NSDictionary *)batteryInfo outIsWireless:(BOOL *)wireless { return @"test"; }
@end
@implementation TT100InputPowerProvider
+ (NSDictionary *)readSample { sampleReads++; return @{@"status": helperPowerAvailable ? @"available" : @"input_power_smc_unavailable"}; }
+ (NSNumber *)milliwattsFromSample:(NSDictionary *)sample batteryInfo:(NSDictionary *)batteryInfo { return helperPowerAvailable ? @10000 : nil; }
@end
NSArray<NSNumber *> *JikanAppleFeaturesWithDiagnostics(NSDictionary *properties, NSInteger target, NSInteger startSOC, NSInteger elapsed, NSNumber *power, NSString **failure, NSArray<NSString *> **missing) {
	if (!properties[@"PowerTelemetryData"][@"SystemPowerIn"] && !power) { if (failure) *failure = @"missing_input_power"; return nil; }
	NSMutableArray *values = [NSMutableArray arrayWithObject:@(target)];
	while (values.count < (target == 80 ? 25 : 29)) [values addObject:@0];
	return values;
}
@implementation TT100Database
+ (instancetype)shared { static TT100Database *database; if (!database) database = [self new]; return database; }
- (BOOL)fetchPercentStatsForChargerClass:(NSString *)chargerClass intoEstimate:(double *)estimate uncertainty:(double *)uncertainty sampleCounts:(int *)counts lastUpdated:(double *)updated {
	historyReads++;
	for (NSInteger i = 0; i < 100; i++) { estimate[i] = 60; uncertainty[i] = 0; counts[i] = i == missingPercent ? 0 : 1; updated[i] = 0; }
	return historyAvailable;
}
@end
@implementation TT100LegacyHistory
+ (NSDictionary *)cachedHistoryBuckets { return @{}; }
@end
static void TestHistoryBatch(void) {
	historyReads = 0; missingPercent = -1;
	NSDictionary *battery = Battery(50, YES);
	NSDictionary *results = [TT100HistoryEstimator estimatedSecondsWithBatteryInfo:battery targets:@[@60, @80, @100]];
	CHECK(historyReads == 1);
	CHECK([results[@"60"] doubleValue] == 600);
	CHECK([results[@"80"] doubleValue] == 1800);
	CHECK([results[@"100"] doubleValue] == 3000);
	missingPercent = 70;
	results = [TT100HistoryEstimator estimatedSecondsWithBatteryInfo:battery targets:@[@60, @80]];
	CHECK([results[@"60"] doubleValue] == 600);
	CHECK(isnan([results[@"80"] doubleValue]));
	NSMutableDictionary *live = [battery mutableCopy]; live[@"DesignCapacity"] = @3000; live[@"InstantAmperage"] = @3000;
	results = [TT100HistoryEstimator estimatedSecondsWithBatteryInfo:live targets:@[@60, @80]];
	CHECK([results[@"80"] doubleValue] == 1776);
	results = [TT100HistoryEstimator estimatedSecondsWithBatteryInfo:battery targets:@[@0, @50, @101]];
	CHECK(isnan([results[@"0"] doubleValue]));
	CHECK(isnan([results[@"50"] doubleValue]));
	CHECK(isnan([results[@"101"] doubleValue]));
	missingPercent = -1;
}

@interface FakeModel : NSObject
@property NSMutableDictionary<NSNumber *, NSNumber *> *calls;
- (id<MLFeatureProvider>)predictionFromFeatures:(id<MLFeatureProvider>)features error:(NSError **)error;
@end
@implementation FakeModel
- (instancetype)init { if ((self = [super init])) _calls = [NSMutableDictionary dictionary]; return self; }
- (id<MLFeatureProvider>)predictionFromFeatures:(id<MLFeatureProvider>)features error:(NSError **)error {
	NSNumber *target = [features featureValueForName:@"input_1"].multiArrayValue[0];
	self.calls[target] = @([self.calls[target] integerValue] + 1);
	MLMultiArray *output = [[MLMultiArray alloc] initWithShape:@[@1] dataType:MLMultiArrayDataTypeDouble error:error];
	output[0] = @(target.doubleValue / 100);
	return [[MLDictionaryFeatureProvider alloc] initWithDictionary:@{@"tt80_prediction": output, @"ttl_prediction": output} error:error];
}
@end
@interface TestAppleEstimator : TT100AppleEstimator
@property FakeModel *model;
@end
@implementation TestAppleEstimator
- (MLModel *)_modelForTarget:(NSInteger)target failure:(NSString **)failure { return (MLModel *)self.model; }
@end
static void AgeSession(TT100AppleEstimator *estimator) {
	struct timespec time; clock_gettime(CLOCK_MONOTONIC_RAW, &time);
	[estimator setValue:@(time.tv_sec - 10) forKey:@"connectionTime"];
}
static void TestAppleCache(void) {
	TestAppleEstimator *estimator = [TestAppleEstimator new];
	estimator.model = [FakeModel new];
	currentBattery = Battery(50, YES);
	[estimator observeBatteryInfo:currentBattery]; AgeSession(estimator);
	NSArray *targets = @[@80, @90, @100];
	NSDictionary *first = [estimator resultsForBatteryInfo:currentBattery targets:targets allowEstimatedInputPower:NO][@"results"];
	CHECK(first.count == 3);
	CHECK([first[@"100"][@"measuredInputs"][@"powerSource"] isEqual:@"native"]);
	CHECK([first[@"80"][@"status"] isEqual:@"available"]);
	CHECK([first[@"80"][@"seconds"] doubleValue] != [first[@"90"][@"seconds"] doubleValue]);
	NSDictionary *cachedBatch = [estimator resultsForBatteryInfo:currentBattery targets:targets allowEstimatedInputPower:NO][@"results"];
	CHECK([cachedBatch[@"100"][@"measuredInputs"] isEqual:first[@"100"][@"measuredInputs"]]);
	for (NSNumber *target in targets) CHECK([estimator.model.calls[target] integerValue] == 1);
	NSDictionary *predictions = [estimator valueForKey:@"predictions"];
	id cached = predictions[@80];
	[cached setValue:@1 forKey:@"predictedAt"];
	[estimator resultsForBatteryInfo:currentBattery targets:targets allowEstimatedInputPower:NO];
	CHECK([estimator.model.calls[@80] integerValue] == 2);
	CHECK([estimator.model.calls[@90] integerValue] == 1);
	CHECK([estimator.model.calls[@100] integerValue] == 1);
	NSMutableDictionary *changed = [currentBattery mutableCopy]; changed[@"AdapterDetails"] = @{@"Watts": @30}; currentBattery = changed;
	[estimator resultsForBatteryInfo:currentBattery targets:targets allowEstimatedInputPower:NO];
	for (NSNumber *target in targets) CHECK([estimator.model.calls[target] integerValue] == (target.integerValue == 80 ? 3 : 2));
	changed = [currentBattery mutableCopy]; changed[@"IsCharging"] = @NO; currentBattery = changed;
	NSDictionary *paused = [estimator resultsForBatteryInfo:currentBattery targets:targets allowEstimatedInputPower:NO][@"results"];
	CHECK([paused[@"90"][@"status"] isEqual:@"paused"]);
	[estimator resultsForBatteryInfo:Battery(50, NO) targets:targets allowEstimatedInputPower:NO];
	currentBattery = Battery(50, YES); [estimator observeBatteryInfo:currentBattery]; AgeSession(estimator);
	[estimator resultsForBatteryInfo:currentBattery targets:targets allowEstimatedInputPower:NO];
	for (NSNumber *target in targets) CHECK([estimator.model.calls[target] integerValue] == (target.integerValue == 80 ? 4 : 3));
	// Every target in a refresh shares one helper sample and its revalidated battery state.
	changed = [currentBattery mutableCopy]; [changed removeObjectForKey:@"PowerTelemetryData"]; currentBattery = changed;
	sampleReads = 0;
	NSDictionary *helperBatch = [estimator resultsForBatteryInfo:currentBattery targets:targets allowEstimatedInputPower:NO][@"results"];
	CHECK([helperBatch[@"100"][@"measuredInputs"][@"powerSource"] isEqual:@"smc"]);
	CHECK(sampleReads == 1);
	NSDictionary *unsupported = [estimator resultsForBatteryInfo:currentBattery targets:@[@72, @90] allowEstimatedInputPower:NO][@"results"];
	CHECK([unsupported[@"72"][@"status"] isEqual:@"unsupported_target"]);
	// A new target's helper request can discover a charger change after an
	// earlier target has already returned its cached estimate in this refresh.
	TestAppleEstimator *consistent = [TestAppleEstimator new]; consistent.model = [FakeModel new];
	NSMutableDictionary *oldBattery = [Battery(50, YES) mutableCopy]; [oldBattery removeObjectForKey:@"PowerTelemetryData"];
	currentBattery = oldBattery;
	[consistent observeBatteryInfo:oldBattery]; AgeSession(consistent);
	[consistent resultsForBatteryInfo:oldBattery targets:@[@80] allowEstimatedInputPower:NO];
	NSMutableDictionary *newBattery = [oldBattery mutableCopy]; newBattery[@"AdapterDetails"] = @{@"Watts": @40}; currentBattery = newBattery;
	sampleReads = 0;
	NSDictionary *coherent = [consistent resultsForBatteryInfo:oldBattery targets:@[@80, @85] allowEstimatedInputPower:NO];
	CHECK(sampleReads == 1);
	CHECK([coherent[@"batteryInfo"][@"AdapterDetails"] isEqual:newBattery[@"AdapterDetails"]]);
	CHECK([consistent.model.calls[@80] integerValue] == 2);
	CHECK([consistent.model.calls[@85] integerValue] == 1);

	TestAppleEstimator *approximate = [TestAppleEstimator new]; approximate.model = [FakeModel new];
	helperPowerAvailable = NO;
	[approximate observeBatteryInfo:currentBattery]; AgeSession(approximate);
	NSDictionary *approximateResult = [approximate resultForBatteryInfo:currentBattery target:100 allowEstimatedInputPower:YES];
	CHECK([approximateResult[@"inputPowerSource"] isEqual:@"adapter_estimate"]);
	CHECK([approximateResult[@"measuredInputs"][@"status"] isEqual:@"missing_input_power"]);
	NSDictionary *cachedApproximation = [approximate resultForBatteryInfo:currentBattery target:100 allowEstimatedInputPower:YES];
	CHECK([cachedApproximation[@"measuredInputs"] isEqual:approximateResult[@"measuredInputs"]]);
	helperPowerAvailable = YES;

}
int main(void) { @autoreleasepool {
	TestSettingsAndSelection(); TestPresentation(); TestAppleCache(); TestHistoryBatch();
	printf("Passed %lu Stack settings, selection, snapshot, and estimator-cache checks.\n", (unsigned long)checks);
} return 0; }

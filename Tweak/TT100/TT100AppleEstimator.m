#import "TT100AppleEstimator.h"
#import "../../Shared/JikanInputPowerEligibility.h"

static NSString *const JikanModelRevision = @"iOS260";

static double JikanMonotonicSeconds(void) {
	struct timespec time;
	if (clock_gettime(CLOCK_MONOTONIC_RAW, &time) != 0) return NAN;
	return (double)time.tv_sec + (double)time.tv_nsec / 1e9;
}

static NSNumber *JikanFeatureNumber(NSDictionary *dictionary, NSString *key) {
	id value = [dictionary isKindOfClass:NSDictionary.class] ? dictionary[key] : nil;
	if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) return nil;
	return value;
}

static NSString *JikanSHA256(NSString *path) {
	NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
	if (!handle) return nil;
	CC_SHA256_CTX context;
	CC_SHA256_Init(&context);
	@try {
		while (YES) {
			NSData *chunk = [handle readDataOfLength:65536];
			if (!chunk.length) break;
			CC_SHA256_Update(&context, chunk.bytes, (CC_LONG)chunk.length);
		}
	}
	@catch (__unused NSException *exception) {
		[handle closeFile];
		return nil;
	}
	[handle closeFile];
	unsigned char digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(digest, &context);
	NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
	for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
	return hex;
}

@interface TT100ApplePrediction : NSObject
@property (nonatomic) double predictedAt;
@property (nonatomic) double predictedSeconds;
@property (nonatomic, copy) NSString *inputPowerSource;
@property (nonatomic, copy) NSDictionary *predictionAdapter;
@end
@implementation TT100ApplePrediction
@end

@interface TT100AppleEstimator ()
@property (nonatomic, strong) MLModel *tt80Model;
@property (nonatomic, strong) MLModel *ttlModel;
@property (nonatomic, assign) BOOL sawDisconnected;
@property (nonatomic, assign) BOOL wasConnected;
@property (nonatomic, assign) BOOL sessionValid;
@property (nonatomic, assign) BOOL sessionStartEstimated;
@property (nonatomic, assign) NSInteger startSOC;
@property (nonatomic, assign) NSInteger sessionNumber;
@property (nonatomic, assign) double connectionTime;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, TT100ApplePrediction *> *predictions;
@property (nonatomic, copy) NSDictionary *batchBatteryInfo;
@property (nonatomic, copy) NSDictionary *batchInputSample;
@property (nonatomic, copy) NSString *lastFailure;
@end

@implementation TT100AppleEstimator

- (void)reset {
	self.sawDisconnected = NO;
	self.wasConnected = NO;
	self.sessionValid = NO;
	self.sessionStartEstimated = NO;
	self.connectionTime = 0;
	[self.predictions removeAllObjects];
	self.sessionNumber++;
}

- (NSDictionary *)_unavailable:(NSString *)status {
	return @{@"status": status ?: @"unavailable", @"revision": JikanModelRevision, @"session": @(self.sessionNumber), @"sessionStartEstimated": @(self.sessionStartEstimated), @"inputPowerSource": @"unavailable"};
}

- (void)observeBatteryInfo:(NSDictionary *)batteryInfo {
	NSNumber *connected = JikanFeatureNumber(batteryInfo, @"ExternalConnected");
	NSNumber *soc = JikanFeatureNumber(batteryInfo, @"CurrentCapacity");
	if (!connected) return;
	if (!connected.boolValue) {
		if (self.wasConnected || self.sessionValid) [self reset];
		self.sawDisconnected = YES;
		return;
	}
	NSNumber *charging = JikanFeatureNumber(batteryInfo, @"IsCharging");
	if (charging && !charging.boolValue) [self.predictions removeAllObjects];
	if (self.sessionValid) return;
	if (!self.wasConnected) {
		self.wasConnected = YES;
		[self.predictions removeAllObjects];
		self.sessionNumber++;
	}
	double now = JikanMonotonicSeconds();
	if (soc && soc.doubleValue >= 0 && soc.doubleValue <= 100 && isfinite(now)) {
		self.sessionStartEstimated = !self.sawDisconnected;
		self.startSOC = (NSInteger)soc.doubleValue;
		self.connectionTime = floor(now);
		self.sessionValid = YES;
	}
}

- (MLModel *)_modelForTarget:(NSInteger)target failure:(NSString **)failure {
	MLModel *loaded = target == 80 ? self.tt80Model : self.ttlModel;
	if (loaded) return loaded;
	NSString *root = jbroot([@"/Library/Tweak Support/Jikan/Models/" stringByAppendingString:JikanModelRevision]);
	NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfFile:[root stringByAppendingPathComponent:@"Manifest.plist"]];
	NSString *kind = target == 80 ? @"tt80" : @"ttl";
	NSDictionary *checksums = [manifest[@"SHA256"] isKindOfClass:NSDictionary.class] ? manifest[@"SHA256"] : nil;
	if (![manifest[@"Revision"] isEqualToString:JikanModelRevision] || ![manifest[@"FeatureSchema"] isEqual:@1] ||
		![manifest[@"TT80ModelID"] isEqualToString:@"bkwqiw7f79"] || ![manifest[@"TTLModelID"] isEqualToString:@"k5wmzvi5mm"] || !checksums) {
		if (failure) *failure = @"missing_model_manifest";
		return nil;
	}
	NSString *path = [root stringByAppendingPathComponent:[kind stringByAppendingString:@".mlmodelc"]];
	for (NSString *name in @[@"model.espresso.net", @"model.espresso.weights"]) {
		NSString *key = [NSString stringWithFormat:@"%@/%@", kind, name];
		NSString *expected = checksums[key];
		NSString *actual = JikanSHA256([path stringByAppendingPathComponent:name]);
		if (![expected isKindOfClass:NSString.class] || ![actual isEqualToString:expected]) {
			if (failure) *failure = @"model_checksum_mismatch";
			return nil;
		}
	}
	MLModelConfiguration *configuration = [MLModelConfiguration new];
	configuration.computeUnits = MLComputeUnitsCPUOnly;
	NSError *error = nil;
	loaded = [MLModel modelWithContentsOfURL:[NSURL fileURLWithPath:path isDirectory:YES] configuration:configuration error:&error];
	if (!loaded) {
		if (failure) *failure = @"model_load_failed";
		return nil;
	}
	MLFeatureDescription *input = loaded.modelDescription.inputDescriptionsByName[@"input_1"];
	NSString *outputName = target == 80 ? @"tt80_prediction" : @"ttl_prediction";
	MLFeatureDescription *output = loaded.modelDescription.outputDescriptionsByName[outputName];
	if (input.type != MLFeatureTypeMultiArray || output.type != MLFeatureTypeMultiArray ||
		![input.multiArrayConstraint.shape isEqual:@[@1, @(target == 80 ? 25 : 29)]] ||
		input.multiArrayConstraint.dataType != MLMultiArrayDataTypeFloat32) {
		if (failure) *failure = @"model_schema_mismatch";
		return nil;
	}
	if (target == 80) self.tt80Model = loaded;
	else
		self.ttlModel = loaded;
	return loaded;
}

- (NSDictionary *)resultForBatteryInfo:(NSDictionary *)batteryInfo target:(NSInteger)target allowEstimatedInputPower:(BOOL)allowEstimatedInputPower {
	return [self resultsForBatteryInfo:batteryInfo targets:@[@(target)] allowEstimatedInputPower:allowEstimatedInputPower][@"results"][@(target).stringValue];
}

- (NSDictionary *)resultsForBatteryInfo:(NSDictionary *)batteryInfo targets:(NSArray<NSNumber *> *)targets allowEstimatedInputPower:(BOOL)allowEstimatedInputPower {
	[self observeBatteryInfo:batteryInfo];
	if (!self.predictions) self.predictions = [NSMutableDictionary dictionary];
	NSSet *active = [NSSet setWithArray:targets];
	for (NSNumber *target in self.predictions.allKeys) if (![active containsObject:target]) [self.predictions removeObjectForKey:target];
	self.batchBatteryInfo = batteryInfo;
	self.batchInputSample = nil;
	NSMutableDictionary *results = [NSMutableDictionary dictionary];
	for (NSUInteger pass = 0; pass < 2; pass++) {
		for (NSNumber *target in targets) {
			if (!self.predictions[target]) self.predictions[target] = [TT100ApplePrediction new];
			results[target.stringValue] = [self _resultForBatteryInfo:self.batchBatteryInfo target:target.integerValue allowEstimatedInputPower:allowEstimatedInputPower];
		}
		// Helper IPC can discover a new adapter or power state. Re-evaluate any
		// earlier cached results against that same refreshed state, reusing the
		// one helper sample. Native-only refreshes need just the first pass.
		if (!self.batchInputSample) break;
	}
	NSDictionary *batch = @{@"results": [results copy], @"batteryInfo": self.batchBatteryInfo ?: @{}};
	self.batchInputSample = nil;
	self.batchBatteryInfo = nil;
	return batch;
}

- (NSDictionary *)_resultForBatteryInfo:(NSDictionary *)batteryInfo target:(NSInteger)target allowEstimatedInputPower:(BOOL)allowEstimatedInputPower {
	NSNumber *connected = JikanFeatureNumber(batteryInfo, @"ExternalConnected");
	NSNumber *soc = JikanFeatureNumber(batteryInfo, @"CurrentCapacity");
	double now = JikanMonotonicSeconds();
	TT100ApplePrediction *cachedPrediction = self.predictions[@(target)];
	if (!connected || !soc || !isfinite(now)) return [self _unavailable:@"missing_power_state"];
	if (!connected.boolValue) return [self _unavailable:@"disconnected"];
	if (!self.sessionValid) return [self _unavailable:@"unknown_connection_time"];
	if (!JikanAppleTargetIsSupported(target)) return [self _unavailable:@"unsupported_target"];
	if (soc.doubleValue >= target || [JikanFeatureNumber(batteryInfo, @"FullyCharged") boolValue]) {
		cachedPrediction.predictedAt = 0;
		return [self _unavailable:@"target_reached"];
	}
	if (now - self.connectionTime < 4.0) return [self _unavailable:@"waiting_for_first_prediction"];
	NSNumber *charging = JikanFeatureNumber(batteryInfo, @"IsCharging");
	if (!charging || !charging.boolValue) {
		cachedPrediction.predictedAt = 0;
		return [self _unavailable:@"paused"];
	}
	NSDictionary *telemetry = batteryInfo[@"PowerTelemetryData"];
	BOOL nativePowerPresent = [telemetry isKindOfClass:NSDictionary.class] && telemetry[@"SystemPowerIn"] != nil;
	if (cachedPrediction.predictedAt > 0 && (![cachedPrediction.predictionAdapter isEqual:batteryInfo[@"AdapterDetails"]] || ([cachedPrediction.inputPowerSource isEqual:@"smc"] && nativePowerPresent) || ([cachedPrediction.inputPowerSource isEqual:@"native"] && !nativePowerPresent) || ([cachedPrediction.inputPowerSource isEqual:@"adapter_estimate"] && (!allowEstimatedInputPower || nativePowerPresent)))) cachedPrediction.predictedAt = 0;
	if (cachedPrediction.predictedAt > 0 && now - cachedPrediction.predictedAt < 300.0) {
		double remaining = cachedPrediction.predictedSeconds - (now - cachedPrediction.predictedAt);
		if (isfinite(remaining) && remaining > 0) return @{@"status": @"available", @"seconds": @(remaining), @"revision": JikanModelRevision, @"session": @(self.sessionNumber), @"sessionStartEstimated": @(self.sessionStartEstimated), @"inputPowerSource": cachedPrediction.inputPowerSource ?: @"native"};
		cachedPrediction.predictedAt = 0;
	}
	NSString *failure = nil;
	NSArray<NSString *> *missingFeatures = nil;
	NSArray<NSNumber *> *features = JikanAppleFeaturesWithDiagnostics(batteryInfo, target, self.startSOC, (NSInteger)floor(now) - (NSInteger)self.connectionTime, nil, &failure, &missingFeatures);
	NSString *inputPowerSource = @"native";
	if (!features && [failure isEqualToString:@"missing_input_power"]) {
		if (!JikanCanMeasureWiredInputPower(batteryInfo) && !allowEstimatedInputPower) return [self _unavailable:@"input_power_unsupported_path"];
	}
	if (!features && [failure isEqualToString:@"missing_input_power"] && JikanCanMeasureWiredInputPower(batteryInfo)) {
		if (!self.batchInputSample) {
			self.batchInputSample = [TT100InputPowerProvider readSample];
			self.batchBatteryInfo = [TT100BatteryProvider fetchBatteryInfo];
			[self observeBatteryInfo:self.batchBatteryInfo];
		}
		NSDictionary *sample = self.batchInputSample;
		batteryInfo = self.batchBatteryInfo;
		if (!JikanFeatureNumber(batteryInfo, @"ExternalConnected") || !JikanFeatureNumber(batteryInfo, @"IsCharging")) return [self _unavailable:@"missing_power_state"];
		if (![batteryInfo[@"ExternalConnected"] boolValue]) return [self _unavailable:@"disconnected"];
		if ([JikanFeatureNumber(batteryInfo, @"CurrentCapacity") doubleValue] >= target || [batteryInfo[@"FullyCharged"] boolValue]) return [self _unavailable:@"target_reached"];
		if (![batteryInfo[@"IsCharging"] boolValue]) return [self _unavailable:@"paused"];
		now = JikanMonotonicSeconds();
		if (!self.sessionValid || !isfinite(now)) return [self _unavailable:@"unknown_connection_time"];
		NSInteger elapsed = (NSInteger)floor(now) - (NSInteger)self.connectionTime;
		// Native telemetry may have appeared while IPC was in flight.
		features = JikanAppleFeaturesWithDiagnostics(batteryInfo, target, self.startSOC, elapsed, nil, &failure, &missingFeatures);
		if (!features && [failure isEqualToString:@"missing_input_power"]) {
			NSNumber *inputPower = [TT100InputPowerProvider milliwattsFromSample:sample batteryInfo:batteryInfo];
			if (!inputPower) {
				if (!allowEstimatedInputPower) return [self _unavailable:[sample[@"status"] isEqual:@"available"] ? @"input_power_state_changed" : sample[@"status"]];
			} else {
				features = JikanAppleFeaturesWithDiagnostics(batteryInfo, target, self.startSOC, elapsed, inputPower, &failure, &missingFeatures);
				inputPowerSource = @"smc";
			}
		}
	}
	if (!features && [failure isEqualToString:@"missing_input_power"] && allowEstimatedInputPower) {
		// AdapterDetails describes the charger's capability, never actual USB draw.
		// Only an explicit user opt-in permits this unmeasured model input.
		NSNumber *estimatedInputPower = JikanEstimatedAdapterInputMilliwatts(batteryInfo);
		if (estimatedInputPower) {
			features = JikanAppleFeaturesWithDiagnostics(batteryInfo, target, self.startSOC, (NSInteger)floor(now) - (NSInteger)self.connectionTime, estimatedInputPower, &failure, &missingFeatures);
			if (features) inputPowerSource = @"adapter_estimate";
		}
	}
	if (!features) {
		NSMutableDictionary *unavailable = [[self _unavailable:failure] mutableCopy];
		if (missingFeatures.count) unavailable[@"missingFeatures"] = missingFeatures;
		return unavailable;
	}
	MLModel *model = [self _modelForTarget:target failure:&failure];
	if (!model) return [self _unavailable:failure];
	NSError *error = nil;
	MLMultiArray *input = [[MLMultiArray alloc] initWithShape:@[@1, @(features.count)] dataType:MLMultiArrayDataTypeFloat32 error:&error];
	if (!input) return [self _unavailable:@"input_allocation_failed"];
	for (NSUInteger i = 0; i < features.count; i++) input[i] = features[i];
	MLDictionaryFeatureProvider *provider = [[MLDictionaryFeatureProvider alloc] initWithDictionary:@{@"input_1": [MLFeatureValue featureValueWithMultiArray:input]} error:&error];
	if (!provider) return [self _unavailable:@"input_provider_failed"];
	id<MLFeatureProvider> prediction = [model predictionFromFeatures:provider error:&error];
	NSString *outputName = target == 80 ? @"tt80_prediction" : @"ttl_prediction";
	MLMultiArray *output = [prediction featureValueForName:outputName].multiArrayValue;
	if (output.count != 1) return [self _unavailable:@"prediction_failed"];
	double hours = [output[0] doubleValue];
	double seconds = hours * 3600.0 + (target == 80 ? 0.0 : 300.0);
	if (!isfinite(seconds) || seconds <= 0 || seconds > INT_MAX) return [self _unavailable:@"invalid_prediction"];
	cachedPrediction.predictedAt = JikanMonotonicSeconds();
	cachedPrediction.predictedSeconds = seconds;
	cachedPrediction.inputPowerSource = inputPowerSource;
	cachedPrediction.predictionAdapter = batteryInfo[@"AdapterDetails"];
	return @{@"status": @"available", @"seconds": @(seconds), @"revision": JikanModelRevision, @"session": @(self.sessionNumber), @"sessionStartEstimated": @(self.sessionStartEstimated), @"inputPowerSource": inputPowerSource};
}

@end

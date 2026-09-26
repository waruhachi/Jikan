#import <CommonCrypto/CommonDigest.h>
#import <CoreML/CoreML.h>
#import <math.h>
#import <roothide.h>
#import <time.h>

#import "../../Shared/JikanAppleFeatures.h"
#import "../../Shared/JikanEstimateSettings.h"
#import "TT100AppleEstimator.h"

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

@interface TT100AppleEstimator ()
@property (nonatomic, strong) MLModel *tt80Model;
@property (nonatomic, strong) MLModel *ttlModel;
@property (nonatomic, assign) BOOL sawDisconnected;
@property (nonatomic, assign) BOOL wasConnected;
@property (nonatomic, assign) BOOL sessionValid;
@property (nonatomic, assign) NSInteger startSOC;
@property (nonatomic, assign) NSInteger sessionNumber;
@property (nonatomic, assign) double connectionTime;
@property (nonatomic, assign) double predictedAt;
@property (nonatomic, assign) double predictedSeconds;
@property (nonatomic, assign) NSInteger predictedTarget;
@property (nonatomic, copy) NSString *lastFailure;
@end

@implementation TT100AppleEstimator

- (void)reset {
	self.sawDisconnected = NO;
	self.wasConnected = NO;
	self.sessionValid = NO;
	self.connectionTime = 0;
	self.predictedAt = 0;
	self.predictedSeconds = 0;
	self.predictedTarget = 0;
	self.sessionNumber++;
}

- (NSDictionary *)_unavailable:(NSString *)status {
	return @{@"status": status ?: @"unavailable", @"revision": JikanModelRevision, @"session": @(self.sessionNumber)};
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
	if (self.wasConnected) return;
	self.wasConnected = YES;
	self.predictedAt = 0;
	self.sessionNumber++;
	double now = JikanMonotonicSeconds();
	if (self.sawDisconnected && soc && soc.doubleValue >= 0 && soc.doubleValue <= 100 && isfinite(now)) {
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

- (NSDictionary *)resultForBatteryInfo:(NSDictionary *)batteryInfo target:(NSInteger)target {
	NSNumber *connected = JikanFeatureNumber(batteryInfo, @"ExternalConnected");
	NSNumber *soc = JikanFeatureNumber(batteryInfo, @"CurrentCapacity");
	double now = JikanMonotonicSeconds();
	[self observeBatteryInfo:batteryInfo];
	if (!connected || !soc || !isfinite(now)) return [self _unavailable:@"missing_power_state"];
	if (!connected.boolValue) return [self _unavailable:@"disconnected"];
	if (!self.sessionValid) return [self _unavailable:@"unknown_connection_time"];
	if (!JikanAppleTargetIsSupported(target)) return [self _unavailable:@"unsupported_target"];
	if (soc.doubleValue >= target || [JikanFeatureNumber(batteryInfo, @"FullyCharged") boolValue]) {
		self.predictedAt = 0;
		return [self _unavailable:@"target_reached"];
	}
	if (now - self.connectionTime < 4.0) return [self _unavailable:@"waiting_for_first_prediction"];
	NSNumber *charging = JikanFeatureNumber(batteryInfo, @"IsCharging");
	if (!charging || !charging.boolValue) {
		self.predictedAt = 0;
		return [self _unavailable:@"paused"];
	}
	if (self.predictedTarget != target) self.predictedAt = 0;
	if (self.predictedAt > 0 && now - self.predictedAt < 300.0) {
		double remaining = self.predictedSeconds - (now - self.predictedAt);
		if (isfinite(remaining) && remaining > 0) return @{@"status": @"available", @"seconds": @(remaining), @"revision": JikanModelRevision, @"session": @(self.sessionNumber)};
		self.predictedAt = 0;
	}
	NSString *failure = nil;
	NSArray<NSNumber *> *features = JikanAppleFeatures(batteryInfo, target, self.startSOC, (NSInteger)floor(now) - (NSInteger)self.connectionTime, &failure);
	if (!features) return [self _unavailable:failure];
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
	self.predictedAt = JikanMonotonicSeconds();
	self.predictedSeconds = seconds;
	self.predictedTarget = target;
	return @{@"status": @"available", @"seconds": @(seconds), @"revision": JikanModelRevision, @"session": @(self.sessionNumber)};
}

@end

#import "JikanPresentationStore.h"

NSString *const JikanPresentationStateDidChangeNotification = @"JikanPresentationStateDidChange";
NSString *const TT100BatteryInfoUpdatedNotification = @"TT100BatteryInfoUpdated";
NSString *const TT100InternalDidRefreshBatteryInfoNotification = @"TT100InternalDidRefreshBatteryInfo";
NSString *const JikanChargingStateChangedNotification = @"JikanChargingStateChanged";

@interface JikanPresentationStore ()
@property (nonatomic, strong) NSUserDefaults *preferences;
@end

@implementation JikanPresentationStore

@synthesize state = _state;

+ (instancetype)sharedInstance {
	static JikanPresentationStore *store;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ store = [[self alloc] initWithPreferences:[[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite]]; });
	return store;
}

- (instancetype)initWithPreferences:(NSUserDefaults *)preferences {
	NSAssert([NSThread isMainThread], @"Presentation state must be owned by the main thread");
	self = [super init];
	if (self) {
		_preferences = preferences;
		_state = [[JikanPresentationState alloc] initWithSnapshot:nil settings:[[JikanPresentationSettings alloc] initWithPreferences:preferences] previewActive:NO estimateGeneration:0];
	}
	return self;
}

- (JikanPresentationState *)state {
	NSAssert([NSThread isMainThread], @"Presentation state must be read on the main thread");
	return _state;
}

- (void)notifyStateChanged {
	[[NSNotificationCenter defaultCenter] postNotificationName:JikanPresentationStateDidChangeNotification object:self userInfo:@{@"state": _state}];
}

- (void)notifyChargingStateChanged {
	[[NSNotificationCenter defaultCenter] postNotificationName:JikanChargingStateChangedNotification object:nil userInfo:@{@"isCharging": @(_state.snapshot.externalPowerConnected)}];
}

- (void)reloadPreferences {
	NSAssert([NSThread isMainThread], @"Presentation settings must change on the main thread");
	JikanPresentationSettings *settings = [[JikanPresentationSettings alloc] initWithPreferences:_preferences];
	BOOL estimateChanged = ![settings.estimateSource isEqualToString:_state.settings.estimateSource] || settings.targetPercent != _state.settings.targetPercent;
	NSUInteger generation = _state.estimateGeneration + (estimateChanged || settings.enabled != _state.settings.enabled);
	JikanBatterySnapshot *snapshot = settings.enabled ? _state.snapshot : nil;
	if (estimateChanged) snapshot = [snapshot snapshotWithoutEstimateForSettings:settings];
	_state = [[JikanPresentationState alloc] initWithSnapshot:snapshot settings:settings previewActive:_state.previewActive estimateGeneration:generation];
	[self notifyChargingStateChanged];
	[self notifyStateChanged];
}

- (BOOL)publishBatteryDictionary:(NSDictionary *)dictionary generation:(NSUInteger)generation publisher:(id)publisher {
	NSAssert([NSThread isMainThread], @"Battery state must be published on the main thread");
	if (!_state.settings.enabled || generation != _state.estimateGeneration) return NO;
	if (![dictionary isKindOfClass:NSDictionary.class] || ![dictionary[@"estimateSource"] isEqual:_state.settings.estimateSource]) return NO;
	id target = dictionary[@"targetPercent"];
	if (![target isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)target) == CFBooleanGetTypeID() || !isfinite([target doubleValue]) || [target doubleValue] != _state.settings.targetPercent) return NO;
	JikanBatterySnapshot *snapshot = [[JikanBatterySnapshot alloc] initWithDictionary:dictionary settings:_state.settings];
	BOOL wasConnected = _state.snapshot.externalPowerConnected;
	_state = [[JikanPresentationState alloc] initWithSnapshot:snapshot settings:_state.settings previewActive:_state.previewActive estimateGeneration:generation];
	[[NSNotificationCenter defaultCenter] postNotificationName:TT100InternalDidRefreshBatteryInfoNotification object:publisher userInfo:snapshot.dictionary];
	if (_state.snapshot != snapshot || !_state.settings.enabled || generation != _state.estimateGeneration) return YES;
	if (wasConnected != snapshot.externalPowerConnected) [self notifyChargingStateChanged];
	[self notifyStateChanged];
	if (_state.snapshot == snapshot && _state.settings.enabled && generation == _state.estimateGeneration) {
		[[NSNotificationCenter defaultCenter] postNotificationName:TT100BatteryInfoUpdatedNotification object:publisher userInfo:snapshot.dictionary];
	}
	return YES;
}

- (void)clearBatterySnapshot {
	NSAssert([NSThread isMainThread], @"Battery state must change on the main thread");
	_state = [[JikanPresentationState alloc] initWithSnapshot:nil settings:_state.settings previewActive:_state.previewActive estimateGeneration:_state.estimateGeneration + 1];
	[self notifyStateChanged];
}

- (void)setPreviewActive:(BOOL)active {
	NSAssert([NSThread isMainThread], @"Preview state must change on the main thread");
	active = active && _state.settings.enabled;
	if (_state.previewActive == active) return;
	_state = [[JikanPresentationState alloc] initWithSnapshot:_state.snapshot settings:_state.settings previewActive:active estimateGeneration:_state.estimateGeneration];
	[self notifyChargingStateChanged];
	[self notifyStateChanged];
}

- (void)updatePosition:(JikanPillPosition)position landscape:(BOOL)landscape {
	NSAssert([NSThread isMainThread], @"Pill positions must change on the main thread");
	JikanPresentationSettings *settings = [_state.settings settingsByUpdatingPosition:position landscape:landscape];
	_state = [[JikanPresentationState alloc] initWithSnapshot:_state.snapshot settings:settings previewActive:_state.previewActive estimateGeneration:_state.estimateGeneration];
}

@end

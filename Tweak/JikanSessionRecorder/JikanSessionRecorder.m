#import "JikanSessionRecorder.h"

@interface JikanSessionRecorder () {
	dispatch_queue_t _queue;
	NSInteger _sessionID;
	NSInteger _lastSOC;
	NSTimeInterval _lastSOCMonotonicTime;
	NSMutableDictionary<NSNumber *, NSMutableArray<NSNumber *> *> *_durations;
	NSString *_chargerClass;
	NSString *_chargerIdentity;
	BOOL _isWireless;
}
@end

static NSTimeInterval TT100MonotonicSeconds(void) {
	struct timespec time;
	if (clock_gettime(CLOCK_MONOTONIC_RAW, &time) != 0) return NAN;
	return (double)time.tv_sec + (double)time.tv_nsec / 1e9;
}

@implementation JikanSessionRecorder

- (instancetype)init {
	if ((self = [super init])) {
		_queue = dispatch_queue_create("com.tt100.recorder", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
		_sessionID = -1;
		_lastSOC = -1;
		_lastSOCMonotonicTime = NAN;
	}
	return self;
}

- (void)consumeSnapshot:(NSDictionary *)snapshot charging:(BOOL)charging {
	if (![snapshot[@"batteryInfo"] count]) return;
	snapshot = [snapshot copy];
	NSTimeInterval monotonicTime = TT100MonotonicSeconds();
	NSTimeInterval timestamp = CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970;
	dispatch_async(_queue, ^{
		@autoreleasepool {
			[self _consumeSnapshot:snapshot charging:charging monotonicTime:monotonicTime timestamp:timestamp];
		}
	});
}

- (void)finishWithBatteryInfo:(NSDictionary *)batteryInfo {
	batteryInfo = [batteryInfo copy];
	NSTimeInterval timestamp = CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970;
	dispatch_async(_queue, ^{
		@autoreleasepool {
			[self _finishWithBatteryInfo:batteryInfo timestamp:timestamp];
		}
	});
}

- (void)_consumeSnapshot:(NSDictionary *)snapshot charging:(BOOL)charging monotonicTime:(NSTimeInterval)monotonicTime timestamp:(NSTimeInterval)timestamp {
	NSDictionary *batteryInfo = snapshot[@"batteryInfo"];
	if (!batteryInfo.count) return;
	if (charging) {
		NSString *chargerIdentity = snapshot[@"chargerIdentity"];
		if (_sessionID >= 0 && ![_chargerIdentity isEqualToString:chargerIdentity]) [self _finishWithBatteryInfo:batteryInfo timestamp:timestamp];
		[self _startWithBatteryInfo:batteryInfo monotonicTime:monotonicTime timestamp:timestamp];
		BOOL paused = [batteryInfo[@"IsCharging"] respondsToSelector:@selector(boolValue)] && ![batteryInfo[@"IsCharging"] boolValue];
		if (paused) {
			_lastSOC = [snapshot[@"displayPercent"] integerValue];
			_lastSOCMonotonicTime = monotonicTime;
		} else
			[self _recordTicksWithBatteryInfo:batteryInfo monotonicTime:monotonicTime timestamp:timestamp];
	} else {
		[self _finishWithBatteryInfo:batteryInfo timestamp:timestamp];
	}
}

- (void)_startWithBatteryInfo:(NSDictionary *)batteryInfo monotonicTime:(NSTimeInterval)monotonicTime timestamp:(NSTimeInterval)timestamp {
	if (_sessionID >= 0) return;
	NSNumber *pctMax = batteryInfo[@"MaxCapacity"];
	NSNumber *pctCurr = batteryInfo[@"CurrentCapacity"];
	if (!pctMax || !pctCurr) return;
	if (pctMax.intValue <= 0) return;
	NSInteger soc = (NSInteger)lrint((pctCurr.doubleValue / pctMax.doubleValue) * 100.0);
	_sessionID = [[TT100Database shared] beginSessionWithStartSOC:soc timestamp:timestamp];
	if (_sessionID >= 0) {
		BOOL isWireless = NO;
		NSString *chargerClass = [TT100 chargerClassWithBatteryInfo:batteryInfo outIsWireless:&isWireless];
		if (!chargerClass.length) chargerClass = @"unknown";
		_chargerClass = [chargerClass copy];
		_chargerIdentity = [[TT100 chargerIdentityWithBatteryInfo:batteryInfo] copy];
		_isWireless = isWireless;
		[[TT100Database shared] updateSession:_sessionID chargerClass:_chargerClass isWireless:_isWireless];
	}
	_lastSOC = soc;
	_lastSOCMonotonicTime = monotonicTime;
	if (!_durations) _durations = [NSMutableDictionary new];
}

- (void)_finishWithBatteryInfo:(NSDictionary *)batteryInfo timestamp:(NSTimeInterval)timestamp {
	if (_sessionID < 0) return;
	NSNumber *pctMax = batteryInfo[@"MaxCapacity"];
	NSNumber *pctCurr = batteryInfo[@"CurrentCapacity"];
	NSInteger soc = _lastSOC;
	if (pctMax && pctCurr && pctMax.intValue > 0) soc = (NSInteger)lrint((pctCurr.doubleValue / pctMax.doubleValue) * 100.0);
	[[TT100Database shared] endSessionId:_sessionID endSOC:MAX(0, MIN(100, soc)) timestamp:timestamp];

	if (_durations.count) {
		NSString *cls = _chargerClass.length ? _chargerClass : @"unknown";
		[[TT100Database shared] updatePercentStatsForChargerClass:cls withDurationsSec:_durations];
	}
	_durations = [NSMutableDictionary new];
	_sessionID = -1;
	_lastSOC = -1;
	_lastSOCMonotonicTime = NAN;
	_chargerClass = nil;
	_chargerIdentity = nil;
	_isWireless = NO;
}

- (void)_recordTicksWithBatteryInfo:(NSDictionary *)batteryInfo monotonicTime:(NSTimeInterval)monotonicTime timestamp:(NSTimeInterval)timestamp {
	if (_sessionID < 0) return;
	NSNumber *pctMax = batteryInfo[@"MaxCapacity"];
	NSNumber *pctCurr = batteryInfo[@"CurrentCapacity"];
	if (!pctMax || !pctCurr || pctMax.intValue <= 0) return;
	NSInteger soc = (NSInteger)lrint((pctCurr.doubleValue / pctMax.doubleValue) * 100.0);
	NSTimeInterval now = monotonicTime;
	NSTimeInterval delta = now - _lastSOCMonotonicTime;
	if (_lastSOC < 0 || soc < _lastSOC || !isfinite(now) ||
		!isfinite(_lastSOCMonotonicTime) || !isfinite(delta) || delta <= 0) {
		_lastSOC = soc;
		_lastSOCMonotonicTime = now;
		return;
	}
	if (soc == _lastSOC) return;
	NSInteger steps = soc - _lastSOC;
	for (NSInteger step = 1; step <= steps; step++) {
		NSInteger reached = _lastSOC + step;
		double slice = delta / (double)steps;
		NSTimeInterval tickTs = timestamp - (delta - slice * step);
		[[TT100Database shared] insertTickForSession:_sessionID
												 soc:reached
												  ts:tickTs
										batteryTempC:NAN
							  instantaneousCurrentmA:[batteryInfo[@"Amperage"] integerValue]
											screenOn:YES
											 cpuLoad:NAN
										thermalLevel:0];
		NSInteger prior = reached - 1;
		if (prior >= 0 && prior < 100) {
			NSMutableArray *arr = _durations[@(prior)];
			if (!arr) {
				arr = [NSMutableArray new];
				_durations[@(prior)] = arr;
			}
			[arr addObject:@(slice)];
		}
	}
	if (_durations.count) {
		[[TT100Database shared] updatePercentStatsForChargerClass:_chargerClass ?: @"unknown" withDurationsSec:_durations];
		[_durations removeAllObjects];
	}
	_lastSOC = soc;
	_lastSOCMonotonicTime = now;
}

@end

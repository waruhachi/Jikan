#import "JikanSessionRecorder.h"

@interface JikanSessionRecorder () {
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
		_sessionID = -1;
		_lastSOC = -1;
		_lastSOCMonotonicTime = NAN;
	}
	return self;
}

- (void)consumeSnapshot:(NSDictionary *)snapshot charging:(BOOL)charging {
	NSDictionary *batteryInfo = snapshot[@"batteryInfo"];
	if (!batteryInfo.count) return;
	if (charging) {
		NSString *chargerIdentity = snapshot[@"chargerIdentity"];
		if (_sessionID >= 0 && ![_chargerIdentity isEqualToString:chargerIdentity]) [self finishWithBatteryInfo:batteryInfo];
		[self _startWithBatteryInfo:batteryInfo];
		BOOL paused = [batteryInfo[@"IsCharging"] respondsToSelector:@selector(boolValue)] && ![batteryInfo[@"IsCharging"] boolValue];
		if (paused) {
			_lastSOC = [snapshot[@"displayPercent"] integerValue];
			_lastSOCMonotonicTime = TT100MonotonicSeconds();
		} else
			[self _recordTicksWithBatteryInfo:batteryInfo];
	} else {
		[self finishWithBatteryInfo:batteryInfo];
	}
}

- (void)_startWithBatteryInfo:(NSDictionary *)batteryInfo {
	if (_sessionID >= 0) return;
	NSNumber *pctMax = batteryInfo[@"MaxCapacity"];
	NSNumber *pctCurr = batteryInfo[@"CurrentCapacity"];
	if (!pctMax || !pctCurr) return;
	if (pctMax.intValue <= 0) return;
	NSInteger soc = (NSInteger)lrint((pctCurr.doubleValue / pctMax.doubleValue) * 100.0);
	_sessionID = [[TT100Database shared] beginSessionWithStartSOC:soc];
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
	_lastSOCMonotonicTime = TT100MonotonicSeconds();
	if (!_durations) _durations = [NSMutableDictionary new];
}

- (void)finishWithBatteryInfo:(NSDictionary *)batteryInfo {
	if (_sessionID < 0) return;
	NSNumber *pctMax = batteryInfo[@"MaxCapacity"];
	NSNumber *pctCurr = batteryInfo[@"CurrentCapacity"];
	NSInteger soc = _lastSOC;
	if (pctMax && pctCurr && pctMax.intValue > 0) soc = (NSInteger)lrint((pctCurr.doubleValue / pctMax.doubleValue) * 100.0);
	[[TT100Database shared] endSessionId:_sessionID endSOC:MAX(0, MIN(100, soc))];

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

- (void)_recordTicksWithBatteryInfo:(NSDictionary *)batteryInfo {
	if (_sessionID < 0) return;
	NSNumber *pctMax = batteryInfo[@"MaxCapacity"];
	NSNumber *pctCurr = batteryInfo[@"CurrentCapacity"];
	if (!pctMax || !pctCurr || pctMax.intValue <= 0) return;
	NSInteger soc = (NSInteger)lrint((pctCurr.doubleValue / pctMax.doubleValue) * 100.0);
	NSTimeInterval now = TT100MonotonicSeconds();
	NSTimeInterval delta = now - _lastSOCMonotonicTime;
	if (_lastSOC < 0 || soc < _lastSOC || !isfinite(now) ||
		!isfinite(_lastSOCMonotonicTime) || !isfinite(delta) || delta <= 0) {
		_lastSOC = soc;
		_lastSOCMonotonicTime = now;
		return;
	}
	if (soc == _lastSOC) return;
	const NSTimeInterval nowEpoch = CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970;
	NSInteger steps = soc - _lastSOC;
	for (NSInteger step = 1; step <= steps; step++) {
		NSInteger reached = _lastSOC + step;
		double slice = delta / (double)steps;
		NSTimeInterval tickTs = nowEpoch - (delta - slice * step);
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

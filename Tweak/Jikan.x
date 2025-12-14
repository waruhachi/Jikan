#import "Jikan.h"

BOOL isCharging = NO;
static NSInteger _tt100CurrentSessionId = -1;
static NSInteger _tt100LastSOC = -1;
static CFAbsoluteTime _tt100LastSOCTime = 0;
static NSMutableDictionary<NSNumber *, NSMutableArray<NSNumber *> *> *_tt100Durations;
static NSString *_tt100CurrentChargerClass = nil;
static BOOL _tt100CurrentIsWireless = NO;

static _UIAnimatingLabel *TTFindAnimatingLabel(UIView *view) {
	for (UIView *subview in view.subviews) {
		if ([subview isKindOfClass:NSClassFromString(@"_UIAnimatingLabel")]) {
			return (_UIAnimatingLabel *)subview;
		}
	}
	return nil;
}

static void TT100SessionMaybeStart(NSDictionary *batteryInfo) {
	if (_tt100CurrentSessionId >= 0) return;
	NSNumber *pctMax = batteryInfo[@"MaxCapacity"];
	NSNumber *pctCurr = batteryInfo[@"CurrentCapacity"];
	if (!pctMax || !pctCurr) return;
	if (pctMax.intValue <= 0) return;
	NSInteger soc = (NSInteger)lrint((pctCurr.doubleValue / pctMax.doubleValue) * 100.0);
	_tt100CurrentSessionId = [[TT100Database shared] beginSessionWithStartSOC:soc];
	if (_tt100CurrentSessionId >= 0) {
		BOOL isWireless = NO;
		NSString *chargerClass = [TT100 chargerClassWithBatteryInfo:batteryInfo outIsWireless:&isWireless];
		if (!chargerClass.length) chargerClass = @"unknown";
		_tt100CurrentChargerClass = [chargerClass copy];
		_tt100CurrentIsWireless = isWireless;
		[[TT100Database shared] updateSession:_tt100CurrentSessionId chargerClass:_tt100CurrentChargerClass isWireless:_tt100CurrentIsWireless];
	}
	_tt100LastSOC = soc;
	_tt100LastSOCTime = CFAbsoluteTimeGetCurrent();
	if (!_tt100Durations) _tt100Durations = [NSMutableDictionary new];
}

static void TT100SessionMaybeEnd(NSDictionary *batteryInfo) {
	if (_tt100CurrentSessionId < 0) return;
	NSNumber *pctMax = batteryInfo[@"MaxCapacity"];
	NSNumber *pctCurr = batteryInfo[@"CurrentCapacity"];
	if (pctMax && pctCurr && pctMax.intValue > 0) {
		NSInteger soc = (NSInteger)lrint((pctCurr.doubleValue / pctMax.doubleValue) * 100.0);
		[[TT100Database shared] endSessionId:_tt100CurrentSessionId endSOC:soc];
	}

	if (_tt100Durations.count) {
		NSString *cls = _tt100CurrentChargerClass.length ? _tt100CurrentChargerClass : @"unknown";
		[[TT100Database shared] updatePercentStatsForChargerClass:cls withDurationsSec:_tt100Durations];
	}
	_tt100Durations = [NSMutableDictionary new];
	_tt100CurrentSessionId = -1;
	_tt100LastSOC = -1;
	_tt100LastSOCTime = 0;
	_tt100CurrentChargerClass = nil;
	_tt100CurrentIsWireless = NO;
}

static void TT100RecordTicksIfNeeded(NSDictionary *batteryInfo) {
	if (_tt100CurrentSessionId < 0) return;
	NSNumber *pctMax = batteryInfo[@"MaxCapacity"];
	NSNumber *pctCurr = batteryInfo[@"CurrentCapacity"];
	if (!pctMax || !pctCurr || pctMax.intValue <= 0) return;
	NSInteger soc = (NSInteger)lrint((pctCurr.doubleValue / pctMax.doubleValue) * 100.0);
	if (_tt100LastSOC < 0) {
		_tt100LastSOC = soc;
		_tt100LastSOCTime = CFAbsoluteTimeGetCurrent();
		return;
	}
	if (soc <= _tt100LastSOC) return;
	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	CFAbsoluteTime delta = now - _tt100LastSOCTime;
	if (delta <= 0) delta = 1;
	const NSTimeInterval nowEpoch = now + kCFAbsoluteTimeIntervalSince1970;
	NSInteger steps = soc - _tt100LastSOC;
	for (NSInteger step = 1; step <= steps; step++) {
		NSInteger reached = _tt100LastSOC + step;
		double slice = delta / (double)steps;
		NSTimeInterval tickTs = nowEpoch - (delta - slice * step);
		[[TT100Database shared] insertTickForSession:_tt100CurrentSessionId
												 soc:reached
												  ts:tickTs
										batteryTempC:NAN
							  instantaneousCurrentmA:[batteryInfo[@"Amperage"] integerValue]
											screenOn:YES
											 cpuLoad:NAN
										thermalLevel:0];
		NSInteger prior = reached - 1;
		if (prior >= 0 && prior < 100) {
			NSMutableArray *arr = _tt100Durations[@(prior)];
			if (!arr) {
				arr = [NSMutableArray new];
				_tt100Durations[@(prior)] = arr;
			}
			[arr addObject:@(slice)];
		}
	}
}

%hook NCNotificationListCountIndicatorView

- (void)didMoveToWindow {
	self.hidden = YES;
	%orig;
}

%end

%hook _UIBatteryView
- (void)setChargingState:(NSInteger)arg1 {
	BOOL wasCharging = isCharging;
	isCharging = (arg1 == 1);
	if (wasCharging != isCharging) {
		NSDictionary *batteryInfo = [TT100 fetchBatteryInfo];
		if (isCharging) {
			TT100SessionMaybeStart(batteryInfo);
		} else {
			TT100SessionMaybeEnd(batteryInfo);
		}
		[[NSNotificationCenter defaultCenter] postNotificationName:JikanChargingStateChangedNotification object:nil userInfo:@{@"isCharging": @(isCharging)}];
	}
	return %orig;
}

%end

%hook CSQuickActionsView

- (void)refreshSupportedButtons {
	%orig;

	if (!hideQuickActionButtons) return;

	self.cameraButton.hidden = YES;
	self.flashlightButton.hidden = YES;
}

%end

%hook CSCoverSheetView
%property(nonatomic, strong) JikanPlatterView *remainingTimePlatter;

- (void)layoutSubviews {
	%orig;

	[self _addOrRemoveRemainingTimePlatterIfNecessary];
	[self _configureRemainingTimePlatterConstraints];
}

%new
- (void)_addOrRemoveRemainingTimePlatterIfNecessary {
	if (!self.remainingTimePlatter) {
		self.remainingTimePlatter = [[JikanPlatterView alloc] init];
		self.remainingTimePlatter.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:self.remainingTimePlatter];
	}

	BOOL shouldShow = isCharging;
	if (shouldShow) {
		[[TT100 sharedInstance] _refreshBatteryInfo];
	}

	[self _setRemainingTimePlatterVisible:shouldShow];
}

%new
- (void)_setRemainingTimePlatterVisible:(BOOL)visible {
	if (!self.remainingTimePlatter) return;

	BOOL currentlyVisible = !self.remainingTimePlatter.hidden;
	if (visible == currentlyVisible) return;

	NSTimeInterval duration = 0.25;
	UIViewAnimationOptions options = UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState;

	if (visible) {
		self.remainingTimePlatter.alpha = 0.0;
		self.remainingTimePlatter.hidden = NO;
		[UIView animateWithDuration:duration delay:0 options:options animations:^{
			self.remainingTimePlatter.alpha = 1.0;
		} completion:nil];
	} else {
		[UIView animateWithDuration:duration delay:0 options:options animations:^{
			self.remainingTimePlatter.alpha = 0.0;
		} completion:^(BOOL finished) {
			self.remainingTimePlatter.hidden = YES;
		}];
	}
}

%new
- (void)_configureRemainingTimePlatterConstraints {
	if (!self.remainingTimePlatter) return;

	UIView *superview = self.remainingTimePlatter.superview;
	if (superview) {
		NSMutableArray *constraintsToRemove = [NSMutableArray array];
		for (NSLayoutConstraint *constraint in superview.constraints) {
			if (constraint.firstItem == self.remainingTimePlatter || constraint.secondItem == self.remainingTimePlatter) {
				[constraintsToRemove addObject:constraint];
			}
		}
		[superview removeConstraints:constraintsToRemove];
	}

	[self.remainingTimePlatter removeConstraints:self.remainingTimePlatter.constraints];

	static const CGFloat platterHeight = 60.0;	// same as Quick Actions height ig
	CGFloat platterWidth = self.bounds.size.width * 0.45;
	CGFloat platterCenterY = self.bounds.size.height * 0.91;  // shit value, set to the nearest value of the QA height, coudnt find a better way to position it dynamically
	[NSLayoutConstraint activateConstraints:@[
		[self.remainingTimePlatter.widthAnchor constraintEqualToConstant:platterWidth],
		[self.remainingTimePlatter.heightAnchor constraintEqualToConstant:platterHeight],
		[self.remainingTimePlatter.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
		[self.remainingTimePlatter.centerYAnchor constraintEqualToAnchor:self.topAnchor constant:platterCenterY],
	]];

	[self.remainingTimePlatter setupConstraints];
}

%end

%hook CSProminentSubtitleDateView

- (void)didMoveToWindow {
	%orig;

	for (UIView *subview in self.subviews) {
		if (![subview isKindOfClass:NSClassFromString(@"_UIAnimatingLabel")]) continue;

		_UIAnimatingLabel *label = (_UIAnimatingLabel *)subview;

		objc_setAssociatedObject(label, kTTManagedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		label.numberOfLines = 1;
		label.adjustsFontSizeToFitWidth = NO;

		NSString *current = label.text ?: @"";
		NSRange sep = [current rangeOfString:@" • " options:NSBackwardsSearch];
		NSString *baseText = (sep.location != NSNotFound) ? [current substringToIndex:sep.location] : current;
		objc_setAssociatedObject(label, kTTBaseTextKey, baseText, OBJC_ASSOCIATION_COPY_NONATOMIC);

		if (isCharging || !showRemainingBatteryTime) {
			[[NSNotificationCenter defaultCenter] removeObserver:label name:@"TT100BatteryInfoUpdated" object:nil];
			label.text = baseText;
			continue;
		}

		[[NSNotificationCenter defaultCenter] removeObserver:label name:@"TT100BatteryInfoUpdated" object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:label selector:@selector(_updateBatteryTime:) name:@"TT100BatteryInfoUpdated" object:nil];

		[label _updateBatteryTime:nil];
	}

	[self setNeedsLayout];
}

- (void)layoutSubviews {
	%orig;

	CGRect bounds = self.bounds;

	for (UIView *subview in self.subviews) {
		if (![subview isKindOfClass:NSClassFromString(@"_UIAnimatingLabel")]) continue;

		_UIAnimatingLabel *label = (_UIAnimatingLabel *)subview;
		NSNumber *managed = objc_getAssociatedObject(label, kTTManagedKey);
		if (!managed.boolValue) continue;

		CGRect f = label.frame;

		f.origin.x = 0.0;
		f.size.width = bounds.size.width;

		label.frame = f;
	}
}

- (void)_updateLabel {
	%orig;

	if (isCharging || !showRemainingBatteryTime) return;

	_UIAnimatingLabel *label = TTFindAnimatingLabel(self);
	if (!label) return;

	NSString *current = label.text ?: @"";
	NSRange sep = [current rangeOfString:@" • " options:NSBackwardsSearch];
	NSString *baseText = (sep.location != NSNotFound) ? [current substringToIndex:sep.location] : current;

	objc_setAssociatedObject(label, kTTManagedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(label, kTTBaseTextKey, baseText, OBJC_ASSOCIATION_COPY_NONATOMIC);

	[[NSNotificationCenter defaultCenter] removeObserver:label name:@"TT100BatteryInfoUpdated" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:label selector:@selector(_updateBatteryTime:) name:@"TT100BatteryInfoUpdated" object:nil];

	[label _updateBatteryTime:nil];
}

- (void)setDate:(id)date {
	%orig;

	if (isCharging || !showRemainingBatteryTime) return;

	_UIAnimatingLabel *label = TTFindAnimatingLabel(self);
	if (label) {
		[label _updateBatteryTime:nil];
	}
}

%end

%hook _UIAnimatingLabel

%new
- (void)_updateBatteryTime:(NSNotification *)notification {
	NSString *storedBase = objc_getAssociatedObject(self, kTTBaseTextKey);
	if (!storedBase) return;

	if (isCharging || !showRemainingBatteryTime) {
		self.text = storedBase;
		[[NSNotificationCenter defaultCenter] removeObserver:self name:@"TT100BatteryInfoUpdated" object:nil];
		return;
	}

	NSDictionary *batteryInfo = [TT100 fetchBatteryInfo];
	id avgObj = batteryInfo[@"AvgTimeToEmpty"];
	id remObj = batteryInfo[@"TimeRemaining"];

	NSInteger minutes = 0;

	if ([avgObj isKindOfClass:[NSNumber class]]) minutes = [(NSNumber *)avgObj integerValue];
	else if ([avgObj isKindOfClass:[NSString class]])
		minutes = [(NSString *)avgObj integerValue];

	if (minutes <= 0) {
		if ([remObj isKindOfClass:[NSNumber class]]) minutes = [(NSNumber *)remObj integerValue];
		else if ([remObj isKindOfClass:[NSString class]])
			minutes = [(NSString *)remObj integerValue];
	}

	if (minutes <= 0 || minutes > 48 * 60) {
		NSString *baseText = objc_getAssociatedObject(self, kTTBaseTextKey);
		if (baseText) self.text = baseText;
		return;
	}

	NSInteger hours = minutes / 60;
	NSInteger mins = minutes % 60;

	NSString *timeString = nil;

	if (hours > 0) {
		if (mins == 0) {
			timeString = [NSString stringWithFormat:@"%ldh left", (long)hours];
		} else {
			timeString = [NSString stringWithFormat:@"%ldh %02ldm left", (long)hours, (long)mins];
		}
	} else {
		if (mins == 0) {
			NSString *baseText = objc_getAssociatedObject(self, kTTBaseTextKey);
			if (baseText) self.text = baseText;
			return;
		}
		timeString = [NSString stringWithFormat:@"%ldm left", (long)mins];
	}

	NSString *current = self.text ?: @"";
	NSRange sep = [current rangeOfString:@" • " options:NSBackwardsSearch];
	NSString *currentBase = (sep.location != NSNotFound) ? [current substringToIndex:sep.location] : current;

	if (currentBase.length > 0 && ![currentBase isEqualToString:storedBase]) {
		storedBase = currentBase;
		objc_setAssociatedObject(self, kTTBaseTextKey, storedBase, OBJC_ASSOCIATION_COPY_NONATOMIC);
	}

	self.adjustsFontSizeToFitWidth = NO;
	self.text = (storedBase.length > 0)
		? [NSString stringWithFormat:@"%@ • %@", storedBase, timeString]
		: timeString;
}

%end

%ctor {
	NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:@"moe.waru.jikan.preferences"];

	enabled = [preferences objectForKey:@"enabled"] ? [preferences boolForKey:@"enabled"] : YES;
	hideQuickActionButtons = [preferences objectForKey:@"hideQuickActionButtons"] ? [preferences boolForKey:@"hideQuickActionButtons"] : NO;
	showRemainingBatteryTime = [preferences objectForKey:@"showRemainingBatteryTime"] ? [preferences boolForKey:@"showRemainingBatteryTime"] : NO;

	if (!enabled) {
		return;
	}

	[TT100 startMonitoring];
	[[NSNotificationCenter defaultCenter] addObserverForName:TT100InternalDidRefreshBatteryInfoNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
		NSDictionary *bi = note.userInfo[@"batteryInfo"];
		if (isCharging && bi) TT100RecordTicksIfNeeded(bi);
	}];
}

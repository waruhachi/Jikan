#import "Jikan.h"

BOOL isCharging = NO;
static NSString *const kJikanPrefsSuite = @"moe.waru.jikan.preferences";
static NSString *const kJikanPrefsReloadNotification = @"moe.waru.jikan.preferences.reload";
static NSInteger _tt100CurrentSessionId = -1;
static NSInteger _tt100LastSOC = -1;
static CFAbsoluteTime _tt100LastSOCTime = 0;
static NSMutableDictionary<NSNumber *, NSMutableArray<NSNumber *> *> *_tt100Durations;
static NSString *_tt100CurrentChargerClass = nil;
static BOOL _tt100CurrentIsWireless = NO;
static const void *kTTPlatterWidthConstraintKey = &kTTPlatterWidthConstraintKey;
static const void *kTTPlatterHeightConstraintKey = &kTTPlatterHeightConstraintKey;
static const void *kTTPlatterCenterXConstraintKey = &kTTPlatterCenterXConstraintKey;
static const void *kTTPlatterBottomConstraintKey = &kTTPlatterBottomConstraintKey;
static const void *kTTPlatterConstraintsInstalledKey = &kTTPlatterConstraintsInstalledKey;
static const void *kTTPlatterStyleCapturedKey = &kTTPlatterStyleCapturedKey;
static const void *kTTPlatterAlignmentLoggedKey = &kTTPlatterAlignmentLoggedKey;
static const void *kTTCoverSheetObserverInstalledKey = &kTTCoverSheetObserverInstalledKey;
static const void *kTTCoverSheetBootstrapTimerKey = &kTTCoverSheetBootstrapTimerKey;
static const void *kTTCoverSheetBootstrapStartTimeKey = &kTTCoverSheetBootstrapStartTimeKey;
static BOOL _ttDidLogQuickActionHierarchy = NO;
static BOOL _ttLastResolvedChargingValid = NO;
static BOOL _ttAllowSBUIControllerFallback = NO;

static void TTLoadPreferences(void) {
	NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	enabled = [preferences objectForKey:@"enabled"] ? [preferences boolForKey:@"enabled"] : YES;
	hideQuickActionButtons = [preferences objectForKey:@"hideQuickActionButtons"] ? [preferences boolForKey:@"hideQuickActionButtons"] : NO;
	showRemainingBatteryTime = [preferences objectForKey:@"showRemainingBatteryTime"] ? [preferences boolForKey:@"showRemainingBatteryTime"] : NO;
	autoResizeRemainingBatteryTime = [preferences objectForKey:@"autoResizeRemainingBatteryTime"] ? [preferences boolForKey:@"autoResizeRemainingBatteryTime"] : NO;
	tapToShowWattage = [preferences objectForKey:@"tapToShowWattage"] ? [preferences boolForKey:@"tapToShowWattage"] : NO;
	platterYOffset = [preferences objectForKey:@"platterYOffset"] ? [preferences doubleForKey:@"platterYOffset"] : 0.0;
}

static void TTPrefsDidChange(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
#pragma unused(center, observer, name, object, userInfo)
	dispatch_async(dispatch_get_main_queue(), ^{
		TTLoadPreferences();
		[[NSNotificationCenter defaultCenter] postNotificationName:JikanChargingStateChangedNotification object:nil userInfo:@{@"isCharging": @(isCharging)}];
		[[TT100 sharedInstance] _refreshBatteryInfo];
	});
}

static NSLayoutConstraint *TTGetConstraint(UIView *view, const void *key) {
	return (NSLayoutConstraint *)objc_getAssociatedObject(view, key);
}

static void TTSetConstraint(UIView *view, const void *key, NSLayoutConstraint *constraint) {
	objc_setAssociatedObject(view, key, constraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL TTConstraintsInstalled(UIView *view) {
	return [objc_getAssociatedObject(view, kTTPlatterConstraintsInstalledKey) boolValue];
}

static void TTSetConstraintsInstalled(UIView *view, BOOL installed) {
	objc_setAssociatedObject(view, kTTPlatterConstraintsInstalledKey, @(installed), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL TTPlatterStyleCaptured(UIView *view) {
	return [objc_getAssociatedObject(view, kTTPlatterStyleCapturedKey) boolValue];
}

static void TTSetPlatterStyleCaptured(UIView *view, BOOL captured) {
	objc_setAssociatedObject(view, kTTPlatterStyleCapturedKey, @(captured), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL TTPlatterAlignmentLogged(UIView *view) {
	return [objc_getAssociatedObject(view, kTTPlatterAlignmentLoggedKey) boolValue];
}

static void TTSetPlatterAlignmentLogged(UIView *view, BOOL logged) {
	objc_setAssociatedObject(view, kTTPlatterAlignmentLoggedKey, @(logged), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSString *TTColorDescription(UIColor *color) {
	if (!color) return @"nil";
	CGFloat r = 0, g = 0, b = 0, a = 0;
	if ([color getRed:&r green:&g blue:&b alpha:&a]) {
		return [NSString stringWithFormat:@"rgba(%.3f,%.3f,%.3f,%.3f)", r, g, b, a];
	}
	return color.description;
}

static void TTLogVisualTree(UIView *view, NSInteger depth, NSInteger maxDepth) {
	if (!view || depth > maxDepth) return;
	NSMutableString *indent = [NSMutableString string];
	for (NSInteger i = 0; i < depth; i++) [indent appendString:@"  "];
	CALayer *layer = view.layer;
	NSLog(@"[Jikan][Tree] %@%@ frame=%@ alpha=%.3f hidden=%d clips=%d bg=%@ tint=%@ cr=%.2f curve=%ld border=%.2f shadow(op=%.2f r=%.2f) compositing=%@ filters=%@",
		indent,
		NSStringFromClass(view.class),
		NSStringFromCGRect(view.frame),
		view.alpha,
		view.hidden,
		view.clipsToBounds,
		TTColorDescription(view.backgroundColor),
		TTColorDescription(view.tintColor),
		layer.cornerRadius,
		(long)layer.cornerCurve,
		layer.borderWidth,
		layer.shadowOpacity,
		layer.shadowRadius,
		layer.compositingFilter,
		layer.filters);

	if ([view isKindOfClass:[UIVisualEffectView class]]) {
		UIVisualEffectView *ev = (UIVisualEffectView *)view;
		NSLog(@"[Jikan][Tree] %@  effect=%@", indent, NSStringFromClass([ev.effect class]));
	}

	for (UIView *subview in view.subviews) {
		TTLogVisualTree(subview, depth + 1, maxDepth);
	}
}

static void TTLogQuickActionAndPlatterTreesOnce(CSCoverSheetView *coverSheet, UIView *styleSource) {
	if (_ttDidLogQuickActionHierarchy) return;
	if (!coverSheet || !styleSource || !coverSheet.remainingTimePlatter) return;
	_ttDidLogQuickActionHierarchy = YES;
	NSLog(@"[Jikan] ---- QuickAction source hierarchy ----");
	TTLogVisualTree(styleSource, 0, 5);
	NSLog(@"[Jikan] ---- Platter hierarchy ----");
	TTLogVisualTree(coverSheet.remainingTimePlatter, 0, 5);
}

static CSQuickActionsView *TTFindQuickActionsView(UIView *root) {
	if (!root) return nil;
	Class quickActionsClass = NSClassFromString(@"CSQuickActionsView");
	if (!quickActionsClass) return nil;

	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
	while (stack.count) {
		UIView *view = stack.lastObject;
		[stack removeLastObject];
		if ([view isKindOfClass:quickActionsClass]) {
			return (CSQuickActionsView *)view;
		}
		for (UIView *sub in view.subviews) {
			[stack addObject:sub];
		}
	}
	return nil;
}

static BOOL TTQuickActionButtonFramesInView(CSCoverSheetView *coverSheet, CGRect *flashRectOut, CGRect *cameraRectOut) {
	CSQuickActionsView *quickActions = TTFindQuickActionsView(coverSheet);
	if (!quickActions.flashlightButton || !quickActions.cameraButton) return NO;

	UIView *flashSuper = quickActions.flashlightButton.superview ?: quickActions;
	UIView *cameraSuper = quickActions.cameraButton.superview ?: quickActions;
	CGRect flashRect = [flashSuper convertRect:quickActions.flashlightButton.frame toView:coverSheet];
	CGRect cameraRect = [cameraSuper convertRect:quickActions.cameraButton.frame toView:coverSheet];

	if (CGRectIsEmpty(flashRect) || CGRectIsEmpty(cameraRect)) return NO;
	if (flashRectOut) *flashRectOut = flashRect;
	if (cameraRectOut) *cameraRectOut = cameraRect;
	return YES;
}

static UIView *TTFindNearestQuickActionMaterialView(UIView *root) {
	if (!root) return nil;
	CSQuickActionsView *quickActions = TTFindQuickActionsView(root);
	if (!quickActions) return nil;
	NSArray<UIView *> *candidates = @[];
	if (quickActions.flashlightButton && quickActions.cameraButton) {
		candidates = @[quickActions.flashlightButton, quickActions.cameraButton];
	}
	for (UIView *button in candidates) {
		if (!button) continue;
		NSMutableArray<UIView *> *buttonStack = [NSMutableArray arrayWithObject:button];
		while (buttonStack.count) {
			UIView *v = buttonStack.lastObject;
			[buttonStack removeLastObject];
			if ([v isKindOfClass:[UIVisualEffectView class]]) return v;
			if ([NSStringFromClass(v.class) containsString:@"MTMaterial"]) return v;
			for (UIView *sub in v.subviews) {
				[buttonStack addObject:sub];
			}
		}
	}
	return nil;
}

static void TTApplyQuickActionStyleIfPossible(CSCoverSheetView *coverSheet) {
	if (!coverSheet.remainingTimePlatter) return;
	CSQuickActionsView *quickActions = TTFindQuickActionsView(coverSheet);
	CSQuickActionsButton *referenceButton = quickActions.flashlightButton ?: quickActions.cameraButton;

	UIView *sourceMaterialView = TTFindNearestQuickActionMaterialView(coverSheet);
	if (!sourceMaterialView) return;

	if ([sourceMaterialView isKindOfClass:[UIVisualEffectView class]]) {
		UIVisualEffectView *sourceEffect = (UIVisualEffectView *)sourceMaterialView;
		[coverSheet.remainingTimePlatter applyQuickActionVisualEffect:sourceEffect.effect];
		UIView *styleSource = sourceMaterialView.superview ?: (referenceButton ?: sourceMaterialView);
		[coverSheet.remainingTimePlatter applyQuickActionBackgroundStyleFromView:styleSource];
		TTLogQuickActionAndPlatterTreesOnce(coverSheet, styleSource);
		if (!TTPlatterStyleCaptured(coverSheet)) {
			TTSetPlatterStyleCaptured(coverSheet, YES);
			NSLog(@"[Jikan] Captured QA visual effect: class=%@ alpha=%.3f cornerRadius=%.2f", NSStringFromClass(sourceMaterialView.class), sourceMaterialView.alpha, sourceMaterialView.layer.cornerRadius);
		}
		return;
	}

	[coverSheet.remainingTimePlatter applyQuickActionBackgroundStyleFromView:(referenceButton ?: sourceMaterialView)];
	if (!TTPlatterStyleCaptured(coverSheet)) {
		TTSetPlatterStyleCaptured(coverSheet, YES);
		NSLog(@"[Jikan] QA material view is not UIVisualEffectView: %@ alpha=%.3f cornerRadius=%.2f", NSStringFromClass(sourceMaterialView.class), sourceMaterialView.alpha, sourceMaterialView.layer.cornerRadius);
	}
}

static _UIAnimatingLabel *TTFindAnimatingLabel(UIView *view) {
	for (UIView *subview in view.subviews) {
		if ([subview isKindOfClass:NSClassFromString(@"_UIAnimatingLabel")]) {
			return (_UIAnimatingLabel *)subview;
		}
	}
	return nil;
}

static NSString *TTStripBatterySuffix(NSString *text) {
	NSString *value = text ?: @"";
	NSRange sep = [value rangeOfString:@" • " options:NSBackwardsSearch];
	return (sep.location != NSNotFound) ? [value substringToIndex:sep.location] : value;
}

static NSString *TTRemainingTimeSuffix(void) {
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

	if (minutes <= 0 || minutes > 48 * 60) return nil;

	NSInteger hours = minutes / 60;
	NSInteger mins = minutes % 60;
	if (hours > 0) {
		if (mins == 0) return [NSString stringWithFormat:@"%ldh left", (long)hours];
		return [NSString stringWithFormat:@"%ldh %02ldm left", (long)hours, (long)mins];
	}
	if (mins == 0) return nil;
	return [NSString stringWithFormat:@"%ldm left", (long)mins];
}

static NSString *TTBuildSubtitleWithRemainingTime(NSString *text) {
	NSString *base = TTStripBatterySuffix(text);
	if (isCharging || !showRemainingBatteryTime) return base;

	NSString *suffix = TTRemainingTimeSuffix();
	if (!suffix.length) return base;
	return base.length ? [NSString stringWithFormat:@"%@ • %@", base, suffix] : suffix;
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

static BOOL TTReadIsOnACFromSBUIController(BOOL *outHasValue) {
	if (outHasValue) *outHasValue = NO;
	@try {
		Class cls = NSClassFromString(@"SBUIController");
		if (!cls || ![cls respondsToSelector:@selector(sharedInstance)]) return NO;
		id controller = [cls sharedInstance];
		if (!controller || ![controller respondsToSelector:@selector(isOnAC)]) return NO;
		if (outHasValue) *outHasValue = YES;
		return ((BOOL(*)(id, SEL))objc_msgSend)(controller, @selector(isOnAC));
	} @catch (__unused NSException *exception) {
		return NO;
	}
}

static BOOL TTInferChargingStateFromBatteryInfo(NSDictionary *batteryInfo) {
	if (![batteryInfo isKindOfClass:[NSDictionary class]]) return NO;

	id external = batteryInfo[@"ExternalConnected"];
	if ([external respondsToSelector:@selector(boolValue)] && [external boolValue]) {
		return YES;
	}

	id charging = batteryInfo[@"IsCharging"];
	if ([charging respondsToSelector:@selector(boolValue)]) {
		return [charging boolValue];
	}

	id fullyCharged = batteryInfo[@"FullyCharged"];
	if ([fullyCharged respondsToSelector:@selector(boolValue)] && [fullyCharged boolValue]) {
		return YES;
	}

	NSDictionary *adapter = [batteryInfo[@"AdapterDetails"] isKindOfClass:[NSDictionary class]] ? batteryInfo[@"AdapterDetails"] : nil;
	if (adapter.count > 0) {
		id current = adapter[@"Current"];
		if ([current respondsToSelector:@selector(doubleValue)] && fabs([current doubleValue]) > 0.0) {
			return YES;
		}
		id voltage = adapter[@"Voltage"];
		if ([voltage respondsToSelector:@selector(doubleValue)] && fabs([voltage doubleValue]) > 0.0) {
			return YES;
		}
	}

	return NO;
}

static BOOL TTResolveChargingState(void) {
	BOOL hasAC = NO;
	if (_ttAllowSBUIControllerFallback) {
		BOOL onAC = TTReadIsOnACFromSBUIController(&hasAC);
		if (hasAC) {
			_ttLastResolvedChargingValid = YES;
			return onAC;
		}
	}

	NSDictionary *batteryInfo = [TT100 fetchBatteryInfo];
	if (batteryInfo.count > 0) {
		BOOL inferred = TTInferChargingStateFromBatteryInfo(batteryInfo);
		_ttLastResolvedChargingValid = YES;
		return inferred;
	}

	if (_ttLastResolvedChargingValid) return isCharging;
	return NO;
}

static void TTSyncChargingStateFromBatteryInfoAndNotify(BOOL shouldNotify) {
	NSDictionary *batteryInfo = [TT100 fetchBatteryInfo];
	BOOL newCharging = TTResolveChargingState();
	BOOL changed = (newCharging != isCharging);
	isCharging = newCharging;

	if (isCharging) {
		TT100SessionMaybeStart(batteryInfo);
	} else if (changed) {
		TT100SessionMaybeEnd(batteryInfo);
	}

	if (shouldNotify) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] postNotificationName:JikanChargingStateChangedNotification object:nil userInfo:@{@"isCharging": @(isCharging)}];
		});
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
	_ttLastResolvedChargingValid = YES;
	if (wasCharging != isCharging) {
		NSDictionary *batteryInfo = [TT100 fetchBatteryInfo];
		if (isCharging) {
			TT100SessionMaybeStart(batteryInfo);
		} else {
			TT100SessionMaybeEnd(batteryInfo);
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] postNotificationName:JikanChargingStateChangedNotification object:nil userInfo:@{@"isCharging": @(isCharging)}];
		});
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

- (void)didMoveToWindow {
	%orig;

	BOOL installed = [objc_getAssociatedObject(self, kTTCoverSheetObserverInstalledKey) boolValue];
	if (self.window) {
		_ttAllowSBUIControllerFallback = YES;
		if (!installed) {
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_jikanChargingStateChanged:) name:JikanChargingStateChangedNotification object:nil];
			objc_setAssociatedObject(self, kTTCoverSheetObserverInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		TTSyncChargingStateFromBatteryInfoAndNotify(NO);
		[self _jikanStartChargingBootstrap];
		[self _jikanChargingStateChanged:nil];
	} else if (installed) {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:JikanChargingStateChangedNotification object:nil];
		objc_setAssociatedObject(self, kTTCoverSheetObserverInstalledKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[self _jikanStopChargingBootstrap];
	}
}

- (void)layoutSubviews {
	%orig;

	[self _addOrRemoveRemainingTimePlatterIfNecessary];
	[self _configureRemainingTimePlatterConstraints];
}

%new
- (void)_jikanStartChargingBootstrap {
	[self _jikanStopChargingBootstrap];
	objc_setAssociatedObject(self, kTTCoverSheetBootstrapStartTimeKey, @([NSDate date].timeIntervalSince1970), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(_jikanBootstrapTick:) userInfo:nil repeats:YES];
	timer.tolerance = 0.05;
	objc_setAssociatedObject(self, kTTCoverSheetBootstrapTimerKey, timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)_jikanStopChargingBootstrap {
	NSTimer *timer = (NSTimer *)objc_getAssociatedObject(self, kTTCoverSheetBootstrapTimerKey);
	if (timer) {
		[timer invalidate];
	}
	objc_setAssociatedObject(self, kTTCoverSheetBootstrapTimerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, kTTCoverSheetBootstrapStartTimeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)_jikanBootstrapTick:(NSTimer *)timer {
	#pragma unused(timer)
	if (!self.window) {
		[self _jikanStopChargingBootstrap];
		return;
	}

	BOOL previous = isCharging;
	TTSyncChargingStateFromBatteryInfoAndNotify(NO);
	BOOL changed = (previous != isCharging);
	if (changed) {
		[self _jikanChargingStateChanged:nil];
	}

	NSNumber *startObj = (NSNumber *)objc_getAssociatedObject(self, kTTCoverSheetBootstrapStartTimeKey);
	NSTimeInterval elapsed = [NSDate date].timeIntervalSince1970 - startObj.doubleValue;
	if (elapsed >= 3.0) {
		[self _jikanStopChargingBootstrap];
	}
}

%new
- (void)_jikanChargingStateChanged:(NSNotification *)notification {
	#pragma unused(notification)
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self _jikanChargingStateChanged:nil];
		});
		return;
	}
	[self _addOrRemoveRemainingTimePlatterIfNecessary];
	[self _configureRemainingTimePlatterConstraints];
	[self setNeedsLayout];
	[self layoutIfNeeded];
}

%new
- (void)_addOrRemoveRemainingTimePlatterIfNecessary {
	if (!self.remainingTimePlatter) {
		self.remainingTimePlatter = [[JikanPlatterView alloc] init];
		self.remainingTimePlatter.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:self.remainingTimePlatter];
		[self.remainingTimePlatter setupConstraints];
	}

	TTApplyQuickActionStyleIfPossible(self);

	BOOL shouldShow = isCharging;
	if (shouldShow) {
		[[TT100 sharedInstance] _refreshBatteryInfo];
	}

	[self _setRemainingTimePlatterVisible:shouldShow];
}

%new
- (void)_setRemainingTimePlatterVisible:(BOOL)visible {
	if (!self.remainingTimePlatter) return;

	BOOL currentlyVisible = !self.remainingTimePlatter.hidden && self.remainingTimePlatter.alpha > 0.01;
	if (visible == currentlyVisible) {
		if (visible && self.remainingTimePlatter.alpha < 1.0) {
			self.remainingTimePlatter.alpha = 1.0;
		}
		return;
	}

	[self.remainingTimePlatter.layer removeAllAnimations];

	NSTimeInterval duration = 0.25;
	UIViewAnimationOptions options = UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState;

	if (visible) {
		self.remainingTimePlatter.hidden = NO;
		if (self.remainingTimePlatter.alpha < 0.01) {
			self.remainingTimePlatter.alpha = 0.0;
		}
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
	static const CGFloat kPlatterHeight = 60.0;
	CGFloat platterWidth = MAX(180.0, MIN(280.0, self.bounds.size.width * 0.45));
	CGFloat bottomOffset = hideQuickActionButtons ? -28.0 : -76.0;
	CGFloat centerXOffset = 0.0;

	CGRect flashRect = CGRectZero;
	CGRect cameraRect = CGRectZero;
	if (TTQuickActionButtonFramesInView(self, &flashRect, &cameraRect)) {
		CGFloat targetCenterY = (CGRectGetMidY(flashRect) + CGRectGetMidY(cameraRect)) * 0.5;
		CGFloat safeBottomY = CGRectGetHeight(self.bounds) - self.safeAreaInsets.bottom;
		bottomOffset = (targetCenterY + (kPlatterHeight * 0.5)) - safeBottomY;
		CGFloat targetCenterX = (CGRectGetMidX(flashRect) + CGRectGetMidX(cameraRect)) * 0.5;
		centerXOffset = targetCenterX - CGRectGetMidX(self.bounds);

		CGFloat innerGap = CGRectGetMinX(cameraRect) - CGRectGetMaxX(flashRect);
		if (innerGap > 0) {
			CGFloat targetWidth = innerGap - 12.0;
			platterWidth = MAX(136.0, MIN(220.0, targetWidth));
		}

		if (!TTPlatterAlignmentLogged(self)) {
			NSLog(@"[Jikan] QA alignment metrics flash=%@ camera=%@ targetWidth=%.2f bottomOffset=%.2f centerXOffset=%.2f yOffset=%.2f", NSStringFromCGRect(flashRect), NSStringFromCGRect(cameraRect), platterWidth, bottomOffset, centerXOffset, platterYOffset);
			TTSetPlatterAlignmentLogged(self, YES);
		}
	}

	bottomOffset -= platterYOffset;

	if (!TTConstraintsInstalled(self)) {
		NSLayoutConstraint *width = [self.remainingTimePlatter.widthAnchor constraintEqualToConstant:platterWidth];
		NSLayoutConstraint *height = [self.remainingTimePlatter.heightAnchor constraintEqualToConstant:kPlatterHeight];
		NSLayoutConstraint *centerX = [self.remainingTimePlatter.centerXAnchor constraintEqualToAnchor:self.centerXAnchor constant:centerXOffset];
		NSLayoutConstraint *bottom = [self.remainingTimePlatter.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:bottomOffset];
		TTSetConstraint(self, kTTPlatterWidthConstraintKey, width);
		TTSetConstraint(self, kTTPlatterHeightConstraintKey, height);
		TTSetConstraint(self, kTTPlatterCenterXConstraintKey, centerX);
		TTSetConstraint(self, kTTPlatterBottomConstraintKey, bottom);
		[NSLayoutConstraint activateConstraints:@[width, height, centerX, bottom]];
		TTSetConstraintsInstalled(self, YES);
	} else {
		TTGetConstraint(self, kTTPlatterWidthConstraintKey).constant = platterWidth;
		TTGetConstraint(self, kTTPlatterCenterXConstraintKey).constant = centerXOffset;
		TTGetConstraint(self, kTTPlatterBottomConstraintKey).constant = bottomOffset;
	}
}

%end

%hook CSCoverSheetViewController

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	_ttAllowSBUIControllerFallback = YES;
}

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	UIView *view = self.view;
	if ([view isKindOfClass:NSClassFromString(@"CSCoverSheetView")]) {
		CSCoverSheetView *coverSheet = (CSCoverSheetView *)view;
		TTSyncChargingStateFromBatteryInfoAndNotify(NO);
		[coverSheet _jikanChargingStateChanged:nil];
		[coverSheet _jikanStartChargingBootstrap];
	}
}

%end

%hook CSProminentSubtitleDateView

- (void)didMoveToWindow {
	%orig;

	for (UIView *subview in self.subviews) {
		if (![subview isKindOfClass:NSClassFromString(@"_UIAnimatingLabel")]) continue;

		_UIAnimatingLabel *label = (_UIAnimatingLabel *)subview;

		objc_setAssociatedObject(label, kTTManagedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		label.adjustsFontSizeToFitWidth = autoResizeRemainingBatteryTime;

		NSString *current = label.text ?: @"";
		NSRange sep = [current rangeOfString:@" • " options:NSBackwardsSearch];
		NSString *baseText = (sep.location != NSNotFound) ? [current substringToIndex:sep.location] : current;
		objc_setAssociatedObject(label, kTTBaseTextKey, baseText, OBJC_ASSOCIATION_COPY_NONATOMIC);

		if (isCharging || !showRemainingBatteryTime) {
			[[NSNotificationCenter defaultCenter] removeObserver:label name:TT100BatteryInfoUpdatedNotification object:nil];
			label.text = baseText;
			continue;
		}

		[[NSNotificationCenter defaultCenter] removeObserver:label name:TT100BatteryInfoUpdatedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:label selector:@selector(_updateBatteryTime:) name:TT100BatteryInfoUpdatedNotification object:nil];

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

	[[NSNotificationCenter defaultCenter] removeObserver:label name:TT100BatteryInfoUpdatedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:label selector:@selector(_updateBatteryTime:) name:TT100BatteryInfoUpdatedNotification object:nil];

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

%hook SBFLockScreenDateSubtitleDateView

- (NSString *)string {
	NSString *value = %orig;
	return TTBuildSubtitleWithRemainingTime(value);
}

- (void)setString:(NSString *)string {
	%orig(TTBuildSubtitleWithRemainingTime(string));
}

%end

%hook _UIAnimatingLabel

%new
- (void)_updateBatteryTime:(NSNotification *)notification {
	NSString *storedBase = objc_getAssociatedObject(self, kTTBaseTextKey);
	if (!storedBase) return;

	if (isCharging || !showRemainingBatteryTime) {
		self.text = storedBase;
		[[NSNotificationCenter defaultCenter] removeObserver:self name:TT100BatteryInfoUpdatedNotification object:nil];
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

	self.adjustsFontSizeToFitWidth = autoResizeRemainingBatteryTime;
	self.text = (storedBase.length > 0)
		? [NSString stringWithFormat:@"%@ • %@", storedBase, timeString]
		: timeString;
}

%end

%ctor {
	TTLoadPreferences();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, TTPrefsDidChange, (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

	if (!enabled) {
		return;
	}

	TTSyncChargingStateFromBatteryInfoAndNotify(NO);

	[TT100 startMonitoring];
	[[NSNotificationCenter defaultCenter] addObserverForName:TT100InternalDidRefreshBatteryInfoNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
		NSDictionary *bi = note.userInfo[@"batteryInfo"];
		if (isCharging && bi) TT100RecordTicksIfNeeded(bi);
	}];
}

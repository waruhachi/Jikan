#import "Jikan.h"

BOOL isCharging = NO;
static BOOL enabled;
static BOOL hideQuickActionButtons;
static BOOL hideQuickActionButtonsOnlyWhenCharging;
static BOOL showAfterFullCharge;
static BOOL lockPreviewXAxis;
static BOOL lockPreviewYAxis;
static CGFloat pillBackgroundOpacity;
static CGFloat platterPosXNorm;
static CGFloat platterPosYNorm;
static BOOL platterHasCustomPosition;
static CGFloat platterPosXNormLandscape;
static CGFloat platterPosYNormLandscape;
static BOOL platterHasCustomPositionLandscape;

static JikanSessionRecorder *_ttSessionRecorder;
static CFAbsoluteTime _ttLastNCPreviewTriggerTime = 0;
static BOOL _ttPreviewSessionActive = NO;
static BOOL _ttMonitoringEnabled = NO;
static NSDictionary *_ttLatestSnapshot;
static void TTApplyEnabledState(void);

static const void *kTTCoverSheetCoordinatorKey = &kTTCoverSheetCoordinatorKey;

static JikanCoverSheetCoordinator *TTCoverSheetCoordinator(UIView *view) {
	JikanCoverSheetCoordinator *coordinator = objc_getAssociatedObject(view, kTTCoverSheetCoordinatorKey);
	if (!coordinator) {
		coordinator = [[JikanCoverSheetCoordinator alloc] initWithRootView:view configurationProvider:^{
			return (JikanCoverSheetConfiguration){
				.enabled = enabled,
				.hideQuickActionButtons = hideQuickActionButtons,
				.hideQuickActionButtonsOnlyWhenCharging = hideQuickActionButtonsOnlyWhenCharging,
				.showAfterFullCharge = showAfterFullCharge,
				.lockPreviewXAxis = lockPreviewXAxis,
				.lockPreviewYAxis = lockPreviewYAxis,
				.charging = isCharging,
				.previewActive = _ttPreviewSessionActive,
				.portraitPosition = {platterPosXNorm, platterPosYNorm, platterHasCustomPosition},
				.landscapePosition = {platterPosXNormLandscape, platterPosYNormLandscape, platterHasCustomPositionLandscape}};
		} snapshotProvider:^{
			return _ttLatestSnapshot;
		} positionChanged:^(BOOL landscape, JikanPillPosition position) {
			if (landscape) {
				platterPosXNormLandscape = position.x;
				platterPosYNormLandscape = position.y;
				platterHasCustomPositionLandscape = position.hasCustomPosition;
			} else {
				platterPosXNorm = position.x;
				platterPosYNorm = position.y;
				platterHasCustomPosition = position.hasCustomPosition;
			}
		}];
		objc_setAssociatedObject(view, kTTCoverSheetCoordinatorKey, coordinator, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	return coordinator;
}

static BOOL TTShouldHideQuickActionButtonsNow(void) {
	if (!enabled || !hideQuickActionButtons) return NO;
	if (!hideQuickActionButtonsOnlyWhenCharging) return YES;
	return isCharging;
}

static const char *TTUnqualifiedType(const char *type) {
	while (type && (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' || *type == 'O' || *type == 'R' || *type == 'V')) {
		type++;
	}
	return type;
}

static BOOL TTOpenNotificationCenterViaCoverSheetManager(void) {
	Class managerClass = NSClassFromString(@"SBCoverSheetPresentationManager");
	SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
	if (![managerClass respondsToSelector:sharedSelector]) return NO;
	NSMethodSignature *sharedSignature = [managerClass methodSignatureForSelector:sharedSelector];
	if (sharedSignature.numberOfArguments != 2 || sharedSignature.methodReturnType[0] != '@') return NO;
	id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedSelector);
	for (NSString *name in @[@"setCoverSheetPresented:animated:withCompletion:", @"setCoverSheetPresented:animated:options:withCompletion:", @"setCoverSheetPresented:animated:dismissModalPresentation:withCompletion:"]) {
		SEL selector = NSSelectorFromString(name);
		if (![manager respondsToSelector:selector]) continue;
		NSMethodSignature *signature = [manager methodSignatureForSelector:selector];
		BOOL hasOptions = [name containsString:@"options:"];
		BOOL hasDismiss = [name containsString:@"dismissModalPresentation:"];
		NSUInteger arguments = (hasOptions || hasDismiss) ? 6 : 5;
		if (signature.numberOfArguments != arguments || strcmp(TTUnqualifiedType(signature.methodReturnType), @encode(void)) != 0) continue;
		BOOL valid = YES;
		for (NSUInteger i = 2; i < 4; i++) {
			const char *type = TTUnqualifiedType([signature getArgumentTypeAtIndex:i]);
			if (strcmp(type, @encode(BOOL)) != 0) valid = NO;
		}
		if (hasOptions && strcmp(TTUnqualifiedType([signature getArgumentTypeAtIndex:4]), @encode(unsigned long long)) != 0) valid = NO;
		if (hasDismiss && strcmp(TTUnqualifiedType([signature getArgumentTypeAtIndex:4]), @encode(BOOL)) != 0) valid = NO;
		if ([signature getArgumentTypeAtIndex:arguments - 1][0] != '@' || !valid) continue;
		if (hasOptions) ((void (*)(id, SEL, BOOL, BOOL, unsigned long long, id))objc_msgSend)(manager, selector, YES, !UIAccessibilityIsReduceMotionEnabled(), 0, nil);
		else if (hasDismiss)
			((void (*)(id, SEL, BOOL, BOOL, BOOL, id))objc_msgSend)(manager, selector, YES, !UIAccessibilityIsReduceMotionEnabled(), NO, nil);
		else
			((void (*)(id, SEL, BOOL, BOOL, id))objc_msgSend)(manager, selector, YES, !UIAccessibilityIsReduceMotionEnabled(), nil);
		return YES;
	}
	return NO;
}

static BOOL TTOpenNotificationCenterPreview(void) {
	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	if ((now - _ttLastNCPreviewTriggerTime) < 0.35) return NO;
	_ttLastNCPreviewTriggerTime = now;
	@try {
		return TTOpenNotificationCenterViaCoverSheetManager();
	}
	@catch (__unused NSException *exception) {
		return NO;
	}
}

static void TTNCPreviewRequestReceived(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
#pragma unused(center, observer, name, object, userInfo)
	dispatch_async(dispatch_get_main_queue(), ^{
		if (!enabled) return;
		_ttPreviewSessionActive = TTOpenNotificationCenterPreview();
		[[NSNotificationCenter defaultCenter] postNotificationName:JikanChargingStateChangedNotification object:nil userInfo:@{@"isCharging": @(isCharging)}];
	});
}

static void TTEndPreviewSession(void) {
	if (!_ttPreviewSessionActive) return;
	_ttPreviewSessionActive = NO;
	[[NSNotificationCenter defaultCenter] postNotificationName:JikanChargingStateChangedNotification object:nil userInfo:@{@"isCharging": @(isCharging)}];
}

static void TTLoadPreferences(void) {
	NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	static NSString *estimateSignature;
	NSString *source = JikanEstimateSource(preferences);
	NSString *newSignature = [NSString stringWithFormat:@"%@:%ld", source, (long)JikanEstimateTarget(preferences, source)];
	if (estimateSignature && ![estimateSignature isEqualToString:newSignature]) _ttLatestSnapshot = nil;
	estimateSignature = newSignature;
	enabled = [preferences objectForKey:@"enabled"] ? [preferences boolForKey:@"enabled"] : YES;
	hideQuickActionButtons = [preferences objectForKey:@"hideQuickActionButtons"] ? [preferences boolForKey:@"hideQuickActionButtons"] : NO;
	hideQuickActionButtonsOnlyWhenCharging = [preferences objectForKey:@"hideQuickActionButtonsOnlyWhenCharging"] ? [preferences boolForKey:@"hideQuickActionButtonsOnlyWhenCharging"] : NO;
	showAfterFullCharge = [preferences objectForKey:@"showAfterFullCharge"] ? [preferences boolForKey:@"showAfterFullCharge"] : NO;
	lockPreviewXAxis = [preferences objectForKey:JikanPreviewXAxisLockKey] ? [preferences boolForKey:JikanPreviewXAxisLockKey] : NO;
	lockPreviewYAxis = [preferences objectForKey:JikanPreviewYAxisLockKey] ? [preferences boolForKey:JikanPreviewYAxisLockKey] : NO;
	double opacityPercent = [preferences objectForKey:@"pillBackgroundOpacityPercent"] ? [preferences doubleForKey:@"pillBackgroundOpacityPercent"] : 100.0;
	if (!isfinite(opacityPercent)) opacityPercent = 100.0;
	opacityPercent = MAX(0.0, MIN(100.0, opacityPercent));
	pillBackgroundOpacity = (CGFloat)(opacityPercent / 100.0);
	JikanPillPosition portrait = JikanReadPillPosition(preferences, NO);
	platterPosXNorm = portrait.x;
	platterPosYNorm = portrait.y;
	platterHasCustomPosition = portrait.hasCustomPosition;
	JikanPillPosition landscape = JikanReadPillPosition(preferences, YES);
	platterPosXNormLandscape = landscape.x;
	platterPosYNormLandscape = landscape.y;
	platterHasCustomPositionLandscape = landscape.hasCustomPosition;
}

static void TTPrefsDidChange(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
#pragma unused(center, observer, name, object, userInfo)
	dispatch_async(dispatch_get_main_queue(), ^{
		TTLoadPreferences();
		[TT100 preferencesDidChange];
		TTApplyEnabledState();
	});
}

static BOOL TTInferChargingStateFromBatteryInfo(NSDictionary *batteryInfo) {
	if (![batteryInfo isKindOfClass:[NSDictionary class]]) return NO;

	id external = batteryInfo[@"ExternalConnected"];
	if ([external respondsToSelector:@selector(boolValue)]) return [external boolValue];

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

static void TTApplyEnabledState(void) {
	if (enabled) {
		if (!_ttMonitoringEnabled) {
			_ttMonitoringEnabled = YES;
			[TT100 startMonitoring];
		} else {
			[[TT100 sharedInstance] _refreshBatteryInfo];
		}
	} else {
		_ttMonitoringEnabled = NO;
		[TT100 stopMonitoring];
		[_ttSessionRecorder finishWithBatteryInfo:_ttLatestSnapshot[@"batteryInfo"]];
		_ttLatestSnapshot = nil;
		_ttPreviewSessionActive = NO;
		isCharging = NO;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:JikanChargingStateChangedNotification object:nil userInfo:@{@"isCharging": @(isCharging)}];
}

%group JikanQuickActionVisibility
%hook JikanQuickActionControl
- (void)setHidden:(BOOL)hidden {
	%orig([JikanQuickActionAdapter hiddenValueForControl:self requestedHidden:hidden]);
}
%end
%end

%hook _UIBatteryView
- (void)setChargingState:(NSInteger)state {
	%orig;
	if (enabled) [[TT100 sharedInstance] _refreshBatteryInfo];
}
%end

%hook CSQuickActionsView

- (void)refreshSupportedButtons {
	[JikanQuickActionAdapter setButtonsInView:self hidden:NO];
	%orig;
	BOOL shouldHide = TTShouldHideQuickActionButtonsNow();
	[JikanQuickActionAdapter setButtonsInView:self hidden:shouldHide];
}

%end

%hook CSCoverSheetView

- (void)didMoveToWindow {
	%orig;
	if (!self.window) _ttPreviewSessionActive = NO;
	[TTCoverSheetCoordinator(self) didMoveToWindow];
}

- (void)layoutSubviews {
	%orig;
	[TTCoverSheetCoordinator(self) layoutSubviews];
}

%end

%hook CSCoverSheetViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	UIView *view = self.view;
	if ([view isKindOfClass:NSClassFromString(@"CSCoverSheetView")]) {
		if (enabled) [[TT100 sharedInstance] _refreshBatteryInfo];
		[TTCoverSheetCoordinator(view) refresh];
	}
}

- (void)viewWillDisappear:(BOOL)animated {
	%orig;
	TTEndPreviewSession();
}

- (void)viewDidDisappear:(BOOL)animated {
	%orig;
	TTEndPreviewSession();
}

%end

%ctor {
	_ttSessionRecorder = [JikanSessionRecorder new];
	%init;
	Class visibilityClass = [JikanQuickActionAdapter visibilityControlClass];
	if (visibilityClass) {
		%init(JikanQuickActionVisibility, JikanQuickActionControl = visibilityClass);
	}
	TTLoadPreferences();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, TTPrefsDidChange, (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, TTNCPreviewRequestReceived, (__bridge CFStringRef)JikanPreviewRequestNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	[[NSNotificationCenter defaultCenter] addObserverForName:TT100InternalDidRefreshBatteryInfoNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
		if (!enabled) return;
		_ttLatestSnapshot = [note.userInfo copy];
		NSDictionary *batteryInfo = _ttLatestSnapshot[@"batteryInfo"];
		if (!batteryInfo.count) return;
		BOOL wasCharging = isCharging;
		isCharging = TTInferChargingStateFromBatteryInfo(batteryInfo);
		[_ttSessionRecorder consumeSnapshot:_ttLatestSnapshot charging:isCharging];
		if (wasCharging != isCharging) [[NSNotificationCenter defaultCenter] postNotificationName:JikanChargingStateChangedNotification object:nil userInfo:@{@"isCharging": @(isCharging)}];
	}];
	dispatch_async(dispatch_get_main_queue(), ^{ TTApplyEnabledState(); });
}

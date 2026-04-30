#import "Jikan.h"

BOOL isCharging = NO;
static NSString *const kJikanPrefsSuite = @"moe.waru.jikan.preferences";
static NSString *const kJikanPrefsReloadNotification = @"moe.waru.jikan.preferences.reload";
static NSString *const kJikanOpenNCPreviewNotification = @"moe.waru.jikan.preview.nc.request";
static NSInteger _tt100CurrentSessionId = -1;
static NSInteger _tt100LastSOC = -1;
static CFAbsoluteTime _tt100LastSOCTime = 0;
static NSMutableDictionary<NSNumber *, NSMutableArray<NSNumber *> *> *_tt100Durations;
static NSString *_tt100CurrentChargerClass = nil;
static BOOL _tt100CurrentIsWireless = NO;
static const void *kTTPlatterWidthConstraintKey = &kTTPlatterWidthConstraintKey;
static const void *kTTPlatterHeightConstraintKey = &kTTPlatterHeightConstraintKey;
static const void *kTTPlatterCenterXConstraintKey = &kTTPlatterCenterXConstraintKey;
static const void *kTTPlatterConstraintsInstalledKey = &kTTPlatterConstraintsInstalledKey;
static const void *kTTPlatterStyleCapturedKey = &kTTPlatterStyleCapturedKey;
static const void *kTTCoverSheetObserverInstalledKey = &kTTCoverSheetObserverInstalledKey;
static const void *kTTCoverSheetBootstrapTimerKey = &kTTCoverSheetBootstrapTimerKey;
static const void *kTTCoverSheetBootstrapStartTimeKey = &kTTCoverSheetBootstrapStartTimeKey;
static const void *kTTPlatterCenterYConstraintKey = &kTTPlatterCenterYConstraintKey;
static const void *kTTPlatterLongPressKey = &kTTPlatterLongPressKey;
static const void *kTTPlatterDragStartCenterKey = &kTTPlatterDragStartCenterKey;
static const void *kTTPlatterDragStartTouchKey = &kTTPlatterDragStartTouchKey;
static const void *kTTPlatterDefaultCenterComputedPortraitKey = &kTTPlatterDefaultCenterComputedPortraitKey;
static const void *kTTPlatterDefaultCenterComputedLandscapeKey = &kTTPlatterDefaultCenterComputedLandscapeKey;
static const void *kTTPlatterDraggingKey = &kTTPlatterDraggingKey;
static BOOL _ttLastResolvedChargingValid = NO;
static BOOL _ttAllowSBUIControllerFallback = NO;
static CFAbsoluteTime _ttLastNCPreviewTriggerTime = 0;
static BOOL _ttPreviewSessionActive = NO;

static BOOL TTShouldHideQuickActionButtonsNow(void) {
	if (!hideQuickActionButtons) return NO;
	if (!hideQuickActionButtonsOnlyWhenCharging) return YES;
	return isCharging;
}

static const char *TTUnqualifiedType(const char *type) {
	while (type && (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' || *type == 'O' || *type == 'R' || *type == 'V')) {
		type++;
	}
	return type;
}

static BOOL TTInvokeSelectorWithDefaultArguments(id target, NSString *selectorName) {
	if (!target || selectorName.length == 0) return NO;
	SEL selector = NSSelectorFromString(selectorName);
	if (!selector || ![target respondsToSelector:selector]) return NO;

	NSMethodSignature *sig = [target methodSignatureForSelector:selector];
	if (!sig) return NO;

	NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
	inv.target = target;
	inv.selector = selector;

	NSUInteger argCount = sig.numberOfArguments;
	for (NSUInteger i = 2; i < argCount; i++) {
		const char *rawType = [sig getArgumentTypeAtIndex:i];
		const char *type = TTUnqualifiedType(rawType);
		if (!type) continue;

		switch (type[0]) {
			case '@': {
				id value = nil;
				[inv setArgument:&value atIndex:i];
				break;
			}
			case 'B':
			case 'c': {
				BOOL value = YES;
				[inv setArgument:&value atIndex:i];
				break;
			}
			case 'i':
			case 's':
			case 'l':
			case 'q':
			case 'I':
			case 'S':
			case 'L':
			case 'Q': {
				NSInteger value = 1;
				[inv setArgument:&value atIndex:i];
				break;
			}
			case 'f': {
				float value = 1.0f;
				[inv setArgument:&value atIndex:i];
				break;
			}
			case 'd': {
				double value = 1.0;
				[inv setArgument:&value atIndex:i];
				break;
			}
			default: {
				NSUInteger size = 0;
				NSGetSizeAndAlignment(type, &size, NULL);
				if (size > 0) {
					void *zero = calloc(1, size);
					[inv setArgument:zero atIndex:i];
					free(zero);
				}
				break;
			}
		}
	}

	@try {
		[inv invoke];
		return YES;
	}
	@catch (__unused NSException *exception) {
		return NO;
	}
}

static BOOL TTOpenNotificationCenterWithObject(id target) {
	if (!target) return NO;
	NSArray<NSString *> *selectors = @[
		@"presentNotificationCenter",
		@"showNotificationCenter",
		@"revealNotificationCenter",
		@"_showNotificationCenter",
		@"_showNotifications",
		@"_showNotificationsIfNecessary",
		@"_presentNotificationCenter",
		@"_revealNotificationCenter",
		@"_setNotificationCenterVisible:animated:",
		@"setNotificationCenterVisible:animated:",
		@"_setVisible:animated:",
		@"_setPresented:animated:",
		@"_handleShowNotificationsSystemGesture",
		@"_handleShowNotificationsGesture",
		@"_showNotificationsGestureBeganFromSource:",
		@"_showNotificationsGestureEndedWithCompletionType:",
		@"_showNotificationsGestureEndedFromSource:",
		@"_toggleNotificationCenter",
		@"toggleNotificationCenter",
		@"presentNotificationCenterAnimated:",
		@"showNotificationCenterAnimated:",
		@"revealNotificationCenterAnimated:",
		@"_presentNotificationCenterAnimated:",
		@"_showNotificationCenterAnimated:",
		@"_revealNotificationCenterAnimated:",
		@"presentAnimated:",
		@"revealAnimated:"
	];
	for (NSString *name in selectors) {
		if (TTInvokeSelectorWithDefaultArguments(target, name)) return YES;
	}
	return NO;
}

static BOOL TTOpenNotificationCenterViaCoverSheetManager(void) {
	Class managerClass = NSClassFromString(@"SBCoverSheetPresentationManager");
	if (!managerClass) return NO;

	id manager = nil;
	SEL sharedSel = NSSelectorFromString(@"sharedInstance");
	SEL sharedIfExistsSel = NSSelectorFromString(@"sharedInstanceIfExists");
	if ([managerClass respondsToSelector:sharedSel]) {
		manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedSel);
	} else if ([managerClass respondsToSelector:sharedIfExistsSel]) {
		manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedIfExistsSel);
	}
	if (!manager) return NO;

	SEL presentSel = NSSelectorFromString(@"setCoverSheetPresented:animated:withCompletion:");
	if ([manager respondsToSelector:presentSel]) {
		((void (*)(id, SEL, BOOL, BOOL, id))objc_msgSend)(manager, presentSel, YES, YES, nil);
		return YES;
	}

	SEL presentOptionsSel = NSSelectorFromString(@"setCoverSheetPresented:animated:options:withCompletion:");
	if ([manager respondsToSelector:presentOptionsSel]) {
		((void (*)(id, SEL, BOOL, BOOL, unsigned long long, id))objc_msgSend)(manager, presentOptionsSel, YES, YES, 0, nil);
		return YES;
	}

	SEL presentDismissModalSel = NSSelectorFromString(@"setCoverSheetPresented:animated:dismissModalPresentation:withCompletion:");
	if ([manager respondsToSelector:presentDismissModalSel]) {
		((void (*)(id, SEL, BOOL, BOOL, BOOL, id))objc_msgSend)(manager, presentDismissModalSel, YES, YES, NO, nil);
		return YES;
	}

	SEL translationSel = NSSelectorFromString(@"setCoverSheetTranslationToPresented:forcingTransition:ignoringPreflightRequirements:suppressingIconFly:animated:");
	if ([manager respondsToSelector:translationSel]) {
		((void (*)(id, SEL, BOOL, BOOL, BOOL, BOOL, BOOL))objc_msgSend)(manager, translationSel, YES, YES, YES, NO, YES);
		return YES;
	}

	SEL translationLegacySel = NSSelectorFromString(@"setCoverSheetTranslationToPresented:forcingTransition:ignoringPreflightRequirements:animated:");
	if ([manager respondsToSelector:translationLegacySel]) {
		((void (*)(id, SEL, BOOL, BOOL, BOOL, BOOL))objc_msgSend)(manager, translationLegacySel, YES, YES, YES, YES);
		return YES;
	}

	return NO;
}

static void TTOpenNotificationCenterPreview(void) {
	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	if ((now - _ttLastNCPreviewTriggerTime) < 0.35) return;
	_ttLastNCPreviewTriggerTime = now;

	@try {
		if (TTOpenNotificationCenterViaCoverSheetManager()) return;

		id app = [UIApplication sharedApplication];
		if (TTOpenNotificationCenterWithObject(app)) return;
		id appDelegate = [app respondsToSelector:@selector(delegate)] ? ((id (*)(id, SEL))objc_msgSend)(app, @selector(delegate)) : nil;
		if (TTOpenNotificationCenterWithObject(appDelegate)) return;

		NSArray<NSString *> *classNames = @[
			@"SBNotificationCenterController",
			@"SBUIController",
			@"SpringBoard",
			@"SBMainWorkspace"
		];
		NSArray<NSString *> *singletonSelectors = @[
			@"sharedInstance",
			@"sharedController",
			@"defaultInstance"
		];

		for (NSString *className in classNames) {
			Class cls = NSClassFromString(className);
			if (!cls) continue;

			for (NSString *selName in singletonSelectors) {
				SEL sel = NSSelectorFromString(selName);
				if (![cls respondsToSelector:sel]) continue;
				id instance = ((id (*)(id, SEL))objc_msgSend)(cls, sel);
				if (!instance) continue;
				if (TTOpenNotificationCenterWithObject(instance)) return;
			}

			if (TTOpenNotificationCenterWithObject(cls)) return;
		}
		return;
	}
	@catch (NSException *exception) {
		NSLog(@"[Jikan] Failed opening Notification Center preview: %@", exception);
	}
}

static void TTNCPreviewRequestReceived(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
#pragma unused(center, observer, name, object, userInfo)
	dispatch_async(dispatch_get_main_queue(), ^{
		_ttPreviewSessionActive = YES;
		[[NSNotificationCenter defaultCenter] postNotificationName:JikanChargingStateChangedNotification object:nil userInfo:@{ @"isCharging": @(isCharging) }];
		TTOpenNotificationCenterPreview();
	});
}

static void TTEndPreviewSession(void) {
	if (!_ttPreviewSessionActive) return;
	_ttPreviewSessionActive = NO;
	[[NSNotificationCenter defaultCenter] postNotificationName:JikanChargingStateChangedNotification object:nil userInfo:@{ @"isCharging": @(isCharging) }];
}

static CGFloat TTPercentToNorm(id value, CGFloat fallback) {
	double v = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : (double)(fallback * 100.0);
	if (!isfinite(v)) v = (double)(fallback * 100.0);
	v = MAX(0.0, MIN(100.0, v));
	return (CGFloat)(v / 100.0);
}

static void TTLoadPreferences(void) {
	NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	enabled = [preferences objectForKey:@"enabled"] ? [preferences boolForKey:@"enabled"] : YES;
	hideQuickActionButtons = [preferences objectForKey:@"hideQuickActionButtons"] ? [preferences boolForKey:@"hideQuickActionButtons"] : NO;
	hideQuickActionButtonsOnlyWhenCharging = [preferences objectForKey:@"hideQuickActionButtonsOnlyWhenCharging"] ? [preferences boolForKey:@"hideQuickActionButtonsOnlyWhenCharging"] : NO;
	tapToShowWattage = [preferences objectForKey:@"tapToShowWattage"] ? [preferences boolForKey:@"tapToShowWattage"] : NO;
	showAfterFullCharge = [preferences objectForKey:@"showAfterFullCharge"] ? [preferences boolForKey:@"showAfterFullCharge"] : NO;
	lockPreviewXAxis = [preferences objectForKey:@"lockPreviewXAxis"] ? [preferences boolForKey:@"lockPreviewXAxis"] : NO;
	lockPreviewYAxis = [preferences objectForKey:@"lockPreviewYAxis"] ? [preferences boolForKey:@"lockPreviewYAxis"] : NO;
	double opacityPercent = [preferences objectForKey:@"pillBackgroundOpacityPercent"] ? [preferences doubleForKey:@"pillBackgroundOpacityPercent"] : 100.0;
	if (!isfinite(opacityPercent)) opacityPercent = 100.0;
	opacityPercent = MAX(0.0, MIN(100.0, opacityPercent));
	pillBackgroundOpacity = (CGFloat)(opacityPercent / 100.0);
	platterHasCustomPosition = ([preferences objectForKey:@"platterPosXNorm"] != nil && [preferences objectForKey:@"platterPosYNorm"] != nil);
	platterPosXNorm = platterHasCustomPosition ? [preferences doubleForKey:@"platterPosXNorm"] : 0.5;
	platterPosYNorm = platterHasCustomPosition ? [preferences doubleForKey:@"platterPosYNorm"] : 0.84;
	platterHasCustomPositionLandscape = ([preferences objectForKey:@"platterPosXNormLandscape"] != nil && [preferences objectForKey:@"platterPosYNormLandscape"] != nil);
	platterPosXNormLandscape = platterHasCustomPositionLandscape ? [preferences doubleForKey:@"platterPosXNormLandscape"] : 0.5;
	platterPosYNormLandscape = platterHasCustomPositionLandscape ? [preferences doubleForKey:@"platterPosYNormLandscape"] : 0.84;
	platterPosXNorm = MAX(0.05, MIN(0.95, platterPosXNorm));
	platterPosYNorm = MAX(0.05, MIN(0.95, platterPosYNorm));
	platterPosXNormLandscape = MAX(0.05, MIN(0.95, platterPosXNormLandscape));
	platterPosYNormLandscape = MAX(0.05, MIN(0.95, platterPosYNormLandscape));

	id px = [preferences objectForKey:@"pillPosXPortraitPercent"];
	id py = [preferences objectForKey:@"pillPosYPortraitPercent"];
	if (px || py) {
		platterPosXNorm = TTPercentToNorm(px, platterPosXNorm);
		platterPosYNorm = TTPercentToNorm(py, platterPosYNorm);
		platterPosXNorm = MAX(0.05, MIN(0.95, platterPosXNorm));
		platterPosYNorm = MAX(0.05, MIN(0.95, platterPosYNorm));
		platterHasCustomPosition = YES;
	}

	id lx = [preferences objectForKey:@"pillPosXLandscapePercent"];
	id ly = [preferences objectForKey:@"pillPosYLandscapePercent"];
	if (lx || ly) {
		platterPosXNormLandscape = TTPercentToNorm(lx, platterPosXNormLandscape);
		platterPosYNormLandscape = TTPercentToNorm(ly, platterPosYNormLandscape);
		platterPosXNormLandscape = MAX(0.05, MIN(0.95, platterPosXNormLandscape));
		platterPosYNormLandscape = MAX(0.05, MIN(0.95, platterPosYNormLandscape));
		platterHasCustomPositionLandscape = YES;
	}
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

static UIView *TTFindDateViewContainer(CSCoverSheetView *coverSheet) {
	if (!coverSheet) return nil;
	Class dateClass = NSClassFromString(@"CSProminentSubtitleDateView");
	if (!dateClass) return nil;

	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:coverSheet];
	while (stack.count) {
		UIView *view = stack.lastObject;
		[stack removeLastObject];
		if ([view isKindOfClass:dateClass]) {
			return view;
		}
		for (UIView *sub in view.subviews) {
			[stack addObject:sub];
		}
	}
	return nil;
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
	if (TTPlatterStyleCaptured(coverSheet)) return;
	CSQuickActionsView *quickActions = TTFindQuickActionsView(coverSheet);
	CSQuickActionsButton *referenceButton = quickActions.flashlightButton ?: quickActions.cameraButton;

	UIView *sourceMaterialView = TTFindNearestQuickActionMaterialView(coverSheet);
	if (!sourceMaterialView) return;

	if ([sourceMaterialView isKindOfClass:[UIVisualEffectView class]]) {
		UIVisualEffectView *sourceEffect = (UIVisualEffectView *)sourceMaterialView;
		[coverSheet.remainingTimePlatter applyQuickActionVisualEffect:sourceEffect.effect];
		UIView *styleSource = sourceMaterialView.superview ?: (referenceButton ?: sourceMaterialView);
		[coverSheet.remainingTimePlatter applyQuickActionBackgroundStyleFromView:styleSource];
		if (!TTPlatterStyleCaptured(coverSheet)) {
			TTSetPlatterStyleCaptured(coverSheet, YES);
		}
		return;
	}

	[coverSheet.remainingTimePlatter applyQuickActionBackgroundStyleFromView:(referenceButton ?: sourceMaterialView)];
	if (!TTPlatterStyleCaptured(coverSheet)) {
		TTSetPlatterStyleCaptured(coverSheet, YES);
	}
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
	_tt100LastSOC = soc;
	_tt100LastSOCTime = now;
}

static BOOL TTReadIsOnACFromSBUIController(BOOL *outHasValue) {
	if (outHasValue) *outHasValue = NO;
	@try {
		Class cls = NSClassFromString(@"SBUIController");
		if (!cls || ![cls respondsToSelector:@selector(sharedInstance)]) return NO;
		id controller = [cls sharedInstance];
		if (!controller || ![controller respondsToSelector:@selector(isOnAC)]) return NO;
		if (outHasValue) *outHasValue = YES;
		return ((BOOL (*)(id, SEL))objc_msgSend)(controller, @selector(isOnAC));
	}
	@catch (__unused NSException *exception) {
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
	BOOL shouldHide = TTShouldHideQuickActionButtonsNow();
	self.cameraButton.hidden = shouldHide;
	self.flashlightButton.hidden = shouldHide;
}

%end

%hook CSCoverSheetView
%property(nonatomic, strong) JikanPlatterView *remainingTimePlatter;

- (void)didMoveToWindow {
	%orig;

	BOOL installed = [objc_getAssociatedObject(self, kTTCoverSheetObserverInstalledKey) boolValue];
	if (self.window) {
		_ttAllowSBUIControllerFallback = YES;
		TTSetPlatterStyleCaptured(self, NO);
		if (!installed) {
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_jikanChargingStateChanged:) name:JikanChargingStateChangedNotification object:nil];
			objc_setAssociatedObject(self, kTTCoverSheetObserverInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		TTSyncChargingStateFromBatteryInfoAndNotify(NO);
		[self _jikanStartChargingBootstrap];
		[self _jikanChargingStateChanged:nil];
	} else {
		_ttPreviewSessionActive = NO;
		if (self.remainingTimePlatter) {
			[self.remainingTimePlatter setPreviewMode:NO];
		}
		if (installed) {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:JikanChargingStateChangedNotification object:nil];
		objc_setAssociatedObject(self, kTTCoverSheetObserverInstalledKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[self _jikanStopChargingBootstrap];
		}
	}
}

- (void)layoutSubviews {
	%orig;

	if (!self.remainingTimePlatter) {
		[self _addOrRemoveRemainingTimePlatterIfNecessary];
	}
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
	CSQuickActionsView *quickActions = TTFindQuickActionsView(self);
	if (quickActions) {
		BOOL shouldHide = TTShouldHideQuickActionButtonsNow();
		quickActions.cameraButton.hidden = shouldHide;
		quickActions.flashlightButton.hidden = shouldHide;
	}
	[self _configureRemainingTimePlatterConstraints];
	[self setNeedsLayout];
	[self layoutIfNeeded];
}

%new
- (void)_jikanHandlePlatterLongPress:(UILongPressGestureRecognizer *)gesture {
	BOOL previewEnabled = _ttPreviewSessionActive;
	if (!previewEnabled || !self.remainingTimePlatter) return;
	JikanPlatterView *pill = self.remainingTimePlatter;
	CGPoint location = [gesture locationInView:self];
	BOOL isLandscape = CGRectGetWidth(self.bounds) > CGRectGetHeight(self.bounds);

	CGFloat halfW = CGRectGetWidth(pill.bounds) * 0.5;
	CGFloat halfH = CGRectGetHeight(pill.bounds) * 0.5;
	CGFloat minX = self.safeAreaInsets.left + halfW;
	CGFloat maxX = CGRectGetWidth(self.bounds) - self.safeAreaInsets.right - halfW;
	CGFloat minY = self.safeAreaInsets.top + halfH + 8.0;
	CGFloat maxY = CGRectGetHeight(self.bounds) - self.safeAreaInsets.bottom - halfH - 8.0;
	if (maxX < minX) maxX = minX;
	if (maxY < minY) maxY = minY;

	if (gesture.state == UIGestureRecognizerStateBegan) {
		objc_setAssociatedObject(self, kTTPlatterDraggingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		if (isLandscape) {
			platterHasCustomPositionLandscape = YES;
		} else {
			platterHasCustomPosition = YES;
		}
		[pill enterEditMode:YES];
		UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
		[gen impactOccurred];

		CGPoint center = CGPointMake(CGRectGetMidX(pill.frame), CGRectGetMidY(pill.frame));
		objc_setAssociatedObject(self, kTTPlatterDragStartCenterKey, [NSValue valueWithCGPoint:center], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(self, kTTPlatterDragStartTouchKey, [NSValue valueWithCGPoint:location], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	if (gesture.state == UIGestureRecognizerStateChanged) {
		NSValue *centerValue = (NSValue *)objc_getAssociatedObject(self, kTTPlatterDragStartCenterKey);
		NSValue *touchValue = (NSValue *)objc_getAssociatedObject(self, kTTPlatterDragStartTouchKey);
		if (!centerValue || !touchValue) return;

		CGPoint startCenter = centerValue.CGPointValue;
		CGPoint startTouch = touchValue.CGPointValue;
		CGPoint candidate = CGPointMake(startCenter.x + (location.x - startTouch.x), startCenter.y + (location.y - startTouch.y));
		if (lockPreviewXAxis) candidate.x = startCenter.x;
		if (lockPreviewYAxis) candidate.y = startCenter.y;
		candidate.x = MAX(minX, MIN(maxX, candidate.x));
		candidate.y = MAX(minY, MIN(maxY, candidate.y));

		NSLayoutConstraint *cx = TTGetConstraint(self, kTTPlatterCenterXConstraintKey);
		NSLayoutConstraint *cy = TTGetConstraint(self, kTTPlatterCenterYConstraintKey);
		if (cx && cy) {
			cx.constant = candidate.x - CGRectGetMidX(self.bounds);
			cy.constant = candidate.y - CGRectGetMidY(self.bounds);
			CGFloat nx = MAX(0.05, MIN(0.95, candidate.x / MAX(1.0, CGRectGetWidth(self.bounds))));
			CGFloat ny = MAX(0.05, MIN(0.95, candidate.y / MAX(1.0, CGRectGetHeight(self.bounds))));
			if (isLandscape) {
				platterPosXNormLandscape = nx;
				platterPosYNormLandscape = ny;
				platterHasCustomPositionLandscape = YES;
			} else {
				platterPosXNorm = nx;
				platterPosYNorm = ny;
				platterHasCustomPosition = YES;
			}
			[self layoutIfNeeded];
		}
		return;
	}

	if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
		[pill enterEditMode:NO];
		UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
		[gen impactOccurred];

		CGPoint center = CGPointMake(CGRectGetMidX(pill.frame), CGRectGetMidY(pill.frame));
		CGFloat nx = MAX(0.05, MIN(0.95, center.x / MAX(1.0, CGRectGetWidth(self.bounds))));
		CGFloat ny = MAX(0.05, MIN(0.95, center.y / MAX(1.0, CGRectGetHeight(self.bounds))));
		if (isLandscape) {
			platterPosXNormLandscape = nx;
			platterPosYNormLandscape = ny;
			platterHasCustomPositionLandscape = YES;
		} else {
			platterPosXNorm = nx;
			platterPosYNorm = ny;
			platterHasCustomPosition = YES;
		}

		NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
		if (isLandscape) {
			[prefs setDouble:platterPosXNormLandscape forKey:@"platterPosXNormLandscape"];
			[prefs setDouble:platterPosYNormLandscape forKey:@"platterPosYNormLandscape"];
			[prefs setDouble:(platterPosXNormLandscape * 100.0) forKey:@"pillPosXLandscapePercent"];
			[prefs setDouble:(platterPosYNormLandscape * 100.0) forKey:@"pillPosYLandscapePercent"];
		} else {
			[prefs setDouble:platterPosXNorm forKey:@"platterPosXNorm"];
			[prefs setDouble:platterPosYNorm forKey:@"platterPosYNorm"];
			[prefs setDouble:(platterPosXNorm * 100.0) forKey:@"pillPosXPortraitPercent"];
			[prefs setDouble:(platterPosYNorm * 100.0) forKey:@"pillPosYPortraitPercent"];
		}
		[prefs synchronize];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);

		objc_setAssociatedObject(self, kTTPlatterDraggingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(self, kTTPlatterDragStartCenterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(self, kTTPlatterDragStartTouchKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
}

%new
- (void)_addOrRemoveRemainingTimePlatterIfNecessary {
	if (!self.remainingTimePlatter) {
		self.remainingTimePlatter = [[JikanPlatterView alloc] init];
		self.remainingTimePlatter.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:self.remainingTimePlatter];
		[self.remainingTimePlatter setupConstraints];
		UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_jikanHandlePlatterLongPress:)];
		longPress.minimumPressDuration = 0.35;
		[self.remainingTimePlatter addGestureRecognizer:longPress];
		objc_setAssociatedObject(self, kTTPlatterLongPressKey, longPress, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	TTApplyQuickActionStyleIfPossible(self);

	NSDictionary *batteryInfo = [TT100 fetchBatteryInfo];
	BOOL hasEstimate = [TT100 hasEstimateWithBatteryInfo:batteryInfo];
	BOOL fullyCharged = [TT100 isFullyChargedWithBatteryInfo:batteryInfo displayPercent:NULL];
	BOOL previewEnabled = _ttPreviewSessionActive;

	BOOL shouldShow = previewEnabled || (isCharging && (hasEstimate || (showAfterFullCharge && fullyCharged)));
	[self.remainingTimePlatter setPreviewMode:(previewEnabled && !isCharging)];

	UILongPressGestureRecognizer *lp = (UILongPressGestureRecognizer *)objc_getAssociatedObject(self, kTTPlatterLongPressKey);
	lp.enabled = previewEnabled;

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

	NSTimeInterval showDuration = 0.42;
	NSTimeInterval hideDuration = 0.22;
	UIViewAnimationOptions showOptions = UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState;
	UIViewAnimationOptions hideOptions = UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState;

	if (visible) {
		self.remainingTimePlatter.hidden = NO;
		self.remainingTimePlatter.alpha = 0.0;
		self.remainingTimePlatter.transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(0.965, 0.965), 0.0, 4.0);
		[UIView animateWithDuration:showDuration
							  delay:0
			 usingSpringWithDamping:0.88
			  initialSpringVelocity:0.35
							options:showOptions
						 animations:^{
							 self.remainingTimePlatter.alpha = 1.0;
							 self.remainingTimePlatter.transform = CGAffineTransformIdentity;
						 }
						 completion:nil];
	} else {
		[UIView animateWithDuration:hideDuration delay:0 options:hideOptions animations:^{
			self.remainingTimePlatter.alpha = 0.0;
			self.remainingTimePlatter.transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(0.975, 0.975), 0.0, 2.0);
		} completion:^(BOOL finished) {
			if (finished && self.remainingTimePlatter.alpha <= 0.01) {
				self.remainingTimePlatter.hidden = YES;
				self.remainingTimePlatter.transform = CGAffineTransformIdentity;
			}
		}];
	}
}

%new
- (void)_configureRemainingTimePlatterConstraints {
	if (!self.remainingTimePlatter) return;
	static const CGFloat kPlatterHeight = 60.0;
	BOOL isLandscape = CGRectGetWidth(self.bounds) > CGRectGetHeight(self.bounds);
	CGFloat platterWidth = MAX(180.0, MIN(280.0, self.bounds.size.width * 0.45));
	CGFloat defaultBottomOffset = TTShouldHideQuickActionButtonsNow() ? -28.0 : -76.0;
	CGFloat defaultCenterXOffset = 0.0;

	CGRect flashRect = CGRectZero;
	CGRect cameraRect = CGRectZero;
	if (TTQuickActionButtonFramesInView(self, &flashRect, &cameraRect)) {
		CGFloat targetCenterY = (CGRectGetMidY(flashRect) + CGRectGetMidY(cameraRect)) * 0.5;
		CGFloat safeBottomY = CGRectGetHeight(self.bounds) - self.safeAreaInsets.bottom;
		defaultBottomOffset = (targetCenterY + (kPlatterHeight * 0.5)) - safeBottomY;
		CGFloat targetCenterX = (CGRectGetMidX(flashRect) + CGRectGetMidX(cameraRect)) * 0.5;
		defaultCenterXOffset = targetCenterX - CGRectGetMidX(self.bounds);

		CGFloat innerGap = CGRectGetMinX(cameraRect) - CGRectGetMaxX(flashRect);
		if (innerGap > 0) {
			CGFloat targetWidth = innerGap - 12.0;
			platterWidth = MAX(136.0, MIN(220.0, targetWidth));
		}
	}

	CGFloat safeMinX = self.safeAreaInsets.left + (platterWidth * 0.5);
	CGFloat safeMaxX = CGRectGetWidth(self.bounds) - self.safeAreaInsets.right - (platterWidth * 0.5);
	CGFloat safeMinY = self.safeAreaInsets.top + (kPlatterHeight * 0.5) + 8.0;
	CGFloat safeMaxY = CGRectGetHeight(self.bounds) - self.safeAreaInsets.bottom - (kPlatterHeight * 0.5) - 8.0;
	if (safeMaxX < safeMinX) safeMaxX = safeMinX;
	if (safeMaxY < safeMinY) safeMaxY = safeMinY;

	CGFloat defaultCenterX = CGRectGetMidX(self.bounds) + defaultCenterXOffset;
	CGFloat safeBottomY = CGRectGetHeight(self.bounds) - self.safeAreaInsets.bottom;
	CGFloat defaultCenterY = safeBottomY + defaultBottomOffset - (kPlatterHeight * 0.5);
	if (isLandscape) {
		UIView *dateContainer = TTFindDateViewContainer(self);
		if (dateContainer) {
			CGRect dateRect = [dateContainer.superview convertRect:dateContainer.frame toView:self];
			if (!CGRectIsEmpty(dateRect)) {
				defaultCenterX = CGRectGetMidX(dateRect);
			}
		}
	}
	defaultCenterX = MAX(safeMinX, MIN(safeMaxX, defaultCenterX));
	defaultCenterY = MAX(safeMinY, MIN(safeMaxY, defaultCenterY));

	if (!isLandscape && !platterHasCustomPosition && ![objc_getAssociatedObject(self, kTTPlatterDefaultCenterComputedPortraitKey) boolValue]) {
		platterPosXNorm = defaultCenterX / MAX(1.0, CGRectGetWidth(self.bounds));
		platterPosYNorm = defaultCenterY / MAX(1.0, CGRectGetHeight(self.bounds));
		objc_setAssociatedObject(self, kTTPlatterDefaultCenterComputedPortraitKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	if (isLandscape && !platterHasCustomPositionLandscape && ![objc_getAssociatedObject(self, kTTPlatterDefaultCenterComputedLandscapeKey) boolValue]) {
		platterPosXNormLandscape = defaultCenterX / MAX(1.0, CGRectGetWidth(self.bounds));
		platterPosYNormLandscape = defaultCenterY / MAX(1.0, CGRectGetHeight(self.bounds));
		objc_setAssociatedObject(self, kTTPlatterDefaultCenterComputedLandscapeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	BOOL hasCustomForOrientation = isLandscape ? platterHasCustomPositionLandscape : platterHasCustomPosition;
	CGFloat savedX = isLandscape ? platterPosXNormLandscape : platterPosXNorm;
	CGFloat savedY = isLandscape ? platterPosYNormLandscape : platterPosYNorm;
	CGFloat centerX = hasCustomForOrientation ? (savedX * CGRectGetWidth(self.bounds)) : defaultCenterX;
	CGFloat centerY = hasCustomForOrientation ? (savedY * CGRectGetHeight(self.bounds)) : defaultCenterY;
	centerX = MAX(safeMinX, MIN(safeMaxX, centerX));
	centerY = MAX(safeMinY, MIN(safeMaxY, centerY));

	CGFloat centerXOffset = centerX - CGRectGetMidX(self.bounds);
	CGFloat centerYOffset = centerY - CGRectGetMidY(self.bounds);
	BOOL dragging = [objc_getAssociatedObject(self, kTTPlatterDraggingKey) boolValue];

	if (!TTConstraintsInstalled(self)) {
		NSLayoutConstraint *width = [self.remainingTimePlatter.widthAnchor constraintEqualToConstant:platterWidth];
		NSLayoutConstraint *height = [self.remainingTimePlatter.heightAnchor constraintEqualToConstant:kPlatterHeight];
		NSLayoutConstraint *centerX = [self.remainingTimePlatter.centerXAnchor constraintEqualToAnchor:self.centerXAnchor constant:centerXOffset];
		NSLayoutConstraint *centerY = [self.remainingTimePlatter.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:centerYOffset];
		TTSetConstraint(self, kTTPlatterWidthConstraintKey, width);
		TTSetConstraint(self, kTTPlatterHeightConstraintKey, height);
		TTSetConstraint(self, kTTPlatterCenterXConstraintKey, centerX);
		TTSetConstraint(self, kTTPlatterCenterYConstraintKey, centerY);
		[NSLayoutConstraint activateConstraints:@[width, height, centerX, centerY]];
		TTSetConstraintsInstalled(self, YES);
	} else {
		TTGetConstraint(self, kTTPlatterWidthConstraintKey).constant = platterWidth;
		if (!dragging) {
			TTGetConstraint(self, kTTPlatterCenterXConstraintKey).constant = centerXOffset;
			TTGetConstraint(self, kTTPlatterCenterYConstraintKey).constant = centerYOffset;
		}
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
	TTLoadPreferences();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, TTPrefsDidChange, (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, TTNCPreviewRequestReceived, (__bridge CFStringRef)kJikanOpenNCPreviewNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

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

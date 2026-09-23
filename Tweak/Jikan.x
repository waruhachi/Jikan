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
static NSString *_tt100CurrentChargerIdentity = nil;
static BOOL _tt100CurrentIsWireless = NO;
static const void *kTTPlatterWidthConstraintKey = &kTTPlatterWidthConstraintKey;
static const void *kTTPlatterHeightConstraintKey = &kTTPlatterHeightConstraintKey;
static const void *kTTPlatterCenterXConstraintKey = &kTTPlatterCenterXConstraintKey;
static const void *kTTPlatterConstraintsInstalledKey = &kTTPlatterConstraintsInstalledKey;
static const void *kTTPlatterStyleCapturedKey = &kTTPlatterStyleCapturedKey;
static const void *kTTCoverSheetObserverInstalledKey = &kTTCoverSheetObserverInstalledKey;
static const void *kTTPlatterCenterYConstraintKey = &kTTPlatterCenterYConstraintKey;
static const void *kTTPlatterLongPressKey = &kTTPlatterLongPressKey;
static const void *kTTPlatterDragStartCenterKey = &kTTPlatterDragStartCenterKey;
static const void *kTTPlatterDragStartTouchKey = &kTTPlatterDragStartTouchKey;
static const void *kTTPlatterDefaultCenterComputedPortraitKey = &kTTPlatterDefaultCenterComputedPortraitKey;
static const void *kTTPlatterDefaultCenterComputedLandscapeKey = &kTTPlatterDefaultCenterComputedLandscapeKey;
static const void *kTTPlatterDraggingKey = &kTTPlatterDraggingKey;
static const void *kTTQuickActionOriginalHiddenKey = &kTTQuickActionOriginalHiddenKey;
static const void *kTTQuickActionHiddenByJikanKey = &kTTQuickActionHiddenByJikanKey;
static CFAbsoluteTime _ttLastNCPreviewTriggerTime = 0;
static BOOL _ttPreviewSessionActive = NO;
static BOOL _ttMonitoringEnabled = NO;
static NSDictionary *_ttLatestSnapshot;
static const void *kTTQuickActionInternalHiddenWriteKey = &kTTQuickActionInternalHiddenWriteKey;
static void TTApplyEnabledState(void);

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
	platterPosXNorm = isfinite(platterPosXNorm) ? MAX(0.05, MIN(0.95, platterPosXNorm)) : 0.5;
	platterPosYNorm = isfinite(platterPosYNorm) ? MAX(0.05, MIN(0.95, platterPosYNorm)) : 0.84;
	platterPosXNormLandscape = isfinite(platterPosXNormLandscape) ? MAX(0.05, MIN(0.95, platterPosXNormLandscape)) : 0.5;
	platterPosYNormLandscape = isfinite(platterPosYNormLandscape) ? MAX(0.05, MIN(0.95, platterPosYNormLandscape)) : 0.84;

	id px = [preferences objectForKey:@"pillPosXPortraitPercent"];
	id py = [preferences objectForKey:@"pillPosYPortraitPercent"];
	if (px || py) {
		platterPosXNorm = TTPercentToNorm(px, platterPosXNorm);
		platterPosYNorm = TTPercentToNorm(py, platterPosYNorm);
		platterPosXNorm = isfinite(platterPosXNorm) ? MAX(0.05, MIN(0.95, platterPosXNorm)) : 0.5;
		platterPosYNorm = isfinite(platterPosYNorm) ? MAX(0.05, MIN(0.95, platterPosYNorm)) : 0.84;
		platterHasCustomPosition = YES;
	}

	id lx = [preferences objectForKey:@"pillPosXLandscapePercent"];
	id ly = [preferences objectForKey:@"pillPosYLandscapePercent"];
	if (lx || ly) {
		platterPosXNormLandscape = TTPercentToNorm(lx, platterPosXNormLandscape);
		platterPosYNormLandscape = TTPercentToNorm(ly, platterPosYNormLandscape);
		platterPosXNormLandscape = isfinite(platterPosXNormLandscape) ? MAX(0.05, MIN(0.95, platterPosXNormLandscape)) : 0.5;
		platterPosYNormLandscape = isfinite(platterPosYNormLandscape) ? MAX(0.05, MIN(0.95, platterPosYNormLandscape)) : 0.84;
		platterHasCustomPositionLandscape = YES;
	}
}

static void TTPrefsDidChange(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
#pragma unused(center, observer, name, object, userInfo)
	dispatch_async(dispatch_get_main_queue(), ^{
		TTLoadPreferences();
		TTApplyEnabledState();
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

static id TTObjectForSelector(id target, NSString *selectorName) {
	if (!target || selectorName.length == 0) return nil;
	SEL selector = NSSelectorFromString(selectorName);
	if (!selector || ![target respondsToSelector:selector]) return nil;

	@try {
		NSMethodSignature *signature = [target methodSignatureForSelector:selector];
		if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
		return ((id (*)(id, SEL))objc_msgSend)(target, selector);
	}
	@catch (__unused NSException *exception) {
		return nil;
	}
}

static UIView *TTViewForSelector(id target, NSString *selectorName) {
	id object = TTObjectForSelector(target, selectorName);
	return [object isKindOfClass:[UIView class]] ? (UIView *)object : nil;
}

static BOOL TTResolveQuickActionButtons(CSQuickActionsView *quickActions, UIView **leadingOut, UIView **trailingOut) {
	if (leadingOut) *leadingOut = nil;
	if (trailingOut) *trailingOut = nil;
	if (!quickActions) return NO;

	UIView *leading = nil;
	UIView *trailing = nil;
	id container = TTObjectForSelector(quickActions, @"buttonContainerView");
	if (container) {
		leading = TTViewForSelector(container, @"leadingButton");
		trailing = TTViewForSelector(container, @"trailingButton");
	}

	if (!leading) leading = TTViewForSelector(quickActions, @"flashlightButton");
	if (!trailing) trailing = TTViewForSelector(quickActions, @"cameraButton");

	if (!leading || !trailing) {
		id buttonsObject = TTObjectForSelector(quickActions, @"buttons");
		if ([buttonsObject isKindOfClass:[NSArray class]]) {
			NSMutableArray<UIView *> *buttonViews = [NSMutableArray array];
			for (id object in (NSArray *)buttonsObject) {
				if (![object isKindOfClass:[UIView class]]) continue;
				UIView *view = (UIView *)object;
				if (![view isDescendantOfView:quickActions]) continue;
				if (![buttonViews containsObject:view]) [buttonViews addObject:view];
			}

			[buttonViews sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
				CGRect aRect = [a convertRect:a.bounds toView:quickActions];
				CGRect bRect = [b convertRect:b.bounds toView:quickActions];
				CGFloat aX = CGRectGetMidX(aRect);
				CGFloat bX = CGRectGetMidX(bRect);
				if (aX < bX) return NSOrderedAscending;
				if (aX > bX) return NSOrderedDescending;
				return NSOrderedSame;
			}];

			for (UIView *view in buttonViews) {
				if (!leading && view != trailing) leading = view;
			}
			for (UIView *view in buttonViews.reverseObjectEnumerator) {
				if (!trailing && view != leading) trailing = view;
			}
		}
	}
	if (leading == trailing) trailing = nil;

	if (leadingOut) *leadingOut = leading;
	if (trailingOut) *trailingOut = trailing;
	return leading || trailing;
}

static void TTSetQuickActionControlHidden(UIView *control, BOOL shouldHide) {
	if (!control) return;
	BOOL hiddenByJikan = [objc_getAssociatedObject(control, kTTQuickActionHiddenByJikanKey) boolValue];

	if (shouldHide) {
		if (!hiddenByJikan) {
			objc_setAssociatedObject(control, kTTQuickActionOriginalHiddenKey, @(control.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			objc_setAssociatedObject(control, kTTQuickActionHiddenByJikanKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		objc_setAssociatedObject(control, kTTQuickActionInternalHiddenWriteKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		control.hidden = YES;
		objc_setAssociatedObject(control, kTTQuickActionInternalHiddenWriteKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	if (!hiddenByJikan) return;
	NSNumber *originalHidden = (NSNumber *)objc_getAssociatedObject(control, kTTQuickActionOriginalHiddenKey);
	objc_setAssociatedObject(control, kTTQuickActionOriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(control, kTTQuickActionHiddenByJikanKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	if (originalHidden) control.hidden = originalHidden.boolValue;
}

static void TTSetQuickActionButtonsHidden(CSQuickActionsView *quickActions, BOOL shouldHide) {
	UIView *leading = nil;
	UIView *trailing = nil;
	if (!TTResolveQuickActionButtons(quickActions, &leading, &trailing)) return;

	TTSetQuickActionControlHidden(leading, shouldHide);
	if (trailing && trailing != leading) TTSetQuickActionControlHidden(trailing, shouldHide);
}

static BOOL TTQuickActionButtonFramesInView(CSCoverSheetView *coverSheet, CGRect *leadingRectOut, CGRect *trailingRectOut) {
	CSQuickActionsView *quickActions = TTFindQuickActionsView(coverSheet);
	UIView *leading = nil;
	UIView *trailing = nil;
	if (!TTResolveQuickActionButtons(quickActions, &leading, &trailing) || !leading || !trailing) return NO;
	if (![leading isDescendantOfView:coverSheet] || ![trailing isDescendantOfView:coverSheet]) return NO;

	CGRect leadingRect = [leading convertRect:leading.bounds toView:coverSheet];
	CGRect trailingRect = [trailing convertRect:trailing.bounds toView:coverSheet];
	if (CGRectIsEmpty(leadingRect) || CGRectIsEmpty(trailingRect)) return NO;
	if (!isfinite(leadingRect.origin.x) || !isfinite(leadingRect.origin.y) || !isfinite(leadingRect.size.width) || !isfinite(leadingRect.size.height) ||
		!isfinite(trailingRect.origin.x) || !isfinite(trailingRect.origin.y) || !isfinite(trailingRect.size.width) || !isfinite(trailingRect.size.height)) return NO;
	if (CGRectGetMidX(leadingRect) > CGRectGetMidX(trailingRect)) {
		CGRect swap = leadingRect;
		leadingRect = trailingRect;
		trailingRect = swap;
	}
	if (leadingRectOut) *leadingRectOut = leadingRect;
	if (trailingRectOut) *trailingRectOut = trailingRect;
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
	UIView *leading = nil;
	UIView *trailing = nil;
	TTResolveQuickActionButtons(quickActions, &leading, &trailing);
	NSMutableArray<UIView *> *candidates = [NSMutableArray array];
	if (leading) [candidates addObject:leading];
	if (trailing && trailing != leading) [candidates addObject:trailing];
	for (UIView *button in candidates) {
		if (!button) continue;
		UIView *backgroundEffectView = TTViewForSelector(button, @"backgroundEffectView");
		UIView *backgroundView = TTViewForSelector(button, @"backgroundView");

		NSMutableArray<UIView *> *buttonStack = [NSMutableArray arrayWithObject:button];
		if (backgroundView) [buttonStack addObject:backgroundView];
		if (backgroundEffectView) [buttonStack addObject:backgroundEffectView];
		while (buttonStack.count) {
			UIView *v = buttonStack.lastObject;
			[buttonStack removeLastObject];
			if ([v isKindOfClass:[UIVisualEffectView class]] && ((UIVisualEffectView *)v).effect) return v;
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
	UIView *leading = nil;
	UIView *trailing = nil;
	TTResolveQuickActionButtons(quickActions, &leading, &trailing);
	UIView *referenceButton = leading ?: trailing;

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

	[coverSheet.remainingTimePlatter applyQuickActionBackgroundStyleFromView:sourceMaterialView];
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
		_tt100CurrentChargerIdentity = [[TT100 chargerIdentityWithBatteryInfo:batteryInfo] copy];
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
	NSInteger soc = _tt100LastSOC;
	if (pctMax && pctCurr && pctMax.intValue > 0) soc = (NSInteger)lrint((pctCurr.doubleValue / pctMax.doubleValue) * 100.0);
	[[TT100Database shared] endSessionId:_tt100CurrentSessionId endSOC:MAX(0, MIN(100, soc))];

	if (_tt100Durations.count) {
		NSString *cls = _tt100CurrentChargerClass.length ? _tt100CurrentChargerClass : @"unknown";
		[[TT100Database shared] updatePercentStatsForChargerClass:cls withDurationsSec:_tt100Durations];
	}
	_tt100Durations = [NSMutableDictionary new];
	_tt100CurrentSessionId = -1;
	_tt100LastSOC = -1;
	_tt100LastSOCTime = 0;
	_tt100CurrentChargerClass = nil;
	_tt100CurrentChargerIdentity = nil;
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
	if (soc < _tt100LastSOC) {
		_tt100LastSOC = soc;
		_tt100LastSOCTime = CFAbsoluteTimeGetCurrent();
		return;
	}
	if (soc == _tt100LastSOC) return;
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
	if (_tt100Durations.count) {
		[[TT100Database shared] updatePercentStatsForChargerClass:_tt100CurrentChargerClass ?: @"unknown" withDurationsSec:_tt100Durations];
		[_tt100Durations removeAllObjects];
	}
	_tt100LastSOC = soc;
	_tt100LastSOCTime = now;
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
		TT100SessionMaybeEnd(_ttLatestSnapshot[@"batteryInfo"]);
		_ttLatestSnapshot = nil;
		_ttPreviewSessionActive = NO;
		isCharging = NO;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:JikanChargingStateChangedNotification object:nil userInfo:@{@"isCharging": @(isCharging)}];
}

%group JikanQuickActionVisibility
%hook JikanQuickActionControl
- (void)setHidden:(BOOL)hidden {
	if ([objc_getAssociatedObject(self, kTTQuickActionHiddenByJikanKey) boolValue] && ![objc_getAssociatedObject(self, kTTQuickActionInternalHiddenWriteKey) boolValue]) {
		objc_setAssociatedObject(self, kTTQuickActionOriginalHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		hidden = YES;
	}
	%orig(hidden);
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
	TTSetQuickActionButtonsHidden(self, NO);
	%orig;
	BOOL shouldHide = TTShouldHideQuickActionButtonsNow();
	TTSetQuickActionButtonsHidden(self, shouldHide);
}

%end

%hook CSCoverSheetView
%property(nonatomic, strong) JikanPlatterView *remainingTimePlatter;

- (void)didMoveToWindow {
	%orig;

	BOOL installed = [objc_getAssociatedObject(self, kTTCoverSheetObserverInstalledKey) boolValue];
	if (self.window) {
		TTSetPlatterStyleCaptured(self, NO);
		if (!installed) {
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_jikanChargingStateChanged:) name:JikanChargingStateChangedNotification object:nil];
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_jikanChargingStateChanged:) name:TT100BatteryInfoUpdatedNotification object:nil];
			objc_setAssociatedObject(self, kTTCoverSheetObserverInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		if (enabled) [[TT100 sharedInstance] _refreshBatteryInfo];
		[self _jikanChargingStateChanged:nil];
	} else {
		_ttPreviewSessionActive = NO;
		if (self.remainingTimePlatter) {
			[self.remainingTimePlatter setPreviewMode:NO];
		}
		if (installed) {
			[[NSNotificationCenter defaultCenter] removeObserver:self name:JikanChargingStateChangedNotification object:nil];
			[[NSNotificationCenter defaultCenter] removeObserver:self name:TT100BatteryInfoUpdatedNotification object:nil];
			objc_setAssociatedObject(self, kTTCoverSheetObserverInstalledKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
		TTSetQuickActionButtonsHidden(quickActions, shouldHide);
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
	if (!enabled) {
		[self.remainingTimePlatter enterEditMode:NO];
		[self.remainingTimePlatter setPreviewMode:NO];
		[self _setRemainingTimePlatterVisible:NO];
		return;
	}
	if (!self.remainingTimePlatter) {
		self.remainingTimePlatter = [[JikanPlatterView alloc] init];
		self.remainingTimePlatter.hidden = YES;
		self.remainingTimePlatter.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:self.remainingTimePlatter];
		[self.remainingTimePlatter setupConstraints];
		UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_jikanHandlePlatterLongPress:)];
		longPress.minimumPressDuration = 0.35;
		[self.remainingTimePlatter addGestureRecognizer:longPress];
		objc_setAssociatedObject(self, kTTPlatterLongPressKey, longPress, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	TTApplyQuickActionStyleIfPossible(self);

	BOOL hasEstimate = [_ttLatestSnapshot[@"hasEstimate"] boolValue];
	BOOL fullyCharged = [_ttLatestSnapshot[@"targetReached"] boolValue];
	[self.remainingTimePlatter applyBatterySnapshot:_ttLatestSnapshot];
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
	if (UIAccessibilityIsReduceMotionEnabled() || !enabled) {
		self.remainingTimePlatter.hidden = !visible;
		self.remainingTimePlatter.alpha = visible ? 1.0 : 0.0;
		self.remainingTimePlatter.transform = CGAffineTransformIdentity;
		return;
	}

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
	CGFloat kPlatterHeight = MAX(60.0, MIN(100.0, [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledValueForValue:60.0]));
	BOOL isLandscape = CGRectGetWidth(self.bounds) > CGRectGetHeight(self.bounds);
	CGFloat platterWidth = MAX(180.0, MIN(280.0, self.bounds.size.width * 0.45));
	CGFloat defaultBottomOffset = TTShouldHideQuickActionButtonsNow() ? -28.0 : -76.0;
	CGFloat defaultCenterXOffset = 0.0;

	CGRect leadingRect = CGRectZero;
	CGRect trailingRect = CGRectZero;
	if (TTQuickActionButtonFramesInView(self, &leadingRect, &trailingRect)) {
		CGFloat targetCenterY = (CGRectGetMidY(leadingRect) + CGRectGetMidY(trailingRect)) * 0.5;
		CGFloat safeBottomY = CGRectGetHeight(self.bounds) - self.safeAreaInsets.bottom;
		defaultBottomOffset = (targetCenterY + (kPlatterHeight * 0.5)) - safeBottomY;
		CGFloat targetCenterX = (CGRectGetMidX(leadingRect) + CGRectGetMidX(trailingRect)) * 0.5;
		defaultCenterXOffset = targetCenterX - CGRectGetMidX(self.bounds);

		CGFloat innerGap = CGRectGetMinX(trailingRect) - CGRectGetMaxX(leadingRect);
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
		TTGetConstraint(self, kTTPlatterHeightConstraintKey).constant = kPlatterHeight;
		if (!dragging) {
			TTGetConstraint(self, kTTPlatterCenterXConstraintKey).constant = centerXOffset;
			TTGetConstraint(self, kTTPlatterCenterYConstraintKey).constant = centerYOffset;
		}
	}
}

%end

%hook CSCoverSheetViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	UIView *view = self.view;
	if ([view isKindOfClass:NSClassFromString(@"CSCoverSheetView")]) {
		CSCoverSheetView *coverSheet = (CSCoverSheetView *)view;
		if (enabled) [[TT100 sharedInstance] _refreshBatteryInfo];
		[coverSheet _jikanChargingStateChanged:nil];
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
	%init;
	Class quickButtonClass = NSClassFromString(@"CSQuickActionsButton");
	Class prominentClass = NSClassFromString(@"CSProminentButtonControl");
	Class visibilityClass = prominentClass && [quickButtonClass isSubclassOfClass:prominentClass] ? prominentClass : quickButtonClass;
	if (visibilityClass) {
		%init(JikanQuickActionVisibility, JikanQuickActionControl = visibilityClass);
	}
	TTLoadPreferences();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, TTPrefsDidChange, (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, TTNCPreviewRequestReceived, (__bridge CFStringRef)kJikanOpenNCPreviewNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	[[NSNotificationCenter defaultCenter] addObserverForName:TT100InternalDidRefreshBatteryInfoNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
		if (!enabled) return;
		_ttLatestSnapshot = [note.userInfo copy];
		NSDictionary *batteryInfo = _ttLatestSnapshot[@"batteryInfo"];
		if (!batteryInfo.count) return;
		BOOL wasCharging = isCharging;
		isCharging = TTInferChargingStateFromBatteryInfo(batteryInfo);
		if (isCharging) {
			NSString *chargerIdentity = _ttLatestSnapshot[@"chargerIdentity"];
			if (_tt100CurrentSessionId >= 0 && ![_tt100CurrentChargerIdentity isEqualToString:chargerIdentity]) TT100SessionMaybeEnd(batteryInfo);
			TT100SessionMaybeStart(batteryInfo);
			BOOL paused = [batteryInfo[@"IsCharging"] respondsToSelector:@selector(boolValue)] && ![batteryInfo[@"IsCharging"] boolValue];
			if (paused) {
				_tt100LastSOC = [_ttLatestSnapshot[@"displayPercent"] integerValue];
				_tt100LastSOCTime = CFAbsoluteTimeGetCurrent();
			} else
				TT100RecordTicksIfNeeded(batteryInfo);
		} else {
			TT100SessionMaybeEnd(batteryInfo);
		}
		if (wasCharging != isCharging) [[NSNotificationCenter defaultCenter] postNotificationName:JikanChargingStateChangedNotification object:nil userInfo:@{@"isCharging": @(isCharging)}];
	}];
	dispatch_async(dispatch_get_main_queue(), ^{ TTApplyEnabledState(); });
}

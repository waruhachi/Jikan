#import "Jikan.h"

BOOL isCharging = NO;
static JikanSessionRecorder *_ttSessionRecorder;
static const void *kTTPlatterWidthConstraintKey = &kTTPlatterWidthConstraintKey;
static const void *kTTPlatterHeightConstraintKey = &kTTPlatterHeightConstraintKey;
static const void *kTTPlatterCenterXConstraintKey = &kTTPlatterCenterXConstraintKey;
static const void *kTTPlatterConstraintsInstalledKey = &kTTPlatterConstraintsInstalledKey;
static const void *kTTCoverSheetObserverInstalledKey = &kTTCoverSheetObserverInstalledKey;
static const void *kTTPlatterCenterYConstraintKey = &kTTPlatterCenterYConstraintKey;
static const void *kTTPlatterLongPressKey = &kTTPlatterLongPressKey;
static const void *kTTPlatterDragStartCenterKey = &kTTPlatterDragStartCenterKey;
static const void *kTTPlatterDragStartTouchKey = &kTTPlatterDragStartTouchKey;
static const void *kTTPlatterDefaultCenterComputedPortraitKey = &kTTPlatterDefaultCenterComputedPortraitKey;
static const void *kTTPlatterDefaultCenterComputedLandscapeKey = &kTTPlatterDefaultCenterComputedLandscapeKey;
static const void *kTTPlatterDraggingKey = &kTTPlatterDraggingKey;
static CFAbsoluteTime _ttLastNCPreviewTriggerTime = 0;
static BOOL _ttPreviewSessionActive = NO;
static BOOL _ttMonitoringEnabled = NO;
static NSDictionary *_ttLatestSnapshot;
static void TTApplyEnabledState(void);
static const void *kTTQuickActionAdapterKey = &kTTQuickActionAdapterKey;

static JikanQuickActionAdapter *TTQuickActionAdapter(UIView *view) {
	JikanQuickActionAdapter *adapter = objc_getAssociatedObject(view, kTTQuickActionAdapterKey);
	if (!adapter) {
		adapter = [[JikanQuickActionAdapter alloc] initWithRootView:view];
		objc_setAssociatedObject(view, kTTQuickActionAdapterKey, adapter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	return adapter;
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

static CGRect TTPlatterViewport(UIView *host) {
	// A stable content coordinate system must travel with the Cover Sheet.
	// Intersecting with the window during dismissal pins/clamps the pill to
	// the screen instead. The root fallback can be two screens tall on iOS 26.
	CGRect rect = host.bounds;
	if (host.window) {
		rect.size.width = MIN(rect.size.width, CGRectGetWidth(host.window.bounds));
		rect.size.height = MIN(rect.size.height, CGRectGetHeight(host.window.bounds));
	}
	return rect;
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
%property(nonatomic, strong) JikanPlatterView *remainingTimePlatter;

- (void)didMoveToWindow {
	%orig;

	BOOL installed = [objc_getAssociatedObject(self, kTTCoverSheetObserverInstalledKey) boolValue];
	if (self.window) {
		[TTQuickActionAdapter(self) invalidateStyle];
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
	[TTQuickActionAdapter(self) setButtonsHidden:TTShouldHideQuickActionButtonsNow()];
	[self _configureRemainingTimePlatterConstraints];
	[self setNeedsLayout];
	[self layoutIfNeeded];
}

%new
- (void)_jikanHandlePlatterLongPress:(UILongPressGestureRecognizer *)gesture {
	if (!enabled || !self.remainingTimePlatter || self.remainingTimePlatter.hidden) return;
	JikanPlatterView *pill = self.remainingTimePlatter;
	UIView *host = pill.superview;
	CGPoint location = [gesture locationInView:host];
	CGRect viewport = TTPlatterViewport(host);
	BOOL isLandscape = CGRectGetWidth(viewport) > CGRectGetHeight(viewport);

	CGFloat halfW = CGRectGetWidth(pill.bounds) * 0.5;
	CGFloat halfH = CGRectGetHeight(pill.bounds) * 0.5;
	CGFloat minX = CGRectGetMinX(viewport) + host.safeAreaInsets.left + halfW;
	CGFloat maxX = CGRectGetMaxX(viewport) - host.safeAreaInsets.right - halfW;
	CGFloat minY = CGRectGetMinY(viewport) + host.safeAreaInsets.top + halfH + 8.0;
	CGFloat maxY = CGRectGetMaxY(viewport) - host.safeAreaInsets.bottom - halfH - 8.0;
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
			cx.constant = candidate.x - CGRectGetMidX(host.bounds);
			cy.constant = candidate.y - CGRectGetMidY(host.bounds);
			CGFloat nx = MAX(0.05, MIN(0.95, (candidate.x - CGRectGetMinX(viewport)) / MAX(1.0, CGRectGetWidth(viewport))));
			CGFloat ny = MAX(0.05, MIN(0.95, (candidate.y - CGRectGetMinY(viewport)) / MAX(1.0, CGRectGetHeight(viewport))));
			if (isLandscape) {
				platterPosXNormLandscape = nx;
				platterPosYNormLandscape = ny;
				platterHasCustomPositionLandscape = YES;
			} else {
				platterPosXNorm = nx;
				platterPosYNorm = ny;
				platterHasCustomPosition = YES;
			}
			[host layoutIfNeeded];
		}
		return;
	}

	if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
		[pill enterEditMode:NO];
		UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
		[gen impactOccurred];

		CGPoint center = CGPointMake(CGRectGetMidX(pill.frame), CGRectGetMidY(pill.frame));
		CGFloat nx = MAX(0.05, MIN(0.95, (center.x - CGRectGetMinX(viewport)) / MAX(1.0, CGRectGetWidth(viewport))));
		CGFloat ny = MAX(0.05, MIN(0.95, (center.y - CGRectGetMinY(viewport)) / MAX(1.0, CGRectGetHeight(viewport))));
		if (isLandscape) {
			platterPosXNormLandscape = nx;
			platterPosYNormLandscape = ny;
			platterHasCustomPositionLandscape = YES;
		} else {
			platterPosXNorm = nx;
			platterPosYNorm = ny;
			platterHasCustomPosition = YES;
		}

		NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
		JikanSavePillPosition(prefs, isLandscape, nx, ny);
		[prefs synchronize];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);

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
		[[TTQuickActionAdapter(self) platterHostView] addSubview:self.remainingTimePlatter];
		__weak CSCoverSheetView *weakSelf = self;
		self.remainingTimePlatter.contentSizeDidChange = ^{ [weakSelf setNeedsLayout]; };
		[self.remainingTimePlatter setupConstraints];
		UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_jikanHandlePlatterLongPress:)];
		longPress.minimumPressDuration = 0.35;
		[self.remainingTimePlatter addGestureRecognizer:longPress];
		objc_setAssociatedObject(self, kTTPlatterLongPressKey, longPress, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	[TTQuickActionAdapter(self) applyStyleToPlatter:self.remainingTimePlatter];

	BOOL hasEstimate = [_ttLatestSnapshot[@"hasEstimate"] boolValue];
	BOOL fullyCharged = [_ttLatestSnapshot[@"targetReached"] boolValue];
	[self.remainingTimePlatter applyBatterySnapshot:_ttLatestSnapshot];
	BOOL previewEnabled = _ttPreviewSessionActive;

	BOOL shouldShow = previewEnabled || (isCharging && (hasEstimate || (showAfterFullCharge && fullyCharged)));
	[self.remainingTimePlatter setPreviewMode:(previewEnabled && (!isCharging || (!hasEstimate && !(showAfterFullCharge && fullyCharged))))];

	UILongPressGestureRecognizer *lp = (UILongPressGestureRecognizer *)objc_getAssociatedObject(self, kTTPlatterLongPressKey);
	lp.enabled = shouldShow;

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
	UIView *host = [TTQuickActionAdapter(self) platterHostView];
	if (self.remainingTimePlatter.superview != host) {
		if (TTConstraintsInstalled(self)) {
			[NSLayoutConstraint deactivateConstraints:@[TTGetConstraint(self, kTTPlatterWidthConstraintKey), TTGetConstraint(self, kTTPlatterHeightConstraintKey), TTGetConstraint(self, kTTPlatterCenterXConstraintKey), TTGetConstraint(self, kTTPlatterCenterYConstraintKey)]];
			TTSetConstraintsInstalled(self, NO);
		}
		[self.remainingTimePlatter removeFromSuperview];
		[host addSubview:self.remainingTimePlatter];
		[TTQuickActionAdapter(self) invalidateStyle];
	}
	CGRect viewport = TTPlatterViewport(host);
	if (CGRectIsEmpty(viewport)) return;
	BOOL isLandscape = CGRectGetWidth(viewport) > CGRectGetHeight(viewport);
	BOOL hasCustomForOrientation = isLandscape ? platterHasCustomPositionLandscape : platterHasCustomPosition;
	CGFloat maximumWidth = MAX(64.0, CGRectGetWidth(viewport) - host.safeAreaInsets.left - host.safeAreaInsets.right - 24.0);
	CGFloat pillHeight = 60.0;
	CGRect leadingRect = CGRectZero;
	CGRect trailingRect = CGRectZero;
	BOOL hasButtons = [TTQuickActionAdapter(self) getButtonFramesInView:host leadingRect:&leadingRect trailingRect:&trailingRect];
	if (hasButtons) {
		CGFloat buttonHeight = MIN(CGRectGetHeight(leadingRect), CGRectGetHeight(trailingRect));
		if (@available(iOS 26.0, *)) pillHeight = MAX(60.0, buttonHeight);
		else
			pillHeight = MAX(44.0, MIN(60.0, buttonHeight));
		CGFloat innerGap = CGRectGetMinX(trailingRect) - CGRectGetMaxX(leadingRect) - 16.0;
		if (!hasCustomForOrientation && !TTShouldHideQuickActionButtonsNow() && innerGap >= 64.0) maximumWidth = MIN(maximumWidth, innerGap);
	}
	CGSize size = [self.remainingTimePlatter preferredSizeForMaximumWidth:maximumWidth height:pillHeight];
	CGFloat platterWidth = size.width;
	CGFloat kPlatterHeight = size.height;
	CGFloat defaultCenterX = hasButtons ? (CGRectGetMidX(leadingRect) + CGRectGetMidX(trailingRect)) * 0.5 : CGRectGetMidX(viewport);
	CGFloat safeBottomY = CGRectGetMaxY(viewport) - host.safeAreaInsets.bottom;
	CGFloat defaultCenterY = hasButtons ? (CGRectGetMidY(leadingRect) + CGRectGetMidY(trailingRect)) * 0.5 : safeBottomY - (TTShouldHideQuickActionButtonsNow() ? 28.0 : 76.0) - kPlatterHeight * 0.5;

	CGFloat safeMinX = CGRectGetMinX(viewport) + host.safeAreaInsets.left + (platterWidth * 0.5);
	CGFloat safeMaxX = CGRectGetMaxX(viewport) - host.safeAreaInsets.right - (platterWidth * 0.5);
	CGFloat safeMinY = CGRectGetMinY(viewport) + host.safeAreaInsets.top + (kPlatterHeight * 0.5) + 8.0;
	CGFloat safeMaxY = CGRectGetMaxY(viewport) - host.safeAreaInsets.bottom - (kPlatterHeight * 0.5) - 8.0;
	if (safeMaxX < safeMinX) safeMaxX = safeMinX;
	if (safeMaxY < safeMinY) safeMaxY = safeMinY;
	if (isLandscape) {
		UIView *dateContainer = TTFindDateViewContainer(self);
		if (dateContainer) {
			CGRect dateRect = [dateContainer.superview convertRect:dateContainer.frame toView:host];
			if (!CGRectIsEmpty(dateRect)) {
				defaultCenterX = CGRectGetMidX(dateRect);
			}
		}
	}
	defaultCenterX = MAX(safeMinX, MIN(safeMaxX, defaultCenterX));
	defaultCenterY = MAX(safeMinY, MIN(safeMaxY, defaultCenterY));

	if (!isLandscape && !platterHasCustomPosition && ![objc_getAssociatedObject(self, kTTPlatterDefaultCenterComputedPortraitKey) boolValue]) {
		platterPosXNorm = (defaultCenterX - CGRectGetMinX(viewport)) / MAX(1.0, CGRectGetWidth(viewport));
		platterPosYNorm = (defaultCenterY - CGRectGetMinY(viewport)) / MAX(1.0, CGRectGetHeight(viewport));
		objc_setAssociatedObject(self, kTTPlatterDefaultCenterComputedPortraitKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	if (isLandscape && !platterHasCustomPositionLandscape && ![objc_getAssociatedObject(self, kTTPlatterDefaultCenterComputedLandscapeKey) boolValue]) {
		platterPosXNormLandscape = (defaultCenterX - CGRectGetMinX(viewport)) / MAX(1.0, CGRectGetWidth(viewport));
		platterPosYNormLandscape = (defaultCenterY - CGRectGetMinY(viewport)) / MAX(1.0, CGRectGetHeight(viewport));
		objc_setAssociatedObject(self, kTTPlatterDefaultCenterComputedLandscapeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	CGFloat savedX = isLandscape ? platterPosXNormLandscape : platterPosXNorm;
	CGFloat savedY = isLandscape ? platterPosYNormLandscape : platterPosYNorm;
	CGFloat centerX = hasCustomForOrientation ? (CGRectGetMinX(viewport) + savedX * CGRectGetWidth(viewport)) : defaultCenterX;
	CGFloat centerY = hasCustomForOrientation ? (CGRectGetMinY(viewport) + savedY * CGRectGetHeight(viewport)) : defaultCenterY;
	centerX = MAX(safeMinX, MIN(safeMaxX, centerX));
	centerY = MAX(safeMinY, MIN(safeMaxY, centerY));

	CGFloat centerXOffset = centerX - CGRectGetMidX(host.bounds);
	CGFloat centerYOffset = centerY - CGRectGetMidY(host.bounds);
	BOOL dragging = [objc_getAssociatedObject(self, kTTPlatterDraggingKey) boolValue];

	if (!TTConstraintsInstalled(self)) {
		NSLayoutConstraint *width = [self.remainingTimePlatter.widthAnchor constraintEqualToConstant:platterWidth];
		NSLayoutConstraint *height = [self.remainingTimePlatter.heightAnchor constraintEqualToConstant:kPlatterHeight];
		NSLayoutConstraint *centerX = [self.remainingTimePlatter.centerXAnchor constraintEqualToAnchor:host.centerXAnchor constant:centerXOffset];
		NSLayoutConstraint *centerY = [self.remainingTimePlatter.centerYAnchor constraintEqualToAnchor:host.centerYAnchor constant:centerYOffset];
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

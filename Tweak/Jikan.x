#import "Jikan.h"

static JikanPresentationStore *_ttPresentationStore;
static JikanSessionRecorder *_ttSessionRecorder;
static CFAbsoluteTime _ttLastNCPreviewTriggerTime = 0;
static BOOL _ttMonitoringEnabled = NO;
static void TTApplyEnabledState(NSDictionary *lastBatteryInfo);

static const void *kTTCoverSheetCoordinatorKey = &kTTCoverSheetCoordinatorKey;

static JikanCoverSheetCoordinator *TTCoverSheetCoordinator(UIView *view) {
	JikanCoverSheetCoordinator *coordinator = objc_getAssociatedObject(view, kTTCoverSheetCoordinatorKey);
	if (!coordinator) {
		coordinator = [[JikanCoverSheetCoordinator alloc] initWithRootView:view presentationStore:_ttPresentationStore];
		objc_setAssociatedObject(view, kTTCoverSheetCoordinatorKey, coordinator, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	return coordinator;
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
		if (!_ttPresentationStore.state.settings.enabled) return;
		[_ttPresentationStore setPreviewActive:TTOpenNotificationCenterPreview()];
	});
}

static void TTEndPreviewSession(void) {
	[_ttPresentationStore setPreviewActive:NO];
}

static void TTPrefsDidChange(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
#pragma unused(center, observer, name, object, userInfo)
	dispatch_async(dispatch_get_main_queue(), ^{
		NSDictionary *lastBatteryInfo = _ttPresentationStore.state.snapshot.batteryInfo;
		[TT100 preferencesDidChange];
		TTApplyEnabledState(lastBatteryInfo);
	});
}

static void TTApplyEnabledState(NSDictionary *lastBatteryInfo) {
	if (_ttPresentationStore.state.settings.enabled) {
		if (!_ttMonitoringEnabled) {
			_ttMonitoringEnabled = YES;
			[TT100 startMonitoring];
		} else {
			[[TT100 sharedInstance] _refreshBatteryInfo];
		}
	} else {
		_ttMonitoringEnabled = NO;
		[_ttSessionRecorder finishWithBatteryInfo:lastBatteryInfo];
		[TT100 stopMonitoring];
	}
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
	if (_ttPresentationStore.state.settings.enabled) [[TT100 sharedInstance] _refreshBatteryInfo];
}
%end

%hook CSQuickActionsView

- (void)refreshSupportedButtons {
	[JikanQuickActionAdapter setButtonsInView:self hidden:NO];
	%orig;
	BOOL shouldHide = _ttPresentationStore.state.shouldHideQuickActionButtons;
	[JikanQuickActionAdapter setButtonsInView:self hidden:shouldHide];
}

%end

%hook CSCoverSheetView

- (void)didMoveToWindow {
	%orig;
	if (!self.window) [_ttPresentationStore setPreviewActive:NO];
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
		if (_ttPresentationStore.state.settings.enabled) [[TT100 sharedInstance] _refreshBatteryInfo];
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
	_ttPresentationStore = [JikanPresentationStore sharedInstance];
	_ttSessionRecorder = [JikanSessionRecorder new];
	%init;
	Class visibilityClass = [JikanQuickActionAdapter visibilityControlClass];
	if (visibilityClass) {
		%init(JikanQuickActionVisibility, JikanQuickActionControl = visibilityClass);
	}
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, TTPrefsDidChange, (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, TTNCPreviewRequestReceived, (__bridge CFStringRef)JikanPreviewRequestNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	[[NSNotificationCenter defaultCenter] addObserverForName:TT100InternalDidRefreshBatteryInfoNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
		if (!_ttPresentationStore.state.settings.enabled) return;
		NSDictionary *snapshot = note.userInfo;
		NSDictionary *batteryInfo = snapshot[@"batteryInfo"];
		if (!batteryInfo.count) return;
		[_ttSessionRecorder consumeSnapshot:snapshot charging:[snapshot[@"externalPowerConnected"] boolValue]];
	}];
	dispatch_async(dispatch_get_main_queue(), ^{ TTApplyEnabledState(nil); });
}

#import "JikanCoverSheetCoordinator.h"

@interface JikanCoverSheetCoordinator ()
@property (nonatomic, weak) UIView *rootView;
@property (nonatomic, strong) JikanQuickActionAdapter *quickActions;
@property (nonatomic, strong) JikanPlatterView *platter;
@property (nonatomic, copy) JikanCoverSheetConfiguration (^configurationProvider)(void);
@property (nonatomic, copy) NSDictionary * (^snapshotProvider)(void);
@property (nonatomic, copy) void (^positionChanged)(BOOL landscape, JikanPillPosition position);
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *centerXConstraint;
@property (nonatomic, strong) NSLayoutConstraint *centerYConstraint;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPress;
@property (nonatomic, strong) NSValue *dragStartCenter;
@property (nonatomic, strong) NSValue *dragStartTouch;
@property (nonatomic) BOOL constraintsInstalled;
@property (nonatomic) BOOL observersInstalled;
@property (nonatomic) BOOL defaultCenterComputedPortrait;
@property (nonatomic) BOOL defaultCenterComputedLandscape;
@property (nonatomic) BOOL dragging;
@end

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

static UIView *TTFindDateViewContainer(UIView *coverSheet) {
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

static BOOL TTShouldHideQuickActionButtons(JikanCoverSheetConfiguration configuration) {
	if (!configuration.enabled || !configuration.hideQuickActionButtons) return NO;
	if (!configuration.hideQuickActionButtonsOnlyWhenCharging) return YES;
	return configuration.charging;
}

@implementation JikanCoverSheetCoordinator

- (instancetype)initWithRootView:(UIView *)rootView
		   configurationProvider:(JikanCoverSheetConfiguration (^)(void))configurationProvider
				snapshotProvider:(NSDictionary * (^)(void))snapshotProvider
				 positionChanged:(void (^)(BOOL landscape, JikanPillPosition position))positionChanged {
	self = [super init];
	if (self) {
		_rootView = rootView;
		_quickActions = [[JikanQuickActionAdapter alloc] initWithRootView:rootView];
		_configurationProvider = [configurationProvider copy];
		_snapshotProvider = [snapshotProvider copy];
		_positionChanged = [positionChanged copy];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didMoveToWindow {
	JikanCoverSheetConfiguration configuration = self.configurationProvider();

	BOOL installed = self.observersInstalled;
	if (self.rootView.window) {
		[self.quickActions invalidateStyle];
		if (!installed) {
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chargingStateChanged:) name:JikanChargingStateChangedNotification object:nil];
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chargingStateChanged:) name:TT100BatteryInfoUpdatedNotification object:nil];
			self.observersInstalled = YES;
		}
		if (configuration.enabled) [[TT100 sharedInstance] _refreshBatteryInfo];
		[self refresh];
	} else {
		if (self.platter) {
			[self.platter setPreviewMode:NO];
		}
		if (installed) {
			[[NSNotificationCenter defaultCenter] removeObserver:self name:JikanChargingStateChangedNotification object:nil];
			[[NSNotificationCenter defaultCenter] removeObserver:self name:TT100BatteryInfoUpdatedNotification object:nil];
			self.observersInstalled = NO;
		}
	}
}

- (void)layoutSubviews {
	if (!self.platter) {
		[self updatePlatter];
	}
	[self configureConstraints];
}

- (void)chargingStateChanged:(NSNotification *)notification {
#pragma unused(notification)
	[self refresh];
}

- (void)refresh {
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self refresh];
		});
		return;
	}
	[self updatePlatter];
	JikanCoverSheetConfiguration configuration = self.configurationProvider();
	[self.quickActions setButtonsHidden:TTShouldHideQuickActionButtons(configuration)];
	[self configureConstraints];
	[self.rootView setNeedsLayout];
	[self.rootView layoutIfNeeded];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
	JikanCoverSheetConfiguration configuration = self.configurationProvider();
	if (!configuration.enabled || !self.platter || self.platter.hidden) return;
	JikanPlatterView *pill = self.platter;
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
		self.dragging = YES;
		JikanPillPosition position = isLandscape ? configuration.landscapePosition : configuration.portraitPosition;
		position.hasCustomPosition = YES;
		self.positionChanged(isLandscape, position);
		[pill enterEditMode:YES];
		UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
		[gen impactOccurred];

		CGPoint center = CGPointMake(CGRectGetMidX(pill.frame), CGRectGetMidY(pill.frame));
		self.dragStartCenter = [NSValue valueWithCGPoint:center];
		self.dragStartTouch = [NSValue valueWithCGPoint:location];
		return;
	}

	if (gesture.state == UIGestureRecognizerStateChanged) {
		NSValue *centerValue = self.dragStartCenter;
		NSValue *touchValue = self.dragStartTouch;
		if (!centerValue || !touchValue) return;

		CGPoint startCenter = centerValue.CGPointValue;
		CGPoint startTouch = touchValue.CGPointValue;
		CGPoint candidate = CGPointMake(startCenter.x + (location.x - startTouch.x), startCenter.y + (location.y - startTouch.y));
		if (configuration.lockPreviewXAxis) candidate.x = startCenter.x;
		if (configuration.lockPreviewYAxis) candidate.y = startCenter.y;
		candidate.x = MAX(minX, MIN(maxX, candidate.x));
		candidate.y = MAX(minY, MIN(maxY, candidate.y));

		NSLayoutConstraint *cx = self.centerXConstraint;
		NSLayoutConstraint *cy = self.centerYConstraint;
		if (cx && cy) {
			cx.constant = candidate.x - CGRectGetMidX(host.bounds);
			cy.constant = candidate.y - CGRectGetMidY(host.bounds);
			CGFloat nx = MAX(0.05, MIN(0.95, (candidate.x - CGRectGetMinX(viewport)) / MAX(1.0, CGRectGetWidth(viewport))));
			CGFloat ny = MAX(0.05, MIN(0.95, (candidate.y - CGRectGetMinY(viewport)) / MAX(1.0, CGRectGetHeight(viewport))));
			self.positionChanged(isLandscape, (JikanPillPosition){nx, ny, YES});
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
		self.positionChanged(isLandscape, (JikanPillPosition){nx, ny, YES});

		NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
		JikanSavePillPosition(prefs, isLandscape, nx, ny);
		[prefs synchronize];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);

		self.dragging = NO;
		self.dragStartCenter = nil;
		self.dragStartTouch = nil;
	}
}

- (void)updatePlatter {
	JikanCoverSheetConfiguration configuration = self.configurationProvider();
	NSDictionary *snapshot = self.snapshotProvider();
	if (!configuration.enabled) {
		[self.platter enterEditMode:NO];
		[self.platter setPreviewMode:NO];
		[self setPlatterVisible:NO];
		return;
	}
	if (!self.platter) {
		self.platter = [[JikanPlatterView alloc] init];
		self.platter.hidden = YES;
		self.platter.translatesAutoresizingMaskIntoConstraints = NO;
		[[self.quickActions platterHostView] addSubview:self.platter];
		__weak UIView *weakRootView = self.rootView;
		self.platter.contentSizeDidChange = ^{ [weakRootView setNeedsLayout]; };
		[self.platter setupConstraints];
		UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
		longPress.minimumPressDuration = 0.35;
		[self.platter addGestureRecognizer:longPress];
		self.longPress = longPress;
	}

	[self.quickActions applyStyleToPlatter:self.platter];

	BOOL hasEstimate = [snapshot[@"hasEstimate"] boolValue];
	BOOL fullyCharged = [snapshot[@"targetReached"] boolValue];
	[self.platter applyBatterySnapshot:snapshot];
	BOOL previewEnabled = configuration.previewActive;

	BOOL shouldShow = previewEnabled || (configuration.charging && (hasEstimate || (configuration.showAfterFullCharge && fullyCharged)));
	[self.platter setPreviewMode:(previewEnabled && (!configuration.charging || (!hasEstimate && !(configuration.showAfterFullCharge && fullyCharged))))];

	UILongPressGestureRecognizer *lp = self.longPress;
	lp.enabled = shouldShow;

	[self setPlatterVisible:shouldShow];
}

- (void)setPlatterVisible:(BOOL)visible {
	JikanCoverSheetConfiguration configuration = self.configurationProvider();
	if (!self.platter) return;

	BOOL currentlyVisible = !self.platter.hidden && self.platter.alpha > 0.01;
	if (visible == currentlyVisible) {
		if (visible && self.platter.alpha < 1.0) {
			self.platter.alpha = 1.0;
		}
		return;
	}

	[self.platter.layer removeAllAnimations];
	if (UIAccessibilityIsReduceMotionEnabled() || !configuration.enabled) {
		self.platter.hidden = !visible;
		self.platter.alpha = visible ? 1.0 : 0.0;
		self.platter.transform = CGAffineTransformIdentity;
		return;
	}

	NSTimeInterval showDuration = 0.42;
	NSTimeInterval hideDuration = 0.22;
	UIViewAnimationOptions showOptions = UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState;
	UIViewAnimationOptions hideOptions = UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState;

	if (visible) {
		self.platter.hidden = NO;
		self.platter.alpha = 0.0;
		self.platter.transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(0.965, 0.965), 0.0, 4.0);
		[UIView animateWithDuration:showDuration
							  delay:0
			 usingSpringWithDamping:0.88
			  initialSpringVelocity:0.35
							options:showOptions
						 animations:^{
							 self.platter.alpha = 1.0;
							 self.platter.transform = CGAffineTransformIdentity;
						 }
						 completion:nil];
	} else {
		[UIView animateWithDuration:hideDuration delay:0 options:hideOptions animations:^{
			self.platter.alpha = 0.0;
			self.platter.transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(0.975, 0.975), 0.0, 2.0);
		} completion:^(BOOL finished) {
			if (finished && self.platter.alpha <= 0.01) {
				self.platter.hidden = YES;
				self.platter.transform = CGAffineTransformIdentity;
			}
		}];
	}
}

- (void)configureConstraints {
	JikanCoverSheetConfiguration configuration = self.configurationProvider();
	if (!self.platter) return;
	UIView *host = [self.quickActions platterHostView];
	if (self.platter.superview != host) {
		if (self.constraintsInstalled) {
			[NSLayoutConstraint deactivateConstraints:@[self.widthConstraint, self.heightConstraint, self.centerXConstraint, self.centerYConstraint]];
			self.constraintsInstalled = NO;
		}
		[self.platter removeFromSuperview];
		[host addSubview:self.platter];
		[self.quickActions invalidateStyle];
	}
	CGRect viewport = TTPlatterViewport(host);
	if (CGRectIsEmpty(viewport)) return;
	BOOL isLandscape = CGRectGetWidth(viewport) > CGRectGetHeight(viewport);
	BOOL hasCustomForOrientation = isLandscape ? configuration.landscapePosition.hasCustomPosition : configuration.portraitPosition.hasCustomPosition;
	CGFloat maximumWidth = MAX(64.0, CGRectGetWidth(viewport) - host.safeAreaInsets.left - host.safeAreaInsets.right - 24.0);
	CGFloat pillHeight = 60.0;
	CGRect leadingRect = CGRectZero;
	CGRect trailingRect = CGRectZero;
	BOOL hasButtons = [self.quickActions getButtonFramesInView:host leadingRect:&leadingRect trailingRect:&trailingRect];
	if (hasButtons) {
		CGFloat buttonHeight = MIN(CGRectGetHeight(leadingRect), CGRectGetHeight(trailingRect));
		if (@available(iOS 26.0, *)) pillHeight = MAX(60.0, buttonHeight);
		else
			pillHeight = MAX(44.0, MIN(60.0, buttonHeight));
		CGFloat innerGap = CGRectGetMinX(trailingRect) - CGRectGetMaxX(leadingRect) - 16.0;
		if (!hasCustomForOrientation && !TTShouldHideQuickActionButtons(configuration) && innerGap >= 64.0) maximumWidth = MIN(maximumWidth, innerGap);
	}
	CGSize size = [self.platter preferredSizeForMaximumWidth:maximumWidth height:pillHeight];
	CGFloat platterWidth = size.width;
	CGFloat kPlatterHeight = size.height;
	CGFloat defaultCenterX = hasButtons ? (CGRectGetMidX(leadingRect) + CGRectGetMidX(trailingRect)) * 0.5 : CGRectGetMidX(viewport);
	CGFloat safeBottomY = CGRectGetMaxY(viewport) - host.safeAreaInsets.bottom;
	CGFloat defaultCenterY = hasButtons ? (CGRectGetMidY(leadingRect) + CGRectGetMidY(trailingRect)) * 0.5 : safeBottomY - (TTShouldHideQuickActionButtons(configuration) ? 28.0 : 76.0) - kPlatterHeight * 0.5;

	CGFloat safeMinX = CGRectGetMinX(viewport) + host.safeAreaInsets.left + (platterWidth * 0.5);
	CGFloat safeMaxX = CGRectGetMaxX(viewport) - host.safeAreaInsets.right - (platterWidth * 0.5);
	CGFloat safeMinY = CGRectGetMinY(viewport) + host.safeAreaInsets.top + (kPlatterHeight * 0.5) + 8.0;
	CGFloat safeMaxY = CGRectGetMaxY(viewport) - host.safeAreaInsets.bottom - (kPlatterHeight * 0.5) - 8.0;
	if (safeMaxX < safeMinX) safeMaxX = safeMinX;
	if (safeMaxY < safeMinY) safeMaxY = safeMinY;
	if (isLandscape) {
		UIView *dateContainer = TTFindDateViewContainer(self.rootView);
		if (dateContainer) {
			CGRect dateRect = [dateContainer.superview convertRect:dateContainer.frame toView:host];
			if (!CGRectIsEmpty(dateRect)) {
				defaultCenterX = CGRectGetMidX(dateRect);
			}
		}
	}
	defaultCenterX = MAX(safeMinX, MIN(safeMaxX, defaultCenterX));
	defaultCenterY = MAX(safeMinY, MIN(safeMaxY, defaultCenterY));

	if (!isLandscape && !configuration.portraitPosition.hasCustomPosition && !self.defaultCenterComputedPortrait) {
		configuration.portraitPosition.x = (defaultCenterX - CGRectGetMinX(viewport)) / MAX(1.0, CGRectGetWidth(viewport));
		configuration.portraitPosition.y = (defaultCenterY - CGRectGetMinY(viewport)) / MAX(1.0, CGRectGetHeight(viewport));
		self.positionChanged(NO, configuration.portraitPosition);
		self.defaultCenterComputedPortrait = YES;
	}
	if (isLandscape && !configuration.landscapePosition.hasCustomPosition && !self.defaultCenterComputedLandscape) {
		configuration.landscapePosition.x = (defaultCenterX - CGRectGetMinX(viewport)) / MAX(1.0, CGRectGetWidth(viewport));
		configuration.landscapePosition.y = (defaultCenterY - CGRectGetMinY(viewport)) / MAX(1.0, CGRectGetHeight(viewport));
		self.positionChanged(YES, configuration.landscapePosition);
		self.defaultCenterComputedLandscape = YES;
	}

	CGFloat savedX = isLandscape ? configuration.landscapePosition.x : configuration.portraitPosition.x;
	CGFloat savedY = isLandscape ? configuration.landscapePosition.y : configuration.portraitPosition.y;
	CGFloat centerX = hasCustomForOrientation ? (CGRectGetMinX(viewport) + savedX * CGRectGetWidth(viewport)) : defaultCenterX;
	CGFloat centerY = hasCustomForOrientation ? (CGRectGetMinY(viewport) + savedY * CGRectGetHeight(viewport)) : defaultCenterY;
	centerX = MAX(safeMinX, MIN(safeMaxX, centerX));
	centerY = MAX(safeMinY, MIN(safeMaxY, centerY));

	CGFloat centerXOffset = centerX - CGRectGetMidX(host.bounds);
	CGFloat centerYOffset = centerY - CGRectGetMidY(host.bounds);
	BOOL dragging = self.dragging;

	if (!self.constraintsInstalled) {
		NSLayoutConstraint *width = [self.platter.widthAnchor constraintEqualToConstant:platterWidth];
		NSLayoutConstraint *height = [self.platter.heightAnchor constraintEqualToConstant:kPlatterHeight];
		NSLayoutConstraint *centerX = [self.platter.centerXAnchor constraintEqualToAnchor:host.centerXAnchor constant:centerXOffset];
		NSLayoutConstraint *centerY = [self.platter.centerYAnchor constraintEqualToAnchor:host.centerYAnchor constant:centerYOffset];
		self.widthConstraint = width;
		self.heightConstraint = height;
		self.centerXConstraint = centerX;
		self.centerYConstraint = centerY;
		[NSLayoutConstraint activateConstraints:@[width, height, centerX, centerY]];
		self.constraintsInstalled = YES;
	} else {
		self.widthConstraint.constant = platterWidth;
		self.heightConstraint.constant = kPlatterHeight;
		if (!dragging) {
			self.centerXConstraint.constant = centerXOffset;
			self.centerYConstraint.constant = centerYOffset;
		}
	}
}

@end

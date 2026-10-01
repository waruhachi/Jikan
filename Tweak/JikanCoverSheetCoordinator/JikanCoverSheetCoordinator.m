#import "JikanCoverSheetCoordinator.h"

@interface JikanCoverSheetCoordinator ()
@property (nonatomic, weak) UIView *rootView;
@property (nonatomic, strong) JikanQuickActionAdapter *quickActions;
@property (nonatomic, strong) JikanPlatterView *platter;
@property (nonatomic, strong) JikanPresentationStore *presentationStore;
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

@implementation JikanCoverSheetCoordinator

- (instancetype)initWithRootView:(UIView *)rootView presentationStore:(JikanPresentationStore *)presentationStore {
	self = [super init];
	if (self) {
		_rootView = rootView;
		_quickActions = [[JikanQuickActionAdapter alloc] initWithRootView:rootView];
		_presentationStore = presentationStore;
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didMoveToWindow {
	JikanPresentationState *state = self.presentationStore.state;
	JikanPresentationSettings *settings = state.settings;

	BOOL installed = self.observersInstalled;
	if (self.rootView.window) {
		[self.quickActions invalidateStyle];
		if (!installed) {
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(presentationStateChanged:) name:JikanPresentationStateDidChangeNotification object:self.presentationStore];
			self.observersInstalled = YES;
		}
		if (settings.enabled) [[TT100 sharedInstance] _refreshBatteryInfo];
		[self refresh];
	} else {
		if (self.platter) {
			[self.platter setPreviewMode:NO];
		}
		if (installed) {
			[[NSNotificationCenter defaultCenter] removeObserver:self name:JikanPresentationStateDidChangeNotification object:self.presentationStore];
			self.observersInstalled = NO;
		}
	}
}

- (void)layoutSubviews {
	JikanPresentationState *state = self.presentationStore.state;
	if (!self.platter) {
		[self updatePlatterWithState:state];
	}
	[self configureConstraintsWithState:state];
}

- (void)presentationStateChanged:(NSNotification *)notification {
#pragma unused(notification)
	if (self.rootView.window) [self refresh];
}

- (void)refresh {
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self refresh];
		});
		return;
	}
	JikanPresentationState *state = self.presentationStore.state;
	[self updatePlatterWithState:state];
	[self.quickActions setButtonsHidden:state.shouldHideQuickActionButtons];
	[self configureConstraintsWithState:state];
	[self.rootView setNeedsLayout];
	[self.rootView layoutIfNeeded];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
	JikanPresentationState *state = self.presentationStore.state;
	JikanPresentationSettings *settings = state.settings;
	if (!settings.enabled || !self.platter || self.platter.hidden) return;
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
		JikanPillPosition position = isLandscape ? settings.landscapePosition : settings.portraitPosition;
		position.hasCustomPosition = YES;
		[self.presentationStore updatePosition:position landscape:isLandscape];
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
		if (settings.lockPreviewXAxis) candidate.x = startCenter.x;
		if (settings.lockPreviewYAxis) candidate.y = startCenter.y;
		candidate.x = MAX(minX, MIN(maxX, candidate.x));
		candidate.y = MAX(minY, MIN(maxY, candidate.y));

		NSLayoutConstraint *cx = self.centerXConstraint;
		NSLayoutConstraint *cy = self.centerYConstraint;
		if (cx && cy) {
			cx.constant = candidate.x - CGRectGetMidX(host.bounds);
			cy.constant = candidate.y - CGRectGetMidY(host.bounds);
			CGFloat nx = MAX(0.05, MIN(0.95, (candidate.x - CGRectGetMinX(viewport)) / MAX(1.0, CGRectGetWidth(viewport))));
			CGFloat ny = MAX(0.05, MIN(0.95, (candidate.y - CGRectGetMinY(viewport)) / MAX(1.0, CGRectGetHeight(viewport))));
			[self.presentationStore updatePosition:(JikanPillPosition){nx, ny, YES} landscape:isLandscape];
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
		[self.presentationStore updatePosition:(JikanPillPosition){nx, ny, YES} landscape:isLandscape];

		NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
		JikanSavePillPosition(prefs, isLandscape, nx, ny);
		[prefs synchronize];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);

		self.dragging = NO;
		self.dragStartCenter = nil;
		self.dragStartTouch = nil;
	}
}

- (void)updatePlatterWithState:(JikanPresentationState *)state {
	JikanPresentationSettings *settings = state.settings;
	if (!settings.enabled) {
		[self.platter enterEditMode:NO];
		[self.platter setPreviewMode:NO];
		[self.platter applyPresentationState:state];
		[self setPlatterVisible:NO state:state];
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

	[self.platter applyPresentationState:state];
	self.longPress.enabled = state.shouldShowPlatter;
	[self setPlatterVisible:state.shouldShowPlatter state:state];
}

- (void)setPlatterVisible:(BOOL)visible state:(JikanPresentationState *)state {
	JikanPresentationSettings *settings = state.settings;
	if (!self.platter) return;

	BOOL currentlyVisible = !self.platter.hidden && self.platter.alpha > 0.01;
	if (visible == currentlyVisible) {
		if (visible && self.platter.alpha < 1.0) {
			self.platter.alpha = 1.0;
		}
		return;
	}

	[self.platter.layer removeAllAnimations];
	if (UIAccessibilityIsReduceMotionEnabled() || !settings.enabled) {
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

- (void)configureConstraintsWithState:(JikanPresentationState *)state {
	JikanPresentationSettings *settings = state.settings;
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
	BOOL hasCustomForOrientation = isLandscape ? settings.landscapePosition.hasCustomPosition : settings.portraitPosition.hasCustomPosition;
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
		if (!hasCustomForOrientation && !state.shouldHideQuickActionButtons && innerGap >= 64.0) maximumWidth = MIN(maximumWidth, innerGap);
	}
	CGSize size = [self.platter preferredSizeForMaximumWidth:maximumWidth height:pillHeight];
	CGFloat platterWidth = size.width;
	CGFloat kPlatterHeight = size.height;
	CGFloat defaultCenterX = hasButtons ? (CGRectGetMidX(leadingRect) + CGRectGetMidX(trailingRect)) * 0.5 : CGRectGetMidX(viewport);
	CGFloat safeBottomY = CGRectGetMaxY(viewport) - host.safeAreaInsets.bottom;
	CGFloat defaultCenterY = hasButtons ? (CGRectGetMidY(leadingRect) + CGRectGetMidY(trailingRect)) * 0.5 : safeBottomY - (state.shouldHideQuickActionButtons ? 28.0 : 76.0) - kPlatterHeight * 0.5;

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

	if (!isLandscape && !settings.portraitPosition.hasCustomPosition && !self.defaultCenterComputedPortrait) {
		JikanPillPosition position = {
			(defaultCenterX - CGRectGetMinX(viewport)) / MAX(1.0, CGRectGetWidth(viewport)),
			(defaultCenterY - CGRectGetMinY(viewport)) / MAX(1.0, CGRectGetHeight(viewport)), NO};
		[self.presentationStore updatePosition:position landscape:NO];
		self.defaultCenterComputedPortrait = YES;
	}
	if (isLandscape && !settings.landscapePosition.hasCustomPosition && !self.defaultCenterComputedLandscape) {
		JikanPillPosition position = {
			(defaultCenterX - CGRectGetMinX(viewport)) / MAX(1.0, CGRectGetWidth(viewport)),
			(defaultCenterY - CGRectGetMinY(viewport)) / MAX(1.0, CGRectGetHeight(viewport)), NO};
		[self.presentationStore updatePosition:position landscape:YES];
		self.defaultCenterComputedLandscape = YES;
	}

	CGFloat savedX = isLandscape ? settings.landscapePosition.x : settings.portraitPosition.x;
	CGFloat savedY = isLandscape ? settings.landscapePosition.y : settings.portraitPosition.y;
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

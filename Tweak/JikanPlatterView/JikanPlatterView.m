#import "../Jikan.h"
#import "../TT100/TT100.h"
#import "JikanPlatterView.h"

static void TTCopyLayerVisualProperties(CALayer *source, CALayer *target) {
	if (!source || !target) return;
	target.cornerRadius = source.cornerRadius;
	target.cornerCurve = source.cornerCurve;
	target.maskedCorners = source.maskedCorners;
	target.borderWidth = source.borderWidth;
	target.borderColor = source.borderColor;
	target.shadowOpacity = source.shadowOpacity;
	target.shadowRadius = source.shadowRadius;
	target.shadowOffset = source.shadowOffset;
	target.shadowColor = source.shadowColor;
	target.shadowPath = source.shadowPath;
	target.compositingFilter = source.compositingFilter;
	target.filters = source.filters;
	target.allowsGroupOpacity = source.allowsGroupOpacity;
	target.allowsEdgeAntialiasing = source.allowsEdgeAntialiasing;
}

static UIView *TTFindFirstSubviewWithClassNameFragment(UIView *root, NSString *fragment) {
	if (!root || fragment.length == 0) return nil;
	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
	while (stack.count) {
		UIView *view = stack.lastObject;
		[stack removeLastObject];
		if ([NSStringFromClass(view.class) containsString:fragment]) {
			return view;
		}
		for (UIView *subview in view.subviews) {
			[stack addObject:subview];
		}
	}
	return nil;
}

@implementation JikanPlatterView

static CGFloat TTClamp(CGFloat value, CGFloat minValue, CGFloat maxValue) {
	return MIN(MAX(value, minValue), maxValue);
}

- (instancetype)init {
	self = [super init];
	if (self) {
		self.translatesAutoresizingMaskIntoConstraints = NO;

		[self _setupSubviews];

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_tt100BatteryInfoUpdated:) name:TT100BatteryInfoUpdatedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_chargingStateChanged:) name:JikanChargingStateChangedNotification object:nil];

		if (isCharging) {
			[self _startRefreshTimer];
		}
		[[TT100 sharedInstance] _refreshBatteryInfo];
	}

	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self _stopRefreshTimer];
#if !__has_feature(objc_arc)
	[super dealloc];
#endif
}

- (void)didMoveToWindow {
	[super didMoveToWindow];

	if (!self.window) {
		[self _stopRefreshTimer];
		return;
	}

	if (isCharging) {
		[self _startRefreshTimer];
	}
}

- (void)_tt100BatteryInfoUpdated:(NSNotification *)notification {
	NSString *timeString = notification.userInfo[@"timeString"];
	[self updateWithTimeString:timeString];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	self.layer.cornerRadius = self.bounds.size.height / 2;
	self.clipsToBounds = YES;
	if (_backgroundView) {
		_backgroundView.layer.cornerRadius = _backgroundView.bounds.size.height / 2;
		_backgroundView.layer.cornerCurve = self.layer.cornerCurve;
	}

	[self _updateTypographyForCurrentSize];
}

- (void)_setupSubviews {
	UIBlurEffect *fallbackEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
	UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:fallbackEffect];
	effectView.translatesAutoresizingMaskIntoConstraints = NO;
	effectView.clipsToBounds = YES;
	_backgroundView = effectView;
	[self addSubview:_backgroundView];
	[self sendSubviewToBack:_backgroundView];

	_styleOverlayView = [[UIView alloc] init];
	_styleOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
	_styleOverlayView.userInteractionEnabled = NO;
	_styleOverlayView.backgroundColor = [UIColor blackColor];
	_styleOverlayView.alpha = 0.12;
	_styleOverlayView.layer.compositingFilter = @"darkenSourceOver";
	[self addSubview:_styleOverlayView];

	_contentTintReplicaView = [[UIView alloc] init];
	_contentTintReplicaView.translatesAutoresizingMaskIntoConstraints = NO;
	_contentTintReplicaView.userInteractionEnabled = NO;
	_contentTintReplicaView.hidden = YES;
	_contentTintReplicaView.alpha = 0.0;
	[self addSubview:_contentTintReplicaView];

	_containerView = [[UIView alloc] init];
	_containerView.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:_containerView];

	UIImage *boltImage = [[UIImage systemImageNamed:@"bolt.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	_boltImageView = [[UIImageView alloc] initWithImage:boltImage];
	_boltImageView.tintColor = [UIColor greenColor];
	_boltImageView.translatesAutoresizingMaskIntoConstraints = NO;
	[_containerView addSubview:_boltImageView];

	_timeRemainingLabel = [[UILabel alloc] init];
	_timeRemainingLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_timeRemainingLabel.textColor = [UIColor whiteColor];
	_timeRemainingLabel.adjustsFontForContentSizeCategory = YES;
	_timeRemainingLabel.adjustsFontSizeToFitWidth = YES;
	_timeRemainingLabel.minimumScaleFactor = 0.75;
	_timeRemainingLabel.textAlignment = NSTextAlignmentCenter;
	_timeRemainingLabel.text = @"0 minutes";
	[_containerView addSubview:_timeRemainingLabel];

	_staticLabel = [[UILabel alloc] init];
	_staticLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_staticLabel.textColor = [UIColor whiteColor];
	_staticLabel.adjustsFontForContentSizeCategory = YES;
	_staticLabel.adjustsFontSizeToFitWidth = YES;
	_staticLabel.minimumScaleFactor = 0.8;
	_staticLabel.textAlignment = NSTextAlignmentCenter;
	_staticLabel.text = @"until fully charged";
	[_containerView addSubview:_staticLabel];

	[self _updateTypographyForCurrentSize];
}

- (void)_updateTypographyForCurrentSize {
	CGFloat h = CGRectGetHeight(self.bounds);
	if (h <= 0) h = 60.0;

	CGFloat primarySize = TTClamp(h * 0.32, 14.0, 20.0);
	CGFloat secondarySize = TTClamp(h * 0.22, 11.0, 15.0);

	UIFont *primaryBase = [UIFont monospacedDigitSystemFontOfSize:primarySize weight:UIFontWeightSemibold];
	UIFont *secondaryBase = [UIFont systemFontOfSize:secondarySize weight:UIFontWeightMedium];

	_timeRemainingLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:primaryBase compatibleWithTraitCollection:self.traitCollection];
	_staticLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:secondaryBase compatibleWithTraitCollection:self.traitCollection];
}

- (void)setupConstraints {
	[NSLayoutConstraint activateConstraints:@[
		[_backgroundView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
		[_backgroundView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
		[_backgroundView.topAnchor constraintEqualToAnchor:self.topAnchor],
		[_backgroundView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

		[_styleOverlayView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
		[_styleOverlayView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
		[_styleOverlayView.topAnchor constraintEqualToAnchor:self.topAnchor],
		[_styleOverlayView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

		[_contentTintReplicaView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
		[_contentTintReplicaView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
		[_contentTintReplicaView.topAnchor constraintEqualToAnchor:self.topAnchor],
		[_contentTintReplicaView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

		[_containerView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
		[_containerView.bottomAnchor constraintEqualToAnchor:self.centerYAnchor constant:-8],

		[_boltImageView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor],
		[_boltImageView.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
		[_boltImageView.widthAnchor constraintEqualToConstant:10],
		[_boltImageView.heightAnchor constraintEqualToConstant:10],

		[_timeRemainingLabel.leadingAnchor constraintEqualToAnchor:_boltImageView.trailingAnchor constant:4],
		[_timeRemainingLabel.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor],
		[_timeRemainingLabel.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
		[_timeRemainingLabel.heightAnchor constraintEqualToConstant:20],

		[_staticLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
		[_staticLabel.topAnchor constraintEqualToAnchor:self.centerYAnchor],
		[_staticLabel.heightAnchor constraintEqualToConstant:20],
	]];
}

- (void)updateWithTimeString:(NSString *)timeString {
	_timeRemainingLabel.text = timeString;
}

- (void)applyQuickActionVisualEffect:(UIVisualEffect *)effect {
	if (![self->_backgroundView isKindOfClass:[UIVisualEffectView class]]) return;
	UIVisualEffectView *ev = (UIVisualEffectView *)self->_backgroundView;
	if (effect) {
		ev.effect = effect;
	} else if (!ev.effect) {
		ev.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
	}
	[ev setNeedsLayout];
	[ev layoutIfNeeded];
}

- (void)applyQuickActionBackgroundStyleFromView:(UIView *)sourceView {
	if (!sourceView) return;

	if (sourceView.backgroundColor) {
		self.backgroundColor = sourceView.backgroundColor;
	}
	self.alpha = sourceView.alpha;
	self.opaque = sourceView.opaque;
	self.clipsToBounds = sourceView.clipsToBounds;
	self.tintColor = sourceView.tintColor;

	UIVisualEffectView *sourceEffectView = nil;
	if ([sourceView isKindOfClass:[UIVisualEffectView class]]) {
		sourceEffectView = (UIVisualEffectView *)sourceView;
	} else {
		sourceEffectView = (UIVisualEffectView *)TTFindFirstSubviewWithClassNameFragment(sourceView, @"UIVisualEffectView");
	}

	if ([self->_backgroundView isKindOfClass:[UIVisualEffectView class]] && sourceEffectView) {
		UIVisualEffectView *target = (UIVisualEffectView *)self->_backgroundView;
		if (sourceEffectView.effect) {
			target.effect = sourceEffectView.effect;
		} else if (!target.effect) {
			target.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
		}
		target.alpha = sourceEffectView.alpha;
		target.backgroundColor = sourceEffectView.backgroundColor;
		target.opaque = sourceEffectView.opaque;
		target.clipsToBounds = sourceEffectView.clipsToBounds;
		target.tintColor = sourceEffectView.tintColor;
		TTCopyLayerVisualProperties(sourceEffectView.layer, target.layer);

		UIView *sourceBackdrop = TTFindFirstSubviewWithClassNameFragment(sourceEffectView, @"_UIVisualEffectBackdropView");
		UIView *targetBackdrop = TTFindFirstSubviewWithClassNameFragment(target, @"_UIVisualEffectBackdropView");
		if (sourceBackdrop && targetBackdrop) {
			targetBackdrop.alpha = sourceBackdrop.alpha;
			targetBackdrop.hidden = sourceBackdrop.hidden;
			targetBackdrop.backgroundColor = sourceBackdrop.backgroundColor;
			targetBackdrop.opaque = sourceBackdrop.opaque;
			targetBackdrop.clipsToBounds = sourceBackdrop.clipsToBounds;
			TTCopyLayerVisualProperties(sourceBackdrop.layer, targetBackdrop.layer);

			for (NSString *key in @[@"inputSettings", @"outputSettings", @"captureGroup", @"groupName", @"allowsInPlaceFiltering"]) {
				@try {
					id value = [sourceBackdrop valueForKey:key];
					if (value && value != [NSNull null]) {
						[targetBackdrop setValue:value forKey:key];
					}
				} @catch (__unused NSException *exception) {
				}
			}
		}
	}

	self.layer.cornerCurve = sourceView.layer.cornerCurve;
	self.layer.cornerRadius = self.bounds.size.height / 2;
	TTCopyLayerVisualProperties(sourceView.layer, self.layer);
	self.layer.cornerRadius = self.bounds.size.height / 2;

	if (self->_backgroundView) {
		TTCopyLayerVisualProperties(sourceView.layer, self->_backgroundView.layer);
		self->_backgroundView.layer.cornerRadius = self.bounds.size.height / 2;
	}

	if (self->_styleOverlayView) {
		UIView *sourceOverlay = TTFindFirstSubviewWithClassNameFragment(sourceView, @"_UIVisualEffectSubview");
		if (sourceOverlay) {
			self->_styleOverlayView.hidden = sourceOverlay.hidden;
			self->_styleOverlayView.alpha = sourceOverlay.alpha;
			self->_styleOverlayView.backgroundColor = sourceOverlay.backgroundColor;
			self->_styleOverlayView.layer.compositingFilter = sourceOverlay.layer.compositingFilter;
			TTCopyLayerVisualProperties(sourceOverlay.layer, self->_styleOverlayView.layer);
		} else {
			self->_styleOverlayView.hidden = NO;
			self->_styleOverlayView.alpha = 0.12;
			self->_styleOverlayView.backgroundColor = [UIColor blackColor];
			self->_styleOverlayView.layer.compositingFilter = @"darkenSourceOver";
		}
	}

	if (self->_contentTintReplicaView) {
		UIView *sourceContentView = TTFindFirstSubviewWithClassNameFragment(sourceView, @"_UIVisualEffectContentView");
		UIView *sourceTintReplica = nil;
		if (sourceContentView) {
			for (UIView *candidate in sourceContentView.subviews) {
				if ([candidate isKindOfClass:[UIView class]] && ![candidate isKindOfClass:[UIControl class]] && candidate.alpha < 0.01) {
					sourceTintReplica = candidate;
					break;
				}
			}
		}

		if (sourceTintReplica) {
			self->_contentTintReplicaView.hidden = sourceTintReplica.hidden;
			self->_contentTintReplicaView.alpha = sourceTintReplica.alpha;
			self->_contentTintReplicaView.backgroundColor = sourceTintReplica.backgroundColor;
			self->_contentTintReplicaView.layer.compositingFilter = sourceTintReplica.layer.compositingFilter;
			TTCopyLayerVisualProperties(sourceTintReplica.layer, self->_contentTintReplicaView.layer);
		} else {
			self->_contentTintReplicaView.hidden = YES;
			self->_contentTintReplicaView.alpha = 0.0;
		}
	}

	[self setNeedsLayout];
}

- (void)_chargingStateChanged:(NSNotification *)notification {
	BOOL charging = [notification.userInfo[@"isCharging"] boolValue];
	if (charging) {
		[self _startRefreshTimer];
		[[TT100 sharedInstance] _refreshBatteryInfo];
	} else {
		[self _stopRefreshTimer];
	}
}

- (void)_startRefreshTimer {
	if (!_refreshTimer) {
		_refreshTimer = [NSTimer scheduledTimerWithTimeInterval:15.0 target:self selector:@selector(_triggerBatteryRefresh) userInfo:nil repeats:YES];
		_refreshTimer.tolerance = 3.0;
	}
}

- (void)_stopRefreshTimer {
	[_refreshTimer invalidate];
	_refreshTimer = nil;
}

- (void)_triggerBatteryRefresh {
	[[TT100 sharedInstance] _refreshBatteryInfo];
}

@end

#import "JikanPlatterView.h"

static CGFloat TTWiggleRandomOffset(void) {
	return ((arc4random_uniform(1000) / 1000.0) - 0.5) * 0.03;
}

static const CGFloat kTTPreviewOutlineLineWidth = 2.5;
static const CGFloat kTTPreviewOutlineGap = 2.0;

@interface JikanPlatterView () {
	JikanPlatterMaterial *_material;
	CAShapeLayer *_previewOutlineLayer;
	UITapGestureRecognizer *_tapGesture;
	JikanPresentationState *_presentationState;
	NSArray<NSString *> *_activeStackItems;
	NSString *_selectedStackItem;
	BOOL _previewMode;
	BOOL _editingMode;
	JikanPillContentView *_contentView;
}
@end

@implementation JikanPlatterView

- (void)_applyBackgroundOpacity {
	[_material applyOpacity:_presentationState ? _presentationState.settings.backgroundOpacity : 1.0];
}

- (instancetype)init {
	self = [super init];
	if (self) {
		self.translatesAutoresizingMaskIntoConstraints = NO;
		self.isAccessibilityElement = YES;

		[self _setupSubviews];

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_localeChanged:) name:NSCurrentLocaleDidChangeNotification object:nil];
	}

	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
#if !__has_feature(objc_arc)
	[super dealloc];
#endif
}

- (void)didMoveToWindow {
	[super didMoveToWindow];

	if (!self.window) {
		_selectedStackItem = JikanStackEstimate;
		return;
	}

	[self _renderCurrentItem];
	[self _updateTapGestureState];
	[self _applyBackgroundOpacity];
}

- (void)applyPresentationState:(JikanPresentationState *)state {
	BOOL wasConnected = _presentationState.snapshot.externalPowerConnected;
	_presentationState = state;
	[self _reloadStackPreferences];
	_contentView.appearance = state.settings.appearance;
	if (wasConnected && !state.snapshot.externalPowerConnected) {
		[self enterEditMode:NO];
		_selectedStackItem = JikanStackEstimate;
	}
	[self setPreviewMode:state.usesPreviewContent];
	if (!self.window) return;
	[self _renderCurrentItem];
	[self _applyBackgroundOpacity];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	[_material layoutMaterialViews];
	[self _applyBackgroundOpacity];
	[self _updatePreviewOutlineAppearance];
}

- (void)_setupSubviews {
	_material = [[JikanPlatterMaterial alloc] initWithContainerView:self];

	_contentView = [[JikanPillContentView alloc] init];
	_contentView.translatesAutoresizingMaskIntoConstraints = NO;
	[_contentView applyContent:[[JikanPillContent alloc] initWithPrimaryText:JikanLocalizedString(@"jikan.platter.preview.time", @"0 minutes")
															   secondaryText:[JikanPillContent estimateSubtitleForTargetPercent:100]
																	progress:0.0
															   chargingSpeed:@"normal"]];
	__weak JikanPlatterView *weakSelf = self;
	_contentView.contentSizeDidChange = ^{ [weakSelf _contentSizeChanged]; };
	[self addSubview:_contentView];

	_tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTap:)];
	[self addGestureRecognizer:_tapGesture];
	[self _updateTapGestureState];
	[self _applyBackgroundOpacity];
}

- (void)_contentSizeChanged {
	self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", _contentView.content.primaryText ?: @"", _contentView.content.secondaryText ?: @""];
	[self setNeedsLayout];
	if (self.contentSizeDidChange) self.contentSizeDidChange();
}

- (void)_localeChanged:(NSNotification *)notification {
#pragma unused(notification)
	[self _renderCurrentItem];
}

- (CGSize)preferredSizeForMaximumWidth:(CGFloat)width height:(CGFloat)height {
	return [_contentView preferredSizeForMaximumWidth:width height:height];
}

- (void)setupConstraints {
	[_material setupConstraints];
	[NSLayoutConstraint activateConstraints:@[
		[_contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
		[_contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
		[_contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
		[_contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
	]];
}

- (void)_reloadStackPreferences {
	NSArray<NSString *> *items = _presentationState.settings.stackItems ?: @[JikanStackEstimate];
	if (![_activeStackItems isEqualToArray:items]) _activeStackItems = [items copy];
	if (![_activeStackItems containsObject:_selectedStackItem]) _selectedStackItem = JikanStackEstimate;
	[self _updateTapGestureState];
}

- (void)_renderCurrentItem {
	NSString *item = _selectedStackItem ?: JikanStackEstimate;
	NSString *primaryText;
	NSString *secondaryText;
	NSDictionary *batteryInfo = _presentationState.snapshot.batteryInfo;
	if ([item isEqualToString:JikanStackWattage]) {
		double watts = _previewMode ? 5.0 : [TT100 effectiveChargingWattageWithBatteryInfo:batteryInfo];
		primaryText = [JikanPillContent formattedWattage:watts];
		secondaryText = JikanLocalizedString(@"jikan.platter.label.current_wattage", @"current wattage");
	} else if ([item isEqualToString:JikanStackTemperature]) {
		primaryText = JikanFormattedBatteryTemperature(_previewMode ? @{@"Temperature": @3700} : batteryInfo, JikanResolveTemperatureUnit(_presentationState.settings.temperatureUnit)) ?: JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
		secondaryText = JikanLocalizedString(@"jikan.platter.label.battery_temperature", @"battery temperature");
	} else if ([item isEqualToString:JikanStackVoltage]) {
		primaryText = JikanFormattedBatteryVoltage(_previewMode ? @{@"Voltage": @4000} : batteryInfo) ?: JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
		secondaryText = JikanLocalizedString(@"jikan.platter.label.battery_voltage", @"battery voltage");
	} else if (_presentationState.snapshot.targetReached && _presentationState.settings.showAfterFullCharge && !_previewMode) {
		primaryText = [NSString stringWithFormat:@"%ld%%", (long)_presentationState.snapshot.displayPercent];
		secondaryText = JikanLocalizedString(@"jikan.platter.label.charged", @"charged");
	} else {
		primaryText = _previewMode ? JikanLocalizedString(@"jikan.platter.preview.eta", @"1 hr 23 min") : (_presentationState.snapshot.timeString ?: JikanLocalizedString(@"jikan.tt100.value.na", @"N/A"));
		secondaryText = [JikanPillContent estimateSubtitleForTargetPercent:_presentationState ? _presentationState.settings.targetPercent : 100];
	}
	double progress = (double)_presentationState.snapshot.displayPercent / MAX(1, _presentationState.settings.targetPercent);
	[_contentView applyContent:[[JikanPillContent alloc] initWithPrimaryText:primaryText secondaryText:secondaryText progress:progress chargingSpeed:_presentationState.snapshot.chargingSpeed]];
}

- (void)setPreviewMode:(BOOL)preview {
	if (_previewMode == preview) {
		if (_previewMode) [self _renderCurrentItem];
		return;
	}
	_previewMode = preview;
	_selectedStackItem = JikanStackEstimate;
	[self _renderCurrentItem];
	[self _updateTapGestureState];
	[self _updatePreviewOutlineAppearance];
	[self _contentSizeChanged];
}

- (void)_updatePreviewOutlineAppearance {
	if (!_previewMode) {
		_previewOutlineLayer.hidden = YES;
		return;
	}

	if (!_previewOutlineLayer) {
		_previewOutlineLayer = [CAShapeLayer layer];
		_previewOutlineLayer.fillColor = UIColor.clearColor.CGColor;
		_previewOutlineLayer.strokeColor = UIColor.systemRedColor.CGColor;
		_previewOutlineLayer.lineWidth = kTTPreviewOutlineLineWidth;
		_previewOutlineLayer.lineJoin = kCALineJoinRound;
		_previewOutlineLayer.zPosition = -1.0;
		[self.layer addSublayer:_previewOutlineLayer];
	}

	CGFloat radius = CGRectGetHeight(self.bounds) * 0.5 + kTTPreviewOutlineGap;
	CGFloat inset = -(kTTPreviewOutlineGap + (kTTPreviewOutlineLineWidth * 0.5));
	CGRect outlineRect = CGRectInset(self.bounds, inset, inset);

	_previewOutlineLayer.hidden = NO;
	_previewOutlineLayer.path = [UIBezierPath bezierPathWithRoundedRect:outlineRect cornerRadius:radius].CGPath;
}

- (void)enterEditMode:(BOOL)editing {
	if (_editingMode == editing) return;
	_editingMode = editing;
	if (editing) {
		_selectedStackItem = JikanStackEstimate;
		[self _renderCurrentItem];
	}
	if (UIAccessibilityIsReduceMotionEnabled()) {
		[self.layer removeAnimationForKey:@"jikan.wiggle.rotation"];
		[self.layer removeAnimationForKey:@"jikan.wiggle.bob"];
		self.transform = CGAffineTransformIdentity;
		[self _updateTapGestureState];
		return;
	}
	if (editing) {
		[self.layer removeAnimationForKey:@"jikan.wiggle.rotation"];
		[self.layer removeAnimationForKey:@"jikan.wiggle.bob"];

		CAKeyframeAnimation *rotate = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
		CGFloat r = 0.018 + TTWiggleRandomOffset();
		rotate.values = @[@(-r), @(r)];
		rotate.autoreverses = YES;
		rotate.duration = 0.16;
		rotate.repeatCount = HUGE_VALF;
		rotate.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
		[self.layer addAnimation:rotate forKey:@"jikan.wiggle.rotation"];

		CABasicAnimation *bob = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
		bob.fromValue = @(-0.8);
		bob.toValue = @(0.8);
		bob.autoreverses = YES;
		bob.duration = 0.22;
		bob.repeatCount = HUGE_VALF;
		bob.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
		[self.layer addAnimation:bob forKey:@"jikan.wiggle.bob"];

		[UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
			self.transform = CGAffineTransformScale(self.transform, 1.02, 1.02);
		} completion:nil];
	} else {
		[self.layer removeAnimationForKey:@"jikan.wiggle.rotation"];
		[self.layer removeAnimationForKey:@"jikan.wiggle.bob"];
		[UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
			self.transform = CGAffineTransformIdentity;
		} completion:nil];
	}
	[self _updateTapGestureState];
}

- (BOOL)applyQuickActionGlassFromView:(UIView *)sourceView {
	return [_material applyQuickActionGlassFromView:sourceView];
}

- (void)applyQuickActionVisualEffect:(UIVisualEffect *)effect {
	[_material applyQuickActionVisualEffect:effect];
}

- (void)applyQuickActionBackgroundStyleFromView:(UIView *)sourceView {
	[_material applyQuickActionBackgroundStyleFromView:sourceView opacity:_presentationState ? _presentationState.settings.backgroundOpacity : 1.0];
}

- (void)_updateTapGestureState {
	if (!_tapGesture) return;
	_tapGesture.enabled = _activeStackItems.count > 1 && (_presentationState.snapshot.externalPowerConnected || _previewMode) && !_editingMode;
	self.accessibilityTraits = _tapGesture.enabled ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
	self.accessibilityHint = _tapGesture.enabled ? JikanLocalizedString(@"jikan.platter.accessibility.next_item", @"Shows the next Stack item") : nil;
}

- (void)_handleTap:(UITapGestureRecognizer *)gesture {
	if (gesture.state != UIGestureRecognizerStateRecognized) return;
	[self _advanceStack];
}

- (BOOL)accessibilityActivate {
	if (!_tapGesture.enabled) return NO;
	[self _advanceStack];
	return YES;
}

- (void)_advanceStack {
	if (_activeStackItems.count < 2 || (!_presentationState.snapshot.externalPowerConnected && !_previewMode) || _editingMode) return;
	NSUInteger index = [_activeStackItems indexOfObject:_selectedStackItem];
	_selectedStackItem = _activeStackItems[(index == NSNotFound ? 0 : index + 1) % _activeStackItems.count];
	[self _renderCurrentItem];
	if (UIAccessibilityIsVoiceOverRunning()) UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.accessibilityLabel);
}

@end

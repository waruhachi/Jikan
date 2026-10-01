#import "JikanPlatterView.h"

static BOOL TTConfigureLockScreenGlass(UIView *view, UIView *container) {
	if (@available(iOS 26.0, *)) {
		SEL backgroundSetter = NSSelectorFromString(@"cs_setLockPickGlassBackgroundWithLuminance:");
		SEL groupSetter = NSSelectorFromString(@"cs_setLockPickGlassGroupBackground");
		if (![view respondsToSelector:backgroundSetter] || ![container respondsToSelector:groupSetter]) return NO;
		((void (*)(id, SEL))objc_msgSend)(container, groupSetter);
		((void (*)(id, SEL, float))objc_msgSend)(view, backgroundSetter, 0.0f);
		return YES;
	}
	return NO;
}

static BOOL TTConfigureLiquidGlass(UIVisualEffectView *view) {
	if (@available(iOS 26.0, *)) {
		// Resolve the public UIKit APIs at runtime so the tweak still builds
		// with its older SDK and loads on iOS versions without Liquid Glass.
		Class glassClass = NSClassFromString(@"UIGlassEffect");
		Class cornerClass = NSClassFromString(@"UICornerConfiguration");
		SEL effectSelector = NSSelectorFromString(@"effectWithStyle:");
		SEL capsuleSelector = NSSelectorFromString(@"capsuleConfiguration");
		SEL cornerSetter = NSSelectorFromString(@"setCornerConfiguration:");
		if (![glassClass respondsToSelector:effectSelector] ||
			![cornerClass respondsToSelector:capsuleSelector] ||
			![view respondsToSelector:cornerSetter]) return NO;
		UIVisualEffect *effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassClass, effectSelector, 0);	 // UIGlassEffectStyleRegular
		id corners = ((id (*)(id, SEL))objc_msgSend)(cornerClass, capsuleSelector);
		if (![effect isKindOfClass:UIVisualEffect.class] || !corners) return NO;
		view.effect = effect;
		((void (*)(id, SEL, id))objc_msgSend)(view, cornerSetter, corners);
		return YES;
	}
	return NO;
}

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

static CGFloat TTWiggleRandomOffset(void) {
	return ((arc4random_uniform(1000) / 1000.0) - 0.5) * 0.03;
}

static const CGFloat kTTPreviewOutlineLineWidth = 2.5;
static const CGFloat kTTPreviewOutlineGap = 2.0;

@interface JikanPlatterView () {
	UIView *_backgroundView;
	UIView *_styleOverlayView;
	UIView *_contentTintReplicaView;
	CAShapeLayer *_previewOutlineLayer;
	UITapGestureRecognizer *_tapGesture;
	JikanPresentationState *_presentationState;
	NSArray<NSString *> *_activeStackItems;
	NSString *_selectedStackItem;
	BOOL _previewMode;
	BOOL _editingMode;
	BOOL _usesLiquidGlass;
	BOOL _usesLockScreenGlass;
	float _glassLuminance;
	CGFloat _backgroundBaseAlpha;
	CGFloat _styleOverlayBaseAlpha;
	CGFloat _contentTintBaseAlpha;
	JikanPillContentView *_contentView;
}
@end

@implementation JikanPlatterView

- (void)_captureBackgroundBaseAlphas {
	_backgroundBaseAlpha = _backgroundView ? _backgroundView.alpha : 1.0;
	_styleOverlayBaseAlpha = _styleOverlayView ? _styleOverlayView.alpha : 0.12;
	_contentTintBaseAlpha = _contentTintReplicaView ? _contentTintReplicaView.alpha : 0.0;
}

- (void)_applyBackgroundOpacity {
	CGFloat factor = _presentationState ? _presentationState.settings.backgroundOpacity : 1.0;
	if (!isfinite(factor)) factor = 1.0;
	factor = MAX(0.0, MIN(1.0, factor));

	if (_backgroundView) {
		_backgroundView.alpha = _backgroundBaseAlpha * factor;
	}
	if (_styleOverlayView) {
		_styleOverlayView.alpha = _styleOverlayBaseAlpha * factor;
	}
	if (_contentTintReplicaView) {
		_contentTintReplicaView.alpha = _contentTintBaseAlpha * factor;
	}
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

	self.layer.cornerRadius = self.bounds.size.height / 2;
	self.clipsToBounds = NO;
	if (_backgroundView && (!_usesLiquidGlass || _usesLockScreenGlass)) {
		_backgroundView.layer.cornerRadius = _backgroundView.bounds.size.height / 2;
		_backgroundView.layer.cornerCurve = self.layer.cornerCurve;
		_backgroundView.clipsToBounds = YES;
	}
	if (_styleOverlayView) {
		_styleOverlayView.layer.cornerRadius = _styleOverlayView.bounds.size.height / 2;
		_styleOverlayView.layer.cornerCurve = self.layer.cornerCurve;
		_styleOverlayView.clipsToBounds = YES;
	}
	if (_contentTintReplicaView) {
		_contentTintReplicaView.layer.cornerRadius = _contentTintReplicaView.bounds.size.height / 2;
		_contentTintReplicaView.layer.cornerCurve = self.layer.cornerCurve;
		_contentTintReplicaView.clipsToBounds = YES;
	}

	[self _applyBackgroundOpacity];
	[self _updatePreviewOutlineAppearance];
}

- (void)_setupSubviews {
	UIView *glassView = [[UIView alloc] init];
	_usesLockScreenGlass = TTConfigureLockScreenGlass(glassView, self);
	if (_usesLockScreenGlass) {
		_backgroundView = glassView;
		_usesLiquidGlass = YES;
	} else {
		UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:nil];
		_usesLiquidGlass = TTConfigureLiquidGlass(effectView);
		if (!_usesLiquidGlass) effectView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
		_backgroundView = effectView;
	}
	_backgroundView.translatesAutoresizingMaskIntoConstraints = NO;
	_backgroundView.clipsToBounds = !_usesLiquidGlass || _usesLockScreenGlass;
	_backgroundView.userInteractionEnabled = NO;
	[self addSubview:_backgroundView];
	[self sendSubviewToBack:_backgroundView];

	_styleOverlayView = [[UIView alloc] init];
	_styleOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
	_styleOverlayView.userInteractionEnabled = NO;
	_styleOverlayView.backgroundColor = [UIColor blackColor];
	_styleOverlayView.alpha = _usesLiquidGlass ? 0.0 : 0.12;
	_styleOverlayView.hidden = _usesLiquidGlass;
	_styleOverlayView.layer.compositingFilter = @"darkenSourceOver";
	[self addSubview:_styleOverlayView];

	_contentTintReplicaView = [[UIView alloc] init];
	_contentTintReplicaView.translatesAutoresizingMaskIntoConstraints = NO;
	_contentTintReplicaView.userInteractionEnabled = NO;
	_contentTintReplicaView.hidden = YES;
	_contentTintReplicaView.alpha = 0.0;
	[self addSubview:_contentTintReplicaView];

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
	[self _captureBackgroundBaseAlphas];
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
	if (!_usesLiquidGlass || !sourceView) return NO;
	if (_usesLockScreenGlass) {
		// The Lock Screen renderer applies its own material configuration and
		// glass group. A public UIGlassEffect copy does not retain that context.
		SEL getter = NSSelectorFromString(@"glassLuminanceValue");
		if (![sourceView respondsToSelector:getter]) return NO;
		double value = ((double (*)(id, SEL))objc_msgSend)(sourceView, getter);
		if (!isfinite(value)) return NO;
		float luminance = (float)value;
		if (luminance != _glassLuminance) {
			_glassLuminance = luminance;
			((void (*)(id, SEL, float))objc_msgSend)(_backgroundView, NSSelectorFromString(@"cs_setLockPickGlassBackgroundWithLuminance:"), luminance);
		}
		_backgroundView.overrideUserInterfaceStyle = sourceView.traitCollection.userInterfaceStyle;
		return YES;
	}
	// Do not pick up an active flashlight's selected or pressed appearance.
	if ([sourceView isKindOfClass:UIControl.class] &&
		(((UIControl *)sourceView).selected || ((UIControl *)sourceView).highlighted)) return NO;
	Class glassClass = NSClassFromString(@"UIGlassEffect");
	SEL getter = NSSelectorFromString(@"_glassEffect");
	NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:sourceView];
	while (views.count) {
		UIView *view = views.lastObject;
		[views removeLastObject];
		id effect = [view isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)view).effect : nil;
		if (!effect && [view respondsToSelector:getter]) {
			effect = ((id (*)(id, SEL))objc_msgSend)(view, getter);
		}
		if ([effect isKindOfClass:glassClass]) {
			UIVisualEffectView *target = (UIVisualEffectView *)_backgroundView;
			if (![target.effect isEqual:effect]) target.effect = [effect copy];
			target.overrideUserInterfaceStyle = view.traitCollection.userInterfaceStyle;

			return YES;
		}
		[views addObjectsFromArray:view.subviews];
	}
	return NO;
}

- (void)applyQuickActionVisualEffect:(UIVisualEffect *)effect {
	if (_usesLiquidGlass) return;
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
	if (_usesLiquidGlass) return;
	if (!sourceView) return;

	if (sourceView.backgroundColor) {
		self.backgroundColor = sourceView.backgroundColor;
	}
	self.opaque = sourceView.opaque;
	self.clipsToBounds = sourceView.clipsToBounds;

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
		target.backgroundColor = sourceEffectView.backgroundColor;
		target.opaque = sourceEffectView.opaque;
		target.clipsToBounds = sourceEffectView.clipsToBounds;
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
				}
				@catch (__unused NSException *exception) {
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

	[self _captureBackgroundBaseAlphas];
	[self _applyBackgroundOpacity];
	[self setNeedsLayout];
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

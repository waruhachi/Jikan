#import "JikanPlatterMaterial.h"

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

@interface JikanPlatterMaterial () {
	__weak UIView *_containerView;
	UIView *_backgroundView;
	UIView *_styleOverlayView;
	UIView *_contentTintReplicaView;
	BOOL _usesLiquidGlass;
	BOOL _usesLockScreenGlass;
	float _glassLuminance;
	CGFloat _backgroundBaseAlpha;
	CGFloat _styleOverlayBaseAlpha;
	CGFloat _contentTintBaseAlpha;
}
@end

@implementation JikanPlatterMaterial

- (instancetype)initWithContainerView:(UIView *)container {
	self = [super init];
	if (self) {
		_containerView = container;
		[self _setupSubviews];
		[self _captureBackgroundBaseAlphas];
	}
	return self;
}

- (void)_setupSubviews {
	UIView *container = _containerView;
	UIView *glassView = [[UIView alloc] init];
	_usesLockScreenGlass = TTConfigureLockScreenGlass(glassView, container);
	if (_usesLockScreenGlass) {
		_backgroundView = glassView;
		_usesLiquidGlass = YES;
	} else {
		UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:nil];
		_usesLiquidGlass = JikanConfigureLiquidGlass(effectView);
		if (!_usesLiquidGlass) effectView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
		_backgroundView = effectView;
	}
	_backgroundView.translatesAutoresizingMaskIntoConstraints = NO;
	_backgroundView.clipsToBounds = !_usesLiquidGlass || _usesLockScreenGlass;
	_backgroundView.userInteractionEnabled = NO;
	[container addSubview:_backgroundView];
	[container sendSubviewToBack:_backgroundView];

	_styleOverlayView = [[UIView alloc] init];
	_styleOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
	_styleOverlayView.userInteractionEnabled = NO;
	_styleOverlayView.backgroundColor = [UIColor blackColor];
	_styleOverlayView.alpha = _usesLiquidGlass ? 0.0 : 0.12;
	_styleOverlayView.hidden = _usesLiquidGlass;
	_styleOverlayView.layer.compositingFilter = @"darkenSourceOver";
	[container addSubview:_styleOverlayView];

	_contentTintReplicaView = [[UIView alloc] init];
	_contentTintReplicaView.translatesAutoresizingMaskIntoConstraints = NO;
	_contentTintReplicaView.userInteractionEnabled = NO;
	_contentTintReplicaView.hidden = YES;
	_contentTintReplicaView.alpha = 0.0;
	[container addSubview:_contentTintReplicaView];
}

- (void)setupConstraints {
	UIView *container = _containerView;
	[NSLayoutConstraint activateConstraints:@[
		[_backgroundView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
		[_backgroundView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
		[_backgroundView.topAnchor constraintEqualToAnchor:container.topAnchor],
		[_backgroundView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

		[_styleOverlayView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
		[_styleOverlayView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
		[_styleOverlayView.topAnchor constraintEqualToAnchor:container.topAnchor],
		[_styleOverlayView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

		[_contentTintReplicaView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
		[_contentTintReplicaView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
		[_contentTintReplicaView.topAnchor constraintEqualToAnchor:container.topAnchor],
		[_contentTintReplicaView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
	]];
}

- (void)layoutMaterialViews {
	UIView *container = _containerView;

	container.layer.cornerRadius = container.bounds.size.height / 2;
	container.clipsToBounds = NO;
	if (_backgroundView && (!_usesLiquidGlass || _usesLockScreenGlass)) {
		_backgroundView.layer.cornerRadius = _backgroundView.bounds.size.height / 2;
		_backgroundView.layer.cornerCurve = container.layer.cornerCurve;
		_backgroundView.clipsToBounds = YES;
	}
	if (_styleOverlayView) {
		_styleOverlayView.layer.cornerRadius = _styleOverlayView.bounds.size.height / 2;
		_styleOverlayView.layer.cornerCurve = container.layer.cornerCurve;
		_styleOverlayView.clipsToBounds = YES;
	}
	if (_contentTintReplicaView) {
		_contentTintReplicaView.layer.cornerRadius = _contentTintReplicaView.bounds.size.height / 2;
		_contentTintReplicaView.layer.cornerCurve = container.layer.cornerCurve;
		_contentTintReplicaView.clipsToBounds = YES;
	}
}

- (void)_captureBackgroundBaseAlphas {
	_backgroundBaseAlpha = _backgroundView ? _backgroundView.alpha : 1.0;
	_styleOverlayBaseAlpha = _styleOverlayView ? _styleOverlayView.alpha : 0.12;
	_contentTintBaseAlpha = _contentTintReplicaView ? _contentTintReplicaView.alpha : 0.0;
}

- (void)applyOpacity:(CGFloat)factor {
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
	if (![_backgroundView isKindOfClass:[UIVisualEffectView class]]) return;
	UIVisualEffectView *ev = (UIVisualEffectView *)_backgroundView;
	if (effect) {
		ev.effect = effect;
	} else if (!ev.effect) {
		ev.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
	}
	[ev setNeedsLayout];
	[ev layoutIfNeeded];
}

- (void)applyQuickActionBackgroundStyleFromView:(UIView *)sourceView opacity:(CGFloat)opacity {
	if (_usesLiquidGlass) return;
	if (!sourceView) return;

	UIView *container = _containerView;
	if (sourceView.backgroundColor) {
		container.backgroundColor = sourceView.backgroundColor;
	}
	container.opaque = sourceView.opaque;
	container.clipsToBounds = sourceView.clipsToBounds;

	UIVisualEffectView *sourceEffectView = nil;
	if ([sourceView isKindOfClass:[UIVisualEffectView class]]) {
		sourceEffectView = (UIVisualEffectView *)sourceView;
	} else {
		sourceEffectView = (UIVisualEffectView *)TTFindFirstSubviewWithClassNameFragment(sourceView, @"UIVisualEffectView");
	}

	if ([_backgroundView isKindOfClass:[UIVisualEffectView class]] && sourceEffectView) {
		UIVisualEffectView *target = (UIVisualEffectView *)_backgroundView;
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

	container.layer.cornerCurve = sourceView.layer.cornerCurve;
	container.layer.cornerRadius = container.bounds.size.height / 2;
	TTCopyLayerVisualProperties(sourceView.layer, container.layer);
	container.layer.cornerRadius = container.bounds.size.height / 2;

	if (_backgroundView) {
		TTCopyLayerVisualProperties(sourceView.layer, _backgroundView.layer);
		_backgroundView.layer.cornerRadius = container.bounds.size.height / 2;
	}

	if (_styleOverlayView) {
		UIView *sourceOverlay = TTFindFirstSubviewWithClassNameFragment(sourceView, @"_UIVisualEffectSubview");
		if (sourceOverlay) {
			_styleOverlayView.hidden = sourceOverlay.hidden;
			_styleOverlayView.alpha = sourceOverlay.alpha;
			_styleOverlayView.backgroundColor = sourceOverlay.backgroundColor;
			_styleOverlayView.layer.compositingFilter = sourceOverlay.layer.compositingFilter;
			TTCopyLayerVisualProperties(sourceOverlay.layer, _styleOverlayView.layer);
		} else {
			_styleOverlayView.hidden = NO;
			_styleOverlayView.alpha = 0.12;
			_styleOverlayView.backgroundColor = [UIColor blackColor];
			_styleOverlayView.layer.compositingFilter = @"darkenSourceOver";
		}
	}

	if (_contentTintReplicaView) {
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
			_contentTintReplicaView.hidden = sourceTintReplica.hidden;
			_contentTintReplicaView.alpha = sourceTintReplica.alpha;
			_contentTintReplicaView.backgroundColor = sourceTintReplica.backgroundColor;
			_contentTintReplicaView.layer.compositingFilter = sourceTintReplica.layer.compositingFilter;
			TTCopyLayerVisualProperties(sourceTintReplica.layer, _contentTintReplicaView.layer);
		} else {
			_contentTintReplicaView.hidden = YES;
			_contentTintReplicaView.alpha = 0.0;
		}
	}

	[self _captureBackgroundBaseAlphas];
	[self applyOpacity:opacity];
	[container setNeedsLayout];
}

@end

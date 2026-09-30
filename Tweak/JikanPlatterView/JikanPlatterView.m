#import "JikanPlatterView.h"

extern BOOL isCharging;

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

static BOOL TTShowAfterFullChargeEnabled(void) {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"moe.waru.jikan.preferences"];
	if (![prefs objectForKey:@"showAfterFullCharge"]) return NO;
	return [prefs boolForKey:@"showAfterFullCharge"];
}

static CGFloat TTWiggleRandomOffset(void) {
	return ((arc4random_uniform(1000) / 1000.0) - 0.5) * 0.03;
}

static UIColor *TTBoltColorForSpeed(NSString *speed) {
	if ([speed isEqualToString:@"slow"]) {
		return [UIColor systemYellowColor];
	}
	return [UIColor systemGreenColor];
}

static CGFloat TTPillBackgroundOpacity(void) {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"moe.waru.jikan.preferences"];
	id value = [prefs objectForKey:@"pillBackgroundOpacityPercent"];
	double percent = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 100.0;
	if (!isfinite(percent)) percent = 100.0;
	percent = MAX(0.0, MIN(100.0, percent));
	return (CGFloat)(percent / 100.0);
}

static const CGFloat kTTPreviewOutlineLineWidth = 2.5;
static const CGFloat kTTPreviewOutlineGap = 2.0;

@implementation JikanPlatterView

- (void)_setupProgressRingAppearance {
	_redesignContentView = [[UIView alloc] init];
	_redesignContentView.userInteractionEnabled = NO;
	[self addSubview:_redesignContentView];

	_redesignRingView = [[UIView alloc] init];
	[_redesignContentView addSubview:_redesignRingView];
	_redesignRingTrack = [CAShapeLayer layer];
	_redesignRingTrack.fillColor = UIColor.clearColor.CGColor;
	_redesignRingTrack.strokeColor = [UIColor colorWithWhite:0.54 alpha:0.56].CGColor;
	_redesignRingTrack.lineCap = kCALineCapRound;
	[_redesignRingView.layer addSublayer:_redesignRingTrack];
	_redesignRingProgress = [CAShapeLayer layer];
	_redesignRingProgress.fillColor = UIColor.clearColor.CGColor;
	_redesignRingProgress.strokeColor = UIColor.systemGreenColor.CGColor;
	_redesignRingProgress.lineCap = kCALineCapRound;
	[_redesignRingView.layer addSublayer:_redesignRingProgress];

	UIImageSymbolConfiguration *boltConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightBold];
	UIImage *bolt = [[UIImage systemImageNamed:@"bolt.fill" withConfiguration:boltConfig] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	_redesignBoltView = [[UIImageView alloc] initWithImage:bolt];
	_redesignBoltView.tintColor = UIColor.systemGreenColor;
	_redesignBoltView.contentMode = UIViewContentModeScaleAspectFit;
	[_redesignRingView addSubview:_redesignBoltView];

	_redesignDivider = [[UIView alloc] init];
	_redesignDivider.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.33];
	[_redesignContentView addSubview:_redesignDivider];

	_redesignPrimaryLabel = [[UILabel alloc] init];
	_redesignPrimaryLabel.textColor = UIColor.whiteColor;
	_redesignPrimaryLabel.textAlignment = NSTextAlignmentLeft;
	_redesignPrimaryLabel.numberOfLines = 1;
	_redesignPrimaryLabel.lineBreakMode = NSLineBreakByClipping;
	[_redesignContentView addSubview:_redesignPrimaryLabel];
	_redesignSecondaryLabel = [[UILabel alloc] init];
	_redesignSecondaryLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.83];
	_redesignSecondaryLabel.textAlignment = NSTextAlignmentLeft;
	_redesignSecondaryLabel.numberOfLines = 1;
	_redesignSecondaryLabel.lineBreakMode = NSLineBreakByClipping;
	[_redesignContentView addSubview:_redesignSecondaryLabel];
	_redesignPrimaryLabel.text = _timeRemainingLabel.text;
	_redesignSecondaryLabel.text = _staticLabel.text;
}

- (void)_layoutProgressRingAppearance {
	CGFloat width = CGRectGetWidth(self.bounds);
	CGFloat height = CGRectGetHeight(self.bounds);
	if (width <= 0.0 || height <= 0.0) return;
	_redesignContentView.frame = self.bounds;
	CGFloat ringSize = MAX(24.0, height * 0.68);
	_redesignRingView.frame = CGRectMake(10.0, (height - ringSize) * 0.5, ringSize, ringSize);
	CGFloat lineWidth = MAX(2.5, ringSize * 0.09);
	CGFloat ringInset = lineWidth * 0.5 + 1.0;
	UIBezierPath *ringPath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(ringSize * 0.5, ringSize * 0.5)
															radius:ringSize * 0.5 - ringInset
														startAngle:(CGFloat)-M_PI_2
														  endAngle:(CGFloat)(M_PI * 1.5)
														 clockwise:YES];
	_redesignRingTrack.frame = _redesignRingView.bounds;
	_redesignRingProgress.frame = _redesignRingView.bounds;
	_redesignRingTrack.path = ringPath.CGPath;
	_redesignRingProgress.path = ringPath.CGPath;
	_redesignRingTrack.lineWidth = lineWidth;
	_redesignRingProgress.lineWidth = lineWidth;
	_redesignRingProgress.strokeEnd = MIN(1.0, MAX(0.0, (CGFloat)_latestDisplayPercent / MAX(1, _latestTargetPercent)));
	CGFloat boltSize = ringSize * 0.47;
	_redesignBoltView.frame = CGRectMake((ringSize - boltSize) * 0.5, (ringSize - boltSize) * 0.5, boltSize, boltSize);

	CGFloat dividerX = CGRectGetMaxX(_redesignRingView.frame) + 9.0;
	_redesignDivider.frame = CGRectMake(dividerX, height * 0.24, 1.0, height * 0.52);
	CGFloat textX = CGRectGetMaxX(_redesignDivider.frame) + 10.0;
	CGFloat textWidth = MAX(1.0, width - textX - 12.0);
	BOOL bold = UIAccessibilityIsBoldTextEnabled() || self.traitCollection.legibilityWeight == UILegibilityWeightBold;
	UIFont *primary = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:
			[UIFont monospacedDigitSystemFontOfSize:19.0 weight:bold ? UIFontWeightBold : UIFontWeightSemibold]
																	   compatibleWithTraitCollection:self.traitCollection];
	UIFont *secondary = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:
			[UIFont systemFontOfSize:12.0 weight:bold ? UIFontWeightSemibold : UIFontWeightMedium]
																			compatibleWithTraitCollection:self.traitCollection];
	CGFloat lowerScale = 0.0;
	CGFloat upperScale = 1.0;
	for (NSUInteger i = 0; i < 16; i++) {
		CGFloat scale = (lowerScale + upperScale) * 0.5;
		UIFont *p = [primary fontWithSize:primary.pointSize * scale];
		UIFont *s = [secondary fontWithSize:secondary.pointSize * scale];
		CGFloat pWidth = [_redesignPrimaryLabel.text sizeWithAttributes:@{NSFontAttributeName: p}].width;
		CGFloat sWidth = [_redesignSecondaryLabel.text sizeWithAttributes:@{NSFontAttributeName: s}].width;
		if (pWidth <= textWidth && sWidth <= textWidth && p.lineHeight + s.lineHeight + 1.0 <= height - 7.0)
			lowerScale = scale;
		else
			upperScale = scale;
	}
	_redesignPrimaryLabel.font = [primary fontWithSize:primary.pointSize * MAX(0.01, lowerScale)];
	_redesignSecondaryLabel.font = [secondary fontWithSize:secondary.pointSize * MAX(0.01, lowerScale)];
	CGFloat totalTextHeight = _redesignPrimaryLabel.font.lineHeight + _redesignSecondaryLabel.font.lineHeight + 1.0;
	CGFloat textY = (height - totalTextHeight) * 0.5;
	_redesignPrimaryLabel.frame = CGRectMake(textX, textY, textWidth, _redesignPrimaryLabel.font.lineHeight);
	_redesignSecondaryLabel.frame = CGRectMake(textX, CGRectGetMaxY(_redesignPrimaryLabel.frame) + 1.0, textWidth, _redesignSecondaryLabel.font.lineHeight);
}

- (void)_updatePillAppearance {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"moe.waru.jikan.preferences"];
	BOOL usesRing = [JikanPillAppearance(prefs) isEqualToString:JikanPillAppearanceProgressRing];
	if (_usesProgressRingAppearance == usesRing) return;
	_usesProgressRingAppearance = usesRing;
	_textStack.hidden = usesRing;
	_redesignContentView.hidden = !usesRing;
	[self setNeedsLayout];
}

- (void)_captureBackgroundBaseAlphas {
	_backgroundBaseAlpha = _backgroundView ? _backgroundView.alpha : 1.0;
	_styleOverlayBaseAlpha = _styleOverlayView ? _styleOverlayView.alpha : 0.12;
	_contentTintBaseAlpha = _contentTintReplicaView ? _contentTintReplicaView.alpha : 0.0;
}

- (void)_applyBackgroundOpacity {
	CGFloat factor = TTPillBackgroundOpacity();
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

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_chargingStateChanged:) name:JikanChargingStateChangedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textSettingsChanged:) name:UIAccessibilityBoldTextStatusDidChangeNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textSettingsChanged:) name:UIContentSizeCategoryDidChangeNotification object:nil];
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

	[self applyBatterySnapshot:[TT100 latestSnapshot]];
	[self _preferencesPossiblyChanged:nil];
	[self _updateTapGestureState];
	[self _applyBackgroundOpacity];
}

- (void)applyBatterySnapshot:(NSDictionary *)snapshot {
	[self _reloadStackPreferences];
	[self _updatePillAppearance];
	_latestBatteryInfo = [snapshot[@"batteryInfo"] isKindOfClass:[NSDictionary class]] ? snapshot[@"batteryInfo"] : nil;
	_latestTimeString = [snapshot[@"timeString"] isKindOfClass:[NSString class]] ? snapshot[@"timeString"] : JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
	_latestHasEstimate = [snapshot[@"hasEstimate"] boolValue];
	_latestTargetReached = [snapshot[@"targetReached"] boolValue];
	_latestDisplayPercent = MAX(0, MIN(100, [snapshot[@"displayPercent"] integerValue]));
	_latestTargetPercent = MAX(1, MIN(100, snapshot[@"targetPercent"] ? [snapshot[@"targetPercent"] integerValue] : [TT100 targetPercent]));
	if (!self.window) return;
	NSString *speed = [snapshot[@"chargingSpeed"] isKindOfClass:[NSString class]] ? snapshot[@"chargingSpeed"] : @"normal";
	_boltImageView.tintColor = TTBoltColorForSpeed(speed);
	_redesignBoltView.tintColor = _boltImageView.tintColor;
	_redesignRingProgress.strokeColor = _boltImageView.tintColor.CGColor;
	[self updateWithTimeString:_latestTimeString];
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
	if (_usesProgressRingAppearance) [self _layoutProgressRingAppearance];
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

	_containerView = [[UIView alloc] init];
	_containerView.translatesAutoresizingMaskIntoConstraints = NO;

	UIImage *boltImage = [[UIImage systemImageNamed:@"bolt.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	_boltImageView = [[UIImageView alloc] initWithImage:boltImage];
	_boltImageView.tintColor = [UIColor greenColor];
	_boltImageView.translatesAutoresizingMaskIntoConstraints = NO;
	[_containerView addSubview:_boltImageView];

	_timeRemainingLabel = [[UILabel alloc] init];
	_timeRemainingLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_timeRemainingLabel.textColor = [UIColor whiteColor];
	_timeRemainingLabel.adjustsFontForContentSizeCategory = NO;
	_timeRemainingLabel.numberOfLines = 1;
	_timeRemainingLabel.textAlignment = NSTextAlignmentCenter;
	_timeRemainingLabel.text = JikanLocalizedString(@"jikan.platter.preview.time", @"0 minutes");
	[_containerView addSubview:_timeRemainingLabel];

	_staticLabel = [[UILabel alloc] init];
	_staticLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_staticLabel.textColor = [UIColor whiteColor];
	_staticLabel.adjustsFontForContentSizeCategory = NO;
	_staticLabel.numberOfLines = 1;
	_staticLabel.textAlignment = NSTextAlignmentCenter;
	_staticLabel.text = [self _estimateSubtitle];
	_textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_containerView, _staticLabel]];
	_textStack.axis = UILayoutConstraintAxisVertical;
	_textStack.alignment = UIStackViewAlignmentCenter;
	_textStack.spacing = 2.0;
	_textStack.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:_textStack];
	[self _setupProgressRingAppearance];
	_redesignContentView.hidden = YES;
	[self _updatePillAppearance];
	[_timeRemainingLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
	[_staticLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

	_tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTap:)];
	[self addGestureRecognizer:_tapGesture];
	[self _updateTapGestureState];
	[self _captureBackgroundBaseAlphas];
	[self _applyBackgroundOpacity];

	[self _updateTypographyForCurrentSize];
}

- (void)_updateTypographyForCurrentSize {
	BOOL bold = UIAccessibilityIsBoldTextEnabled() || self.traitCollection.legibilityWeight == UILegibilityWeightBold;
	UIFont *primary = [UIFont monospacedDigitSystemFontOfSize:20.0 weight:bold ? UIFontWeightBold : UIFontWeightSemibold];
	UIFont *secondary = [UIFont systemFontOfSize:14.0 weight:bold ? UIFontWeightSemibold : UIFontWeightMedium];
	_timeRemainingLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:primary compatibleWithTraitCollection:self.traitCollection];
	_staticLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:secondary compatibleWithTraitCollection:self.traitCollection];
}

- (void)_contentSizeChanged {
	self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", _timeRemainingLabel.text ?: @"", _staticLabel.text ?: @""];
	_redesignPrimaryLabel.text = _timeRemainingLabel.text;
	_redesignSecondaryLabel.text = _staticLabel.text;
	[self setNeedsLayout];
	if (self.contentSizeDidChange) self.contentSizeDidChange();
}

- (void)_textSettingsChanged:(NSNotification *)notification {
#pragma unused(notification)
	[self _updateTypographyForCurrentSize];
	[self _contentSizeChanged];
}

- (void)_localeChanged:(NSNotification *)notification {
#pragma unused(notification)
	[self _renderCurrentItem];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	if (![self.traitCollection.preferredContentSizeCategory isEqual:previousTraitCollection.preferredContentSizeCategory] ||
		self.traitCollection.legibilityWeight != previousTraitCollection.legibilityWeight) {
		[self _textSettingsChanged:nil];
	}
}

- (CGSize)preferredSizeForMaximumWidth:(CGFloat)width height:(CGFloat)height {
	[self _updatePillAppearance];
	if (_usesProgressRingAppearance) {
		BOOL bold = UIAccessibilityIsBoldTextEnabled() || self.traitCollection.legibilityWeight == UILegibilityWeightBold;
		UIFont *primaryFont = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:
				[UIFont monospacedDigitSystemFontOfSize:19.0 weight:bold ? UIFontWeightBold : UIFontWeightSemibold]
																			   compatibleWithTraitCollection:self.traitCollection];
		UIFont *secondaryFont = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:
				[UIFont systemFontOfSize:12.0 weight:bold ? UIFontWeightSemibold : UIFontWeightMedium]
																					compatibleWithTraitCollection:self.traitCollection];
		CGFloat labelWidth = MAX([_redesignPrimaryLabel.text sizeWithAttributes:@{NSFontAttributeName: primaryFont}].width,
			[_redesignSecondaryLabel.text sizeWithAttributes:@{NSFontAttributeName: secondaryFont}].width);
		CGFloat ringSize = MAX(24.0, height * 0.68);
		CGFloat desiredWidth = ceil(10.0 + ringSize + 9.0 + 1.0 + 10.0 + labelWidth + 12.0);
		return CGSizeMake(MIN(width, MAX(116.0, desiredWidth)), height);
	}
	// Start with the user's text size and weight, then fit both lines together
	// inside the capsule. Text must never increase the pill's height.
	[self _updateTypographyForCurrentSize];
	CGSize primary = [_timeRemainingLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
	CGSize secondary = [_staticLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
	CGFloat desiredWidth = MIN(width, MAX(96.0, ceil(MAX(primary.width + 14.0, secondary.width) + 32.0)));
	CGFloat contentWidth = MAX(1.0, desiredWidth - 33.0);
	CGFloat contentHeight = MAX(1.0, height - 17.0);
	UIFont *primaryFont = _timeRemainingLabel.font;
	UIFont *secondaryFont = _staticLabel.font;
	CGFloat lowerScale = 0.0;
	CGFloat upperScale = 1.0;
	CGFloat scale = 1.0;
	// Optical spacing changes with font size. Measure the fitted fonts instead
	// of assuming that their text widths scale linearly with the point size.
	for (NSUInteger attempt = 0; attempt < 12; attempt++) {
		_timeRemainingLabel.font = [primaryFont fontWithSize:primaryFont.pointSize * scale];
		_staticLabel.font = [secondaryFont fontWithSize:secondaryFont.pointSize * scale];
		primary = [_timeRemainingLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
		secondary = [_staticLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
		BOOL fits = primary.width + 14.0 <= contentWidth && secondary.width <= contentWidth &&
			MAX(10.0, primary.height) + _textStack.spacing + secondary.height <= contentHeight;
		if (fits) {
			lowerScale = scale;
			if (scale == 1.0) break;
		} else {
			upperScale = scale;
		}
		scale = (lowerScale + upperScale) * 0.5;
	}
	_timeRemainingLabel.font = [primaryFont fontWithSize:primaryFont.pointSize * lowerScale];
	_staticLabel.font = [secondaryFont fontWithSize:secondaryFont.pointSize * lowerScale];
	return CGSizeMake(desiredWidth, height);
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

		[_textStack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
		[_textStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
		[_textStack.widthAnchor constraintEqualToAnchor:self.widthAnchor constant:-32.0],
		[_textStack.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:8.0],
		[_textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-8.0],
		[_containerView.widthAnchor constraintLessThanOrEqualToAnchor:_textStack.widthAnchor],
		[_containerView.heightAnchor constraintGreaterThanOrEqualToConstant:10.0],

		[_boltImageView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor],
		[_boltImageView.centerYAnchor constraintEqualToAnchor:_timeRemainingLabel.centerYAnchor],
		[_boltImageView.widthAnchor constraintEqualToConstant:10.0],
		[_boltImageView.heightAnchor constraintEqualToConstant:10.0],

		[_timeRemainingLabel.leadingAnchor constraintEqualToAnchor:_boltImageView.trailingAnchor constant:4.0],
		[_timeRemainingLabel.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor],
		[_timeRemainingLabel.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
		[_timeRemainingLabel.topAnchor constraintEqualToAnchor:_containerView.topAnchor],
		[_staticLabel.widthAnchor constraintLessThanOrEqualToAnchor:_textStack.widthAnchor],
	]];
}

- (NSString *)_estimateSubtitle {
	NSInteger target = _latestTargetPercent > 0 ? _latestTargetPercent : [TT100 targetPercent];
	if (target < 100) return [NSString stringWithFormat:JikanLocalizedString(@"jikan.platter.label.until_target", @"until %ld%% charged"), (long)target];
	return JikanLocalizedString(@"jikan.platter.label.until_fully_charged", @"until fully charged");
}

- (void)updateWithTimeString:(NSString *)timeString {
	if (timeString.length > 0) _latestTimeString = timeString;
	[self _renderCurrentItem];
}

- (void)_reloadStackPreferences {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"moe.waru.jikan.preferences"];
	NSArray<NSString *> *items = JikanStackItems(prefs);
	if (![_activeStackItems isEqualToArray:items]) _activeStackItems = [items copy];
	if (![_activeStackItems containsObject:_selectedStackItem]) _selectedStackItem = JikanStackEstimate;
	[self _updateTapGestureState];
}

- (void)_renderCurrentItem {
	NSString *item = _selectedStackItem ?: JikanStackEstimate;
	if ([item isEqualToString:JikanStackWattage]) {
		[self _updateWattageLabel];
		return;
	}
	if ([item isEqualToString:JikanStackTemperature]) {
		NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"moe.waru.jikan.preferences"];
		NSDictionary *batteryInfo = _previewMode ? @{@"Temperature": @3700} : _latestBatteryInfo;
		_timeRemainingLabel.text = JikanFormattedBatteryTemperature(batteryInfo, JikanResolvedTemperatureUnit(prefs)) ?: JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
		_staticLabel.text = JikanLocalizedString(@"jikan.platter.label.battery_temperature", @"battery temperature");
		[self _contentSizeChanged];
		return;
	}
	if ([item isEqualToString:JikanStackVoltage]) {
		_timeRemainingLabel.text = JikanFormattedBatteryVoltage(_previewMode ? @{@"Voltage": @4000} : _latestBatteryInfo) ?: JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
		_staticLabel.text = JikanLocalizedString(@"jikan.platter.label.battery_voltage", @"battery voltage");
		[self _contentSizeChanged];
		return;
	}
	if (_latestTargetReached && TTShowAfterFullChargeEnabled() && !_previewMode) {
		_timeRemainingLabel.text = [NSString stringWithFormat:@"%ld%%", (long)_latestDisplayPercent];
		_staticLabel.text = JikanLocalizedString(@"jikan.platter.label.charged", @"charged");
	} else {
		_timeRemainingLabel.text = _previewMode ? JikanLocalizedString(@"jikan.platter.preview.eta", @"1 hr 23 min") : _latestTimeString;
		_staticLabel.text = [self _estimateSubtitle];
	}
	[self _contentSizeChanged];
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

- (void)_chargingStateChanged:(NSNotification *)notification {
#pragma unused(notification)
	if (!self.window) return;
	if (!isCharging) {
		[self enterEditMode:NO];
		_selectedStackItem = JikanStackEstimate;
	}
	[self _preferencesPossiblyChanged:nil];
}

- (void)_preferencesPossiblyChanged:(NSNotification *)notification {
#pragma unused(notification)
	[self _reloadStackPreferences];
	[self _updatePillAppearance];
	_latestTargetPercent = [TT100 targetPercent];
	[self updateWithTimeString:_latestTimeString ?: JikanLocalizedString(@"jikan.tt100.value.na", @"N/A")];
	[self _applyBackgroundOpacity];
}

- (void)_updateTapGestureState {
	if (!_tapGesture) return;
	_tapGesture.enabled = _activeStackItems.count > 1 && (isCharging || _previewMode) && !_editingMode;
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
	if (_activeStackItems.count < 2 || (!isCharging && !_previewMode) || _editingMode) return;
	NSUInteger index = [_activeStackItems indexOfObject:_selectedStackItem];
	_selectedStackItem = _activeStackItems[(index == NSNotFound ? 0 : index + 1) % _activeStackItems.count];
	[self _renderCurrentItem];
	if (UIAccessibilityIsVoiceOverRunning()) UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.accessibilityLabel);
}

- (void)_updateWattageLabel {
	NSDictionary *batteryInfo = _latestBatteryInfo;

	double watts = _previewMode ? 5.0 : [TT100 effectiveChargingWattageWithBatteryInfo:batteryInfo];

	if (isfinite(watts) && watts >= 0) {
		NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
		formatter.locale = [NSLocale currentLocale];
		formatter.numberStyle = NSNumberFormatterDecimalStyle;
		formatter.minimumFractionDigits = 1;
		formatter.maximumFractionDigits = 1;
		NSString *number = [formatter stringFromNumber:@(watts)];
		_timeRemainingLabel.text = number ? [NSString stringWithFormat:@"%@ W", number] : JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
	} else {
		_timeRemainingLabel.text = JikanLocalizedString(@"jikan.tt100.value.na", @"N/A");
	}
	_staticLabel.text = JikanLocalizedString(@"jikan.platter.label.current_wattage", @"current wattage");
	[self _contentSizeChanged];
}

@end

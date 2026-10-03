#import "JikanPillContentView.h"

@interface JikanPillContentView () {
	UILabel *_staticLabel;
	UILabel *_timeRemainingLabel;
	UIView *_containerView;
	UIStackView *_textStack;
	UIImageView *_boltImageView;
	UIView *_ringContentView;
	UIView *_ringView;
	UIView *_divider;
	UILabel *_ringPrimaryLabel;
	UILabel *_ringSecondaryLabel;
	UIImageView *_ringBoltView;
	CAShapeLayer *_ringTrack;
	CAShapeLayer *_ringProgress;
}
@end

@implementation JikanPillContentView

- (instancetype)init {
	return [self initWithFrame:CGRectZero];
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.userInteractionEnabled = NO;
		_appearance = JikanPillAppearanceClassic;
		[self _setupClassicAppearance];
		[self _setupConstraints];
		[self _updateTypographyForCurrentSize];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textSettingsChanged:) name:UIAccessibilityBoldTextStatusDidChangeNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textSettingsChanged:) name:UIContentSizeCategoryDidChangeNotification object:nil];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setAppearance:(NSString *)appearance {
	NSString *value = [appearance isEqualToString:JikanPillAppearanceProgressRing] ? JikanPillAppearanceProgressRing : JikanPillAppearanceClassic;
	if ([_appearance isEqualToString:value]) return;
	_appearance = [value copy];
	BOOL usesRing = [_appearance isEqualToString:JikanPillAppearanceProgressRing];
	_textStack.hidden = usesRing;
	_ringContentView.hidden = !usesRing;
	[self setNeedsLayout];
}

- (void)applyContent:(JikanPillContent *)content {
	_content = content;
	_timeRemainingLabel.text = content.primaryText;
	_staticLabel.text = content.secondaryText;
	_ringPrimaryLabel.text = content.primaryText;
	_ringSecondaryLabel.text = content.secondaryText;
	[self _updateColors];
	[self setNeedsLayout];
	if (self.contentSizeDidChange) self.contentSizeDidChange();
}

- (void)setAdaptsToSystemAppearance:(BOOL)adaptsToSystemAppearance {
	if (_adaptsToSystemAppearance == adaptsToSystemAppearance) return;
	_adaptsToSystemAppearance = adaptsToSystemAppearance;
	[self _updateColors];
}

- (void)_updateColors {
	_timeRemainingLabel.textColor = _adaptsToSystemAppearance ? UIColor.labelColor : UIColor.whiteColor;
	_staticLabel.textColor = _adaptsToSystemAppearance ? UIColor.secondaryLabelColor : UIColor.whiteColor;
	_ringPrimaryLabel.textColor = _adaptsToSystemAppearance ? UIColor.labelColor : UIColor.whiteColor;
	_ringSecondaryLabel.textColor = _adaptsToSystemAppearance ? UIColor.secondaryLabelColor : [UIColor colorWithWhite:1.0 alpha:0.83];
	_divider.backgroundColor = _adaptsToSystemAppearance ? UIColor.separatorColor : [UIColor colorWithWhite:1.0 alpha:0.33];
	UIColor *track = _adaptsToSystemAppearance ? UIColor.tertiaryLabelColor : [UIColor colorWithWhite:0.54 alpha:0.56];
	_ringTrack.strokeColor = [track resolvedColorWithTraitCollection:self.traitCollection].CGColor;
	UIColor *color = [_content.chargingSpeed isEqualToString:@"slow"] ? UIColor.systemYellowColor : UIColor.systemGreenColor;
	_boltImageView.tintColor = color;
	_ringBoltView.tintColor = color;
	_ringProgress.strokeColor = [color resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

- (void)_textSettingsChanged:(NSNotification *)notification {
#pragma unused(notification)
	[self _updateTypographyForCurrentSize];
	[self setNeedsLayout];
	if (self.contentSizeDidChange) self.contentSizeDidChange();
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
		[self _updateColors];
	}
	if (![self.traitCollection.preferredContentSizeCategory isEqual:previousTraitCollection.preferredContentSizeCategory] ||
		self.traitCollection.legibilityWeight != previousTraitCollection.legibilityWeight) {
		[self _textSettingsChanged:nil];
	}
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if ([self.appearance isEqualToString:JikanPillAppearanceProgressRing]) {
		[self _layoutProgressRingAppearance];
	} else if (CGRectGetWidth(self.bounds) > 0.0 && CGRectGetHeight(self.bounds) > 0.0) {
		[self preferredSizeForMaximumWidth:CGRectGetWidth(self.bounds) height:CGRectGetHeight(self.bounds)];
	}
}

- (void)_setupClassicAppearance {
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
	_timeRemainingLabel.text = @"";
	[_containerView addSubview:_timeRemainingLabel];

	_staticLabel = [[UILabel alloc] init];
	_staticLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_staticLabel.textColor = [UIColor whiteColor];
	_staticLabel.adjustsFontForContentSizeCategory = NO;
	_staticLabel.numberOfLines = 1;
	_staticLabel.textAlignment = NSTextAlignmentCenter;
	_staticLabel.text = @"";
	_textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_containerView, _staticLabel]];
	_textStack.axis = UILayoutConstraintAxisVertical;
	_textStack.alignment = UIStackViewAlignmentCenter;
	_textStack.spacing = 2.0;
	_textStack.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:_textStack];
	[self _setupProgressRingAppearance];
	_ringContentView.hidden = YES;
	[_timeRemainingLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
	[_staticLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
}

- (void)_setupProgressRingAppearance {
	_ringContentView = [[UIView alloc] init];
	_ringContentView.userInteractionEnabled = NO;
	[self addSubview:_ringContentView];

	_ringView = [[UIView alloc] init];
	[_ringContentView addSubview:_ringView];
	_ringTrack = [CAShapeLayer layer];
	_ringTrack.fillColor = UIColor.clearColor.CGColor;
	_ringTrack.strokeColor = [UIColor colorWithWhite:0.54 alpha:0.56].CGColor;
	_ringTrack.lineCap = kCALineCapRound;
	[_ringView.layer addSublayer:_ringTrack];
	_ringProgress = [CAShapeLayer layer];
	_ringProgress.fillColor = UIColor.clearColor.CGColor;
	_ringProgress.strokeColor = UIColor.systemGreenColor.CGColor;
	_ringProgress.lineCap = kCALineCapRound;
	[_ringView.layer addSublayer:_ringProgress];

	UIImageSymbolConfiguration *boltConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightBold];
	UIImage *bolt = [[UIImage systemImageNamed:@"bolt.fill" withConfiguration:boltConfig] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	_ringBoltView = [[UIImageView alloc] initWithImage:bolt];
	_ringBoltView.tintColor = UIColor.systemGreenColor;
	_ringBoltView.contentMode = UIViewContentModeScaleAspectFit;
	[_ringView addSubview:_ringBoltView];

	_divider = [[UIView alloc] init];
	_divider.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.33];
	[_ringContentView addSubview:_divider];

	_ringPrimaryLabel = [[UILabel alloc] init];
	_ringPrimaryLabel.textColor = UIColor.whiteColor;
	_ringPrimaryLabel.textAlignment = NSTextAlignmentLeft;
	_ringPrimaryLabel.numberOfLines = 1;
	_ringPrimaryLabel.lineBreakMode = NSLineBreakByClipping;
	[_ringContentView addSubview:_ringPrimaryLabel];
	_ringSecondaryLabel = [[UILabel alloc] init];
	_ringSecondaryLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.83];
	_ringSecondaryLabel.textAlignment = NSTextAlignmentLeft;
	_ringSecondaryLabel.numberOfLines = 1;
	_ringSecondaryLabel.lineBreakMode = NSLineBreakByClipping;
	[_ringContentView addSubview:_ringSecondaryLabel];
	_ringPrimaryLabel.text = _timeRemainingLabel.text;
	_ringSecondaryLabel.text = _staticLabel.text;
}

- (void)_layoutProgressRingAppearance {
	CGFloat width = CGRectGetWidth(self.bounds);
	CGFloat height = CGRectGetHeight(self.bounds);
	if (width <= 0.0 || height <= 0.0) return;
	_ringContentView.frame = self.bounds;
	CGFloat ringSize = MAX(24.0, height * 0.68);
	_ringView.frame = CGRectMake(10.0, (height - ringSize) * 0.5, ringSize, ringSize);
	CGFloat lineWidth = MAX(2.5, ringSize * 0.09);
	CGFloat ringInset = lineWidth * 0.5 + 1.0;
	UIBezierPath *ringPath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(ringSize * 0.5, ringSize * 0.5)
															radius:ringSize * 0.5 - ringInset
														startAngle:(CGFloat)-M_PI_2
														  endAngle:(CGFloat)(M_PI * 1.5)
														 clockwise:YES];
	_ringTrack.frame = _ringView.bounds;
	_ringProgress.frame = _ringView.bounds;
	_ringTrack.path = ringPath.CGPath;
	_ringProgress.path = ringPath.CGPath;
	_ringTrack.lineWidth = lineWidth;
	_ringProgress.lineWidth = lineWidth;
	_ringProgress.strokeEnd = _content.progress;
	CGFloat boltSize = ringSize * 0.47;
	_ringBoltView.frame = CGRectMake((ringSize - boltSize) * 0.5, (ringSize - boltSize) * 0.5, boltSize, boltSize);

	CGFloat dividerX = CGRectGetMaxX(_ringView.frame) + 9.0;
	_divider.frame = CGRectMake(dividerX, height * 0.24, 1.0, height * 0.52);
	CGFloat textX = CGRectGetMaxX(_divider.frame) + 10.0;
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
		CGFloat pWidth = [_ringPrimaryLabel.text sizeWithAttributes:@{NSFontAttributeName: p}].width;
		CGFloat sWidth = [_ringSecondaryLabel.text sizeWithAttributes:@{NSFontAttributeName: s}].width;
		if (pWidth <= textWidth && sWidth <= textWidth && p.lineHeight + s.lineHeight + 1.0 <= height - 7.0)
			lowerScale = scale;
		else
			upperScale = scale;
	}
	_ringPrimaryLabel.font = [primary fontWithSize:primary.pointSize * MAX(0.01, lowerScale)];
	_ringSecondaryLabel.font = [secondary fontWithSize:secondary.pointSize * MAX(0.01, lowerScale)];
	CGFloat totalTextHeight = _ringPrimaryLabel.font.lineHeight + _ringSecondaryLabel.font.lineHeight + 1.0;
	CGFloat textY = (height - totalTextHeight) * 0.5;
	_ringPrimaryLabel.frame = CGRectMake(textX, textY, textWidth, _ringPrimaryLabel.font.lineHeight);
	_ringSecondaryLabel.frame = CGRectMake(textX, CGRectGetMaxY(_ringPrimaryLabel.frame) + 1.0, textWidth, _ringSecondaryLabel.font.lineHeight);
}

- (void)_updateTypographyForCurrentSize {
	BOOL bold = UIAccessibilityIsBoldTextEnabled() || self.traitCollection.legibilityWeight == UILegibilityWeightBold;
	UIFont *primary = [UIFont monospacedDigitSystemFontOfSize:20.0 weight:bold ? UIFontWeightBold : UIFontWeightSemibold];
	UIFont *secondary = [UIFont systemFontOfSize:14.0 weight:bold ? UIFontWeightSemibold : UIFontWeightMedium];
	_timeRemainingLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:primary compatibleWithTraitCollection:self.traitCollection];
	_staticLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:secondary compatibleWithTraitCollection:self.traitCollection];
}

- (CGSize)preferredSizeForMaximumWidth:(CGFloat)width height:(CGFloat)height {
	if ([self.appearance isEqualToString:JikanPillAppearanceProgressRing]) {
		BOOL bold = UIAccessibilityIsBoldTextEnabled() || self.traitCollection.legibilityWeight == UILegibilityWeightBold;
		UIFont *primaryFont = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:
				[UIFont monospacedDigitSystemFontOfSize:19.0 weight:bold ? UIFontWeightBold : UIFontWeightSemibold]
																			   compatibleWithTraitCollection:self.traitCollection];
		UIFont *secondaryFont = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:
				[UIFont systemFontOfSize:12.0 weight:bold ? UIFontWeightSemibold : UIFontWeightMedium]
																					compatibleWithTraitCollection:self.traitCollection];
		CGFloat labelWidth = MAX([_ringPrimaryLabel.text sizeWithAttributes:@{NSFontAttributeName: primaryFont}].width,
			[_ringSecondaryLabel.text sizeWithAttributes:@{NSFontAttributeName: secondaryFont}].width);
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

- (void)_setupConstraints {
	[NSLayoutConstraint activateConstraints:@[
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

@end

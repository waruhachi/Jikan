#import "JikanAppearanceCell.h"

@interface JikanAppearanceOptionView : UIControl
@property (nonatomic, assign) BOOL showsProgressRing;
@property (nonatomic, strong) UIView *samplePill;
@property (nonatomic, strong) UIView *ringView;
@property (nonatomic, strong) UIView *divider;
@property (nonatomic, strong) UIImageView *boltView;
@property (nonatomic, strong) UILabel *sampleTime;
@property (nonatomic, strong) UILabel *sampleSubtitle;
@property (nonatomic, strong) UIView *selectionCircle;
@property (nonatomic, strong) UIImageView *checkView;
@property (nonatomic, strong) CAShapeLayer *ringTrack;
@property (nonatomic, strong) CAShapeLayer *ringProgress;
- (instancetype)initWithProgressRing:(BOOL)progressRing;
@end

@implementation JikanAppearanceOptionView

- (instancetype)initWithProgressRing:(BOOL)progressRing {
	self = [super initWithFrame:CGRectZero];
	if (!self) return nil;
	_showsProgressRing = progressRing;
	self.isAccessibilityElement = YES;
	self.accessibilityTraits = UIAccessibilityTraitButton;
	self.accessibilityLabel = progressRing ? @"Progress Ring" : @"Classic";

	_samplePill = [[UIView alloc] init];
	_samplePill.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.94];
	_samplePill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
	_samplePill.layer.borderWidth = 1.0;
	_samplePill.clipsToBounds = YES;
	_samplePill.userInteractionEnabled = NO;
	[self addSubview:_samplePill];

	_ringView = [[UIView alloc] init];
	_ringView.hidden = !progressRing;
	[_samplePill addSubview:_ringView];
	_ringTrack = [CAShapeLayer layer];
	_ringTrack.fillColor = UIColor.clearColor.CGColor;
	_ringTrack.strokeColor = [UIColor colorWithWhite:0.55 alpha:0.7].CGColor;
	_ringTrack.lineWidth = 3.0;
	[_ringView.layer addSublayer:_ringTrack];
	_ringProgress = [CAShapeLayer layer];
	_ringProgress.fillColor = UIColor.clearColor.CGColor;
	_ringProgress.strokeColor = UIColor.systemGreenColor.CGColor;
	_ringProgress.lineWidth = 3.0;
	_ringProgress.lineCap = kCALineCapRound;
	_ringProgress.strokeEnd = 0.72;
	[_ringView.layer addSublayer:_ringProgress];

	_divider = [[UIView alloc] init];
	_divider.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.36];
	_divider.hidden = !progressRing;
	[_samplePill addSubview:_divider];

	UIImageSymbolConfiguration *boltConfig = [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightBold];
	_boltView = [[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:@"bolt.fill" withConfiguration:boltConfig] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
	_boltView.tintColor = UIColor.systemGreenColor;
	_boltView.contentMode = UIViewContentModeScaleAspectFit;
	[_samplePill addSubview:_boltView];

	_sampleTime = [[UILabel alloc] init];
	_sampleTime.text = JikanLocalizedString(@"jikan.platter.preview.eta", @"1 hr 23 min");
	_sampleTime.textColor = UIColor.whiteColor;
	_sampleTime.font = [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightSemibold];
	_sampleTime.textAlignment = progressRing ? NSTextAlignmentLeft : NSTextAlignmentCenter;
	_sampleTime.adjustsFontSizeToFitWidth = YES;
	_sampleTime.minimumScaleFactor = 0.4;
	[_samplePill addSubview:_sampleTime];

	_sampleSubtitle = [[UILabel alloc] init];
	_sampleSubtitle.text = [NSString stringWithFormat:JikanLocalizedString(@"jikan.platter.label.until_target", @"until %ld%% charged"), (long)95];
	_sampleSubtitle.textColor = [UIColor colorWithWhite:1.0 alpha:0.84];
	_sampleSubtitle.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
	_sampleSubtitle.textAlignment = progressRing ? NSTextAlignmentLeft : NSTextAlignmentCenter;
	_sampleSubtitle.adjustsFontSizeToFitWidth = YES;
	_sampleSubtitle.minimumScaleFactor = 0.4;
	[_samplePill addSubview:_sampleSubtitle];

	_selectionCircle = [[UIView alloc] init];
	_selectionCircle.userInteractionEnabled = NO;
	[self addSubview:_selectionCircle];
	_checkView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11.0 weight:UIImageSymbolWeightBold]]];
	_checkView.tintColor = UIColor.whiteColor;
	_checkView.contentMode = UIViewContentModeCenter;
	[_selectionCircle addSubview:_checkView];
	[self setSelected:NO];
	return self;
}

- (void)setSelected:(BOOL)selected {
	[super setSelected:selected];
	_selectionCircle.backgroundColor = selected ? UIColor.systemBlueColor : UIColor.clearColor;
	_selectionCircle.layer.borderColor = selected ? UIColor.clearColor.CGColor : UIColor.systemGray3Color.CGColor;
	_selectionCircle.layer.borderWidth = selected ? 0.0 : 1.7;
	_checkView.hidden = !selected;
	self.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat width = CGRectGetWidth(self.bounds);
	CGFloat pillWidth = MIN(174.0, MAX(100.0, width - 10.0));
	CGFloat pillHeight = 54.0;
	_samplePill.frame = CGRectMake((width - pillWidth) * 0.5, 12.0, pillWidth, pillHeight);
	_samplePill.layer.cornerRadius = pillHeight * 0.5;
	CGFloat contentX;
	CGFloat contentWidth;
	if (_showsProgressRing) {
		_ringView.frame = CGRectMake(9.0, 10.0, 34.0, 34.0);
		UIBezierPath *ringPath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(17.0, 17.0) radius:15.0
															startAngle:(CGFloat)-M_PI_2
															  endAngle:(CGFloat)(M_PI * 1.5)
															 clockwise:YES];
		_ringTrack.frame = _ringView.bounds;
		_ringProgress.frame = _ringView.bounds;
		_ringTrack.path = ringPath.CGPath;
		_ringProgress.path = ringPath.CGPath;
		_boltView.frame = CGRectMake(17.0, 19.0, 18.0, 18.0);
		_divider.frame = CGRectMake(51.0, 13.0, 1.0, 28.0);
		contentX = 59.0;
		contentWidth = MAX(1.0, pillWidth - contentX - 8.0);
	} else {
		CGFloat boltWidth = 10.0;
		CGFloat gap = 4.0;
		CGFloat textWidth = MIN(ceil([_sampleTime.text sizeWithAttributes:@{NSFontAttributeName: _sampleTime.font}].width), pillWidth - 18.0 - boltWidth - gap);
		CGFloat rowWidth = boltWidth + gap + textWidth;
		CGFloat rowX = (pillWidth - rowWidth) * 0.5;
		_boltView.frame = CGRectMake(rowX, 12.0, boltWidth, 16.0);
		contentX = rowX + boltWidth + gap;
		contentWidth = textWidth;
	}
	_sampleTime.frame = CGRectMake(contentX, 8.0, contentWidth, 22.0);
	_sampleSubtitle.frame = _showsProgressRing
		? CGRectMake(contentX, 30.0, contentWidth, 16.0)
		: CGRectMake(9.0, 30.0, pillWidth - 18.0, 16.0);
	_selectionCircle.frame = CGRectMake((width - 22.0) * 0.5, 80.0, 22.0, 22.0);
	_selectionCircle.layer.cornerRadius = 11.0;
	_checkView.frame = _selectionCircle.bounds;
}

@end

@interface JikanAppearanceCell ()
@property (nonatomic, strong) JikanAppearanceOptionView *classicOption;
@property (nonatomic, strong) JikanAppearanceOptionView *ringOption;
@end

@implementation JikanAppearanceCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
	self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
	if (!self) return nil;
	self.selectionStyle = UITableViewCellSelectionStyleNone;
	self.textLabel.hidden = YES;
	self.titleLabel.hidden = YES;
	UIStackView *choices = [[UIStackView alloc] init];
	choices.axis = UILayoutConstraintAxisHorizontal;
	choices.distribution = UIStackViewDistributionFillEqually;
	choices.spacing = 8.0;
	choices.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:choices];
	[NSLayoutConstraint activateConstraints:@[
		[choices.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8.0],
		[choices.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
		[choices.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
		[choices.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0]
	]];
	JikanAppearanceOptionView *classic = [[JikanAppearanceOptionView alloc] initWithProgressRing:NO];
	JikanAppearanceOptionView *ring = [[JikanAppearanceOptionView alloc] initWithProgressRing:YES];
	[choices addArrangedSubview:classic];
	[choices addArrangedSubview:ring];
	[classic addTarget:self action:@selector(_chooseAppearance:) forControlEvents:UIControlEventTouchUpInside];
	[ring addTarget:self action:@selector(_chooseAppearance:) forControlEvents:UIControlEventTouchUpInside];
	_classicOption = classic;
	_ringOption = ring;
	[self _updateSelection];
	return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	[self _updateSelection];
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (self.window) [self _updateSelection];
}

- (void)_updateSelection {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	BOOL ringSelected = [JikanPillAppearance(prefs) isEqualToString:JikanPillAppearanceProgressRing];
	self.classicOption.selected = !ringSelected;
	self.ringOption.selected = ringSelected;
}

- (void)_chooseAppearance:(JikanAppearanceOptionView *)option {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	[prefs setObject:option.showsProgressRing ? JikanPillAppearanceProgressRing : JikanPillAppearanceClassic forKey:JikanPillAppearanceKey];
	[prefs synchronize];
	[self _updateSelection];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);
}

@end

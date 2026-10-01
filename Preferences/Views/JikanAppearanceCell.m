#import "JikanAppearanceCell.h"

@interface JikanAppearanceOptionView : UIControl
@property (nonatomic, assign) BOOL showsProgressRing;
@property (nonatomic, strong) UIView *samplePill;
@property (nonatomic, strong) JikanPillContentView *content;
@property (nonatomic, strong) UIView *selectionCircle;
@property (nonatomic, strong) UIImageView *checkView;
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

	_content = [[JikanPillContentView alloc] init];
	_content.appearance = progressRing ? JikanPillAppearanceProgressRing : JikanPillAppearanceClassic;
	[_content applyContent:[JikanPillContent previewContentForTargetPercent:95]];
	[_samplePill addSubview:_content];

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
	_content.frame = _samplePill.bounds;
	[_content preferredSizeForMaximumWidth:pillWidth height:pillHeight];
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

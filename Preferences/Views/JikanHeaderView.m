#import "JikanHeaderView.h"

@implementation JikanHeaderView {
	UIImageView *_iconView;
	UILabel *_titleLabel;
	UILabel *_subtitleLabel;
	UIStackView *_stackView;
}

- (instancetype)initWithTitle:(NSString *)title subtitles:(NSArray<NSString *> *)subtitles bundle:(NSBundle *)bundle {
	self = [super initWithFrame:CGRectZero];
	if (!self) return nil;

	self.backgroundColor = UIColor.clearColor;

	UIImage *icon = [UIImage imageNamed:@"icon" inBundle:bundle compatibleWithTraitCollection:nil];
	if (!icon) {
		icon = [UIImage imageNamed:@"icon" inBundle:[NSBundle bundleForClass:[self class]] compatibleWithTraitCollection:nil];
	}
	_iconView = [[UIImageView alloc] initWithImage:icon];
	_iconView.translatesAutoresizingMaskIntoConstraints = NO;
	_iconView.contentMode = UIViewContentModeScaleAspectFit;
	_iconView.layer.cornerRadius = 15.0;
	_iconView.clipsToBounds = YES;
	_iconView.alpha = 0.0;

	_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_titleLabel.text = title;
	_titleLabel.textAlignment = NSTextAlignmentCenter;
	_titleLabel.font = [UIFont systemFontOfSize:34 weight:UIFontWeightSemibold];
	_titleLabel.textColor = [UIColor labelColor];
	_titleLabel.alpha = 0.0;

	_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_subtitleLabel.textAlignment = NSTextAlignmentCenter;
	_subtitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
	_subtitleLabel.textColor = [UIColor secondaryLabelColor];
	_subtitleLabel.alpha = 0.0;
	if (subtitles.count > 0) {
		_subtitleLabel.text = subtitles[arc4random_uniform((u_int32_t)subtitles.count)];
	}

	_stackView = [[UIStackView alloc] initWithArrangedSubviews:@[_iconView, _titleLabel, _subtitleLabel]];
	_stackView.translatesAutoresizingMaskIntoConstraints = NO;
	_stackView.axis = UILayoutConstraintAxisVertical;
	_stackView.alignment = UIStackViewAlignmentCenter;
	_stackView.distribution = UIStackViewDistributionEqualSpacing;
	_stackView.spacing = 2.0;
	[self addSubview:_stackView];

	[NSLayoutConstraint activateConstraints:@[
		[_iconView.widthAnchor constraintEqualToConstant:70.0],
		[_iconView.heightAnchor constraintEqualToConstant:70.0],
		[_titleLabel.heightAnchor constraintEqualToConstant:42.0],
		[_subtitleLabel.heightAnchor constraintEqualToConstant:16.0],

		[_stackView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
		[_stackView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:2.0],
	]];

	[self _addInterpolatingMotion];
	return self;
}

- (void)_addInterpolatingMotion {
	UIInterpolatingMotionEffect *horizontal = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
	horizontal.minimumRelativeValue = @(-4.0);
	horizontal.maximumRelativeValue = @(4.0);

	UIInterpolatingMotionEffect *vertical = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
	vertical.minimumRelativeValue = @(-4.0);
	vertical.maximumRelativeValue = @(4.0);

	UIMotionEffectGroup *group = [[UIMotionEffectGroup alloc] init];
	group.motionEffects = @[horizontal, vertical];
	[self addMotionEffect:group];
}

- (void)didMoveToSuperview {
	[super didMoveToSuperview];

	[UIView animateWithDuration:0.55 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
		_iconView.alpha = 1.0;
		_titleLabel.alpha = 1.0;
	} completion:nil];

	[UIView animateWithDuration:0.55 delay:0.18 options:UIViewAnimationOptionCurveEaseOut animations:^{
		_subtitleLabel.alpha = 1.0;
	} completion:nil];
}

@end

#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#import "TextCellWithIcon.h"

@interface TextCellWithIcon ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *iconTitleLabel;
@end

@implementation TextCellWithIcon

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
	self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
	if (!self) return nil;

	self.selectionStyle = UITableViewCellSelectionStyleNone;
	self.backgroundColor = UIColor.clearColor;

	_iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
	_iconView.translatesAutoresizingMaskIntoConstraints = NO;
	_iconView.contentMode = UIViewContentModeScaleAspectFit;
	_iconView.tintColor = [UIColor systemBlueColor];
	[self.contentView addSubview:_iconView];

	_iconTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_iconTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_iconTitleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
	_iconTitleLabel.textColor = [UIColor labelColor];
	[self.contentView addSubview:_iconTitleLabel];

	[NSLayoutConstraint activateConstraints:@[
		[_iconView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
		[_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_iconView.widthAnchor constraintEqualToConstant:26.0],
		[_iconView.heightAnchor constraintEqualToConstant:26.0],
		[_iconTitleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12.0],
		[_iconTitleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_iconTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
	]];

	NSString *symbolName = [specifier propertyForKey:@"sfIcon"];
	if ([symbolName isKindOfClass:[NSString class]] && symbolName.length > 0) {
		UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightRegular];
		UIImage *symbol = [UIImage systemImageNamed:symbolName withConfiguration:config];
		_iconView.image = symbol;
	}

	NSString *title = [specifier propertyForKey:@"label"];
	if (![title isKindOfClass:[NSString class]] || title.length == 0) {
		title = [specifier propertyForKey:@"label"];
	}
	_iconTitleLabel.text = title;

	return self;
}

@end

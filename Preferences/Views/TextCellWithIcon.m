#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#import "TextCellWithIcon.h"

@interface TextCellWithIcon ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *iconTitleLabel;
@property (nonatomic, assign) PSSpecifier *jikanSpecifier;
@end

@implementation TextCellWithIcon

- (UIColor *)_iconColorFromSpecifier:(PSSpecifier *)specifier {
	NSString *name = [specifier propertyForKey:@"sfColor"];
	if (![name isKindOfClass:[NSString class]] || name.length == 0) {
		return [UIColor systemBlueColor];
	}
	if ([name isEqualToString:@"green"]) return [UIColor systemGreenColor];
	if ([name isEqualToString:@"yellow"]) return [UIColor systemYellowColor];
	if ([name isEqualToString:@"gray"]) return [UIColor systemGrayColor];
	if ([name isEqualToString:@"blue"]) return [UIColor systemBlueColor];
	return [UIColor systemBlueColor];
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
	self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
	if (!self) return nil;
	self.jikanSpecifier = specifier;

	self.selectionStyle = UITableViewCellSelectionStyleNone;
	self.backgroundColor = UIColor.clearColor;
	if ([self respondsToSelector:@selector(titleLabel)] && self.titleLabel) {
		self.titleLabel.hidden = YES;
		self.titleLabel.text = @"";
	}
	if (self.textLabel) {
		self.textLabel.hidden = YES;
		self.textLabel.text = @"";
	}

	_iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
	_iconView.translatesAutoresizingMaskIntoConstraints = NO;
	_iconView.contentMode = UIViewContentModeScaleAspectFit;
	_iconView.tintColor = [self _iconColorFromSpecifier:specifier];
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
		if (!symbol && [symbolName isEqualToString:@"battery.75percent"]) {
			symbol = [UIImage systemImageNamed:@"battery.75" withConfiguration:config];
		}
		_iconView.image = symbol;
	}

	NSString *title = [specifier propertyForKey:@"CCELabel"];
	if (![title isKindOfClass:[NSString class]] || title.length == 0) {
		title = [specifier propertyForKey:@"label"];
	}
	_iconTitleLabel.text = title;

	NSString *infoAction = [specifier propertyForKey:@"infoAction"];
	if ([infoAction isKindOfClass:[NSString class]] && infoAction.length > 0) {
		UIButton *infoButton;
		if (@available(iOS 13.0, *)) {
			infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
		} else {
			infoButton = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
		}
		[infoButton addTarget:self action:@selector(_jikanInfoTapped) forControlEvents:UIControlEventTouchUpInside];
		self.accessoryView = infoButton;
	} else {
		self.accessoryView = nil;
	}

	return self;
}

- (void)_jikanInfoTapped {
	NSString *actionName = [self.jikanSpecifier propertyForKey:@"infoAction"];
	if (![actionName isKindOfClass:[NSString class]] || actionName.length == 0) return;
	id target = [self.jikanSpecifier target];
	SEL action = NSSelectorFromString(actionName);
	if (!target || !action || ![target respondsToSelector:action]) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	[target performSelector:action];
#pragma clang diagnostic pop
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if ([self respondsToSelector:@selector(titleLabel)] && self.titleLabel) {
		self.titleLabel.hidden = YES;
		self.titleLabel.text = @"";
	}
	if (self.textLabel) {
		self.textLabel.hidden = YES;
		self.textLabel.text = @"";
	}
	NSString *infoAction = [self.jikanSpecifier propertyForKey:@"infoAction"];
	if (![infoAction isKindOfClass:[NSString class]] || infoAction.length == 0) {
		self.accessoryView = nil;
	}
}

@end

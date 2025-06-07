#import "Jikan.h"

BOOL isCharging = NO;

%hook NCNotificationListCountIndicatorView

- (void)didMoveToWindow {
	self.hidden = YES;
	%orig;
}

%end

%hook _UIBatteryView

- (void)setChargingState:(NSInteger)arg1 {
	BOOL wasCharging = isCharging;
	isCharging = (arg1 == 1);
	if (wasCharging != isCharging) {
		[[NSNotificationCenter defaultCenter] postNotificationName:@"JikanChargingStateChanged" object:nil userInfo:@{ @"isCharging": @(isCharging) }];
	}
	return %orig;
}

%end

%hook CSQuickActionsView
%property (nonatomic, strong) UIView *remainingTimePlatter;

- (void)refreshSupportedButtons {
	%orig;
	[self _addOrRemoveRemainingTimePlatterIfNecessary];
	[self _configureRemainingTimePlatterConstraints];
}

%new
- (void)_addOrRemoveRemainingTimePlatterIfNecessary {
	if ([self _prototypingAllowsButtons] && isCharging) {
		[[TT100 sharedInstance] _refreshBatteryInfo];
		if (!self.remainingTimePlatter) {
			self.remainingTimePlatter = [[JikanPlatterView alloc] init];
			self.remainingTimePlatter.translatesAutoresizingMaskIntoConstraints = NO;
			[self addSubview:self.remainingTimePlatter];
		}
	} else {
		[self.remainingTimePlatter removeFromSuperview];
		self.remainingTimePlatter = nil;
	}
}

%new
- (void)_configureRemainingTimePlatterConstraints {
	if (!self.remainingTimePlatter) return;
	if (CGRectEqualToRect(self.flashlightButton.frame, CGRectZero) || CGRectEqualToRect(self.cameraButton.frame, CGRectZero)) {
		return;
	}

	UIView *superview = self.remainingTimePlatter.superview;
	if (superview) {
		NSMutableArray *constraintsToRemove = [NSMutableArray array];
		for (NSLayoutConstraint *constraint in superview.constraints) {
			if (constraint.firstItem == self.remainingTimePlatter || constraint.secondItem == self.remainingTimePlatter) {
				[constraintsToRemove addObject:constraint];
			}
		}
		[superview removeConstraints:constraintsToRemove];
	}

	[self.remainingTimePlatter removeConstraints:self.remainingTimePlatter.constraints];

	CGFloat heightConstant = [self _buttonOutsets].top + [self _buttonOutsets].bottom;
	[NSLayoutConstraint activateConstraints:@[
		[self.remainingTimePlatter.heightAnchor constraintEqualToAnchor:self.flashlightButton.heightAnchor constant:-heightConstant],
		[self.remainingTimePlatter.leadingAnchor constraintEqualToAnchor:self.flashlightButton.trailingAnchor],
		[self.remainingTimePlatter.trailingAnchor constraintEqualToAnchor:self.cameraButton.leadingAnchor],
		[self.remainingTimePlatter.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
		[self.remainingTimePlatter.centerYAnchor constraintEqualToAnchor:self.flashlightButton.centerYAnchor],
	]];

	[self.remainingTimePlatter setupConstraints];
}

%end
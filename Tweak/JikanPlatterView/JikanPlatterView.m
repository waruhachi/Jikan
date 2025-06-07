#import "../Jikan.h"
#import "../TT100/TT100.h"
#import "JikanPlatterView.h"

@implementation JikanPlatterView

- (instancetype)init {
	self = [super init];
	if (self) {
		self.translatesAutoresizingMaskIntoConstraints = NO;

		[self _setupSubviews];

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_tt100BatteryInfoUpdated:) name:@"TT100BatteryInfoUpdated" object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_chargingStateChanged:) name:@"JikanChargingStateChanged" object:nil];

		if (isCharging) {
			[self _startRefreshTimer];
		}
		[[TT100 sharedInstance] _refreshBatteryInfo];
	}

	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self _stopRefreshTimer];
}

- (void)_tt100BatteryInfoUpdated:(NSNotification *)notification {
	NSString *timeString = notification.userInfo[@"timeString"];
	[self updateWithTimeString:timeString];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	self.layer.cornerRadius = self.bounds.size.height / 2;
	self.clipsToBounds = YES;
	if (_backgroundView) {
		_backgroundView.layer.cornerRadius = _backgroundView.bounds.size.height / 2;
	}
}

- (void)_setupSubviews {
	Class MTMaterialViewClass = objc_getClass("MTMaterialView");
	if (MTMaterialViewClass) {
		if (@available(iOS 15, *)) {
			_backgroundView = [MTMaterialViewClass materialViewWithRecipe:19 options:2];
		} else {
			_backgroundView = [MTMaterialViewClass materialViewWithRecipe:19 configuration:1];
		}
		_backgroundView.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:_backgroundView];
		[self sendSubviewToBack:_backgroundView];
	} else {
		_backgroundView = [[UIView alloc] init];
		_backgroundView.translatesAutoresizingMaskIntoConstraints = NO;
		_backgroundView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.7];
		[self addSubview:_backgroundView];
		[self sendSubviewToBack:_backgroundView];
	}

	_containerView = [[UIView alloc] init];
	_containerView.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSubview:_containerView];

	UIImage *boltImage = [[UIImage systemImageNamed:@"bolt.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	_boltImageView = [[UIImageView alloc] initWithImage:boltImage];
	_boltImageView.tintColor = [UIColor greenColor];
	_boltImageView.translatesAutoresizingMaskIntoConstraints = NO;
	[_containerView addSubview:_boltImageView];

	_timeRemainingLabel = [[UILabel alloc] init];
	_timeRemainingLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_timeRemainingLabel.textColor = [UIColor whiteColor];
	_timeRemainingLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
	_timeRemainingLabel.textAlignment = NSTextAlignmentCenter;
	_timeRemainingLabel.text = @"0 minutes";
	[_containerView addSubview:_timeRemainingLabel];

	_staticLabel = [[UILabel alloc] init];
	_staticLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_staticLabel.textColor = [UIColor whiteColor];
	_staticLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
	_staticLabel.textAlignment = NSTextAlignmentCenter;
	_staticLabel.text = @"until fully charged";
	[_containerView addSubview:_staticLabel];
}

- (void)setupConstraints {
	[NSLayoutConstraint activateConstraints:@[
		[_backgroundView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
		[_backgroundView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
		[_backgroundView.topAnchor constraintEqualToAnchor:self.topAnchor],
		[_backgroundView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
		
		[_containerView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
		[_containerView.bottomAnchor constraintEqualToAnchor:self.centerYAnchor constant:-8],

		[_boltImageView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor],
		[_boltImageView.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
		[_boltImageView.widthAnchor constraintEqualToConstant:10],
		[_boltImageView.heightAnchor constraintEqualToConstant:10],

		[_timeRemainingLabel.leadingAnchor constraintEqualToAnchor:_boltImageView.trailingAnchor constant:4],
		[_timeRemainingLabel.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor],
		[_timeRemainingLabel.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
		[_timeRemainingLabel.heightAnchor constraintEqualToConstant:20],

		[_staticLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
		[_staticLabel.topAnchor constraintEqualToAnchor:self.centerYAnchor],
		[_staticLabel.heightAnchor constraintEqualToConstant:20],
	]];
}

- (void)updateWithTimeString:(NSString *)timeString {
	_timeRemainingLabel.text = timeString;
}

- (void)_chargingStateChanged:(NSNotification *)notification {
	BOOL charging = [notification.userInfo[@"isCharging"] boolValue];
	if (charging) {
		[self _startRefreshTimer];
		[[TT100 sharedInstance] _refreshBatteryInfo];
	} else {
		[self _stopRefreshTimer];
	}
}

- (void)_startRefreshTimer {
	if (!_refreshTimer) {
		_refreshTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(_triggerBatteryRefresh) userInfo:nil repeats:YES];
	}
}

- (void)_stopRefreshTimer {
	[_refreshTimer invalidate];
	_refreshTimer = nil;
}

- (void)_triggerBatteryRefresh {
	NSLog(@"[Jikan] _triggerBatteryRefresh");
	[[TT100 sharedInstance] _refreshBatteryInfo];
}

@end
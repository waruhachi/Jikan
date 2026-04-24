#include "JikanRootListController.h"

@interface JikanRootListController (CoalescedReload)
- (void)_scheduleSpecifiersReload:(BOOL)immediate;
@end

@interface JikanRootListController ()
@property (nonatomic, assign) BOOL jikanReloadQueued;
@property (nonatomic, assign) CFAbsoluteTime jikanLastReloadTime;
@end

@implementation JikanRootListController

static NSString *const kJikanPrefsSuite = @"moe.waru.jikan.preferences";
static NSString *const kJikanPrefsReloadNotification = @"moe.waru.jikan.preferences.reload";
static NSString *const kJikanOpenNCPreviewNotification = @"moe.waru.jikan.preview.nc.request";
static NSString *const kPillBackgroundOpacityKey = @"pillBackgroundOpacityPercent";

static void JikanPrefsDidChange(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
#pragma unused(center, name, object, userInfo)
	JikanRootListController *controller = (__bridge JikanRootListController *)observer;
	if (!controller) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (!controller.viewIfLoaded.window) return;
		[controller _scheduleSpecifiersReload:NO];
	});
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
		[self _configureAxisSliderLeftImages];
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, JikanPrefsDidChange, (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
	}

	return _specifiers;
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];

	// Create view and set as titleView of your navigation bar
	// Set the title and the minimum scroll offset before starting the animation
	if (!self.navigationItem.titleView) {
		AnimatedTitleView *titleView = [[AnimatedTitleView alloc] initWithTitle:@"Jikan" minimumScrollOffsetRequired:100];
		self.navigationItem.titleView = titleView;
	}

	[self _installOpacityValueTapIfNeeded];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	// Send scroll offset updates to view
	if ([self.navigationItem.titleView respondsToSelector:@selector(adjustLabelPositionToScrollOffset:)]) {
		[(AnimatedTitleView *)self.navigationItem.titleView adjustLabelPositionToScrollOffset:scrollView.contentOffset.y];
	}
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL);
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
}

- (void)reloadSpecifiers {
	self.jikanLastReloadTime = CFAbsoluteTimeGetCurrent();
	self.jikanReloadQueued = NO;
	[super reloadSpecifiers];
	[self _configureAxisSliderLeftImages];
	[self _installOpacityValueTapIfNeeded];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self _scheduleSpecifiersReload:YES];
}

- (void)_appDidBecomeActive:(NSNotification *)note {
#pragma unused(note)
	[self _scheduleSpecifiersReload:NO];
}

- (void)_scheduleSpecifiersReload:(BOOL)immediate {
	if (immediate) {
		[self reloadSpecifiers];
		return;
	}

	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	if ((now - self.jikanLastReloadTime) < 0.25) return;
	if (self.jikanReloadQueued) return;

	self.jikanReloadQueued = YES;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (!self.viewIfLoaded.window) {
			self.jikanReloadQueued = NO;
			return;
		}
		[self reloadSpecifiers];
	});
}

- (BOOL)_isEnableSectionInTableView:(UITableView *)tableView section:(NSInteger)section {
#pragma unused(tableView)
	return section == 0;
}

- (UIView *)_legendFooterView {
	UIView *container = [[UIView alloc] initWithFrame:CGRectZero];

	UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 4.0;
	stack.alignment = UIStackViewAlignmentLeading;
	[container addSubview:stack];

	NSArray<NSDictionary *> *legend = @[
		@{@"color": UIColor.systemGreenColor, @"text": @"Fast charging"},
		@{@"color": UIColor.systemYellowColor, @"text": @"Slow charging"},
		@{@"color": UIColor.systemGrayColor, @"text": @"Unknown"}
	];

	for (NSDictionary *entry in legend) {
		UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero];
		row.axis = UILayoutConstraintAxisHorizontal;
		row.spacing = 6.0;
		row.alignment = UIStackViewAlignmentCenter;

		UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold];
		UIImage *bolt = [UIImage systemImageNamed:@"bolt.fill" withConfiguration:cfg];
		UIImageView *icon = [[UIImageView alloc] initWithImage:bolt];
		icon.tintColor = entry[@"color"];
		icon.contentMode = UIViewContentModeScaleAspectFit;
		[icon.widthAnchor constraintEqualToConstant:12.0].active = YES;
		[icon.heightAnchor constraintEqualToConstant:12.0].active = YES;

		UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
		label.text = entry[@"text"];
		label.textColor = [UIColor secondaryLabelColor];
		label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];

		[row addArrangedSubview:icon];
		[row addArrangedSubview:label];
		[stack addArrangedSubview:row];
	}

	[NSLayoutConstraint activateConstraints:@[
		[stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16.0],
		[stack.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-16.0],
		[stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:2.0],
		[stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8.0],
	]];

	return container;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if ([self _isEnableSectionInTableView:tableView section:section]) {
		return [self _legendFooterView];
	}
	return [super tableView:tableView viewForFooterInSection:section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if ([self _isEnableSectionInTableView:tableView section:section]) {
		return 66.0;
	}
	return [super tableView:tableView heightForFooterInSection:section];
}

- (UIImage *)_axisIconForSymbol:(NSString *)symbolName {
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightRegular];
	UIImage *img = [UIImage systemImageNamed:symbolName withConfiguration:cfg];
	if (!img) return nil;
	return [img imageWithTintColor:[UIColor systemBlueColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (void)_configureAxisSliderLeftImages {
	NSArray<NSDictionary *> *map = @[
		@{@"id": @"pillPosXPortraitSlider", @"symbol": @"arrow.left.and.right"},
		@{@"id": @"pillPosYPortraitSlider", @"symbol": @"arrow.up.and.down"},
		@{@"id": @"pillPosXLandscapeSlider", @"symbol": @"arrow.left.and.right"},
		@{@"id": @"pillPosYLandscapeSlider", @"symbol": @"arrow.up.and.down"}
	];
	for (NSDictionary *entry in map) {
		PSSpecifier *spec = [self specifierForID:entry[@"id"]];
		if (!spec) continue;
		UIImage *icon = [self _axisIconForSymbol:entry[@"symbol"]];
		if (!icon) continue;
		[spec setProperty:icon forKey:@"leftImage"];
	}
}

- (void)_installOpacityValueTapIfNeeded {
	if (!self.table) return;

	PSSpecifier *opacitySpecifier = [self specifierForID:@"pillBackgroundOpacitySlider"];
	if (!opacitySpecifier) return;
	NSInteger row = [self indexOfSpecifier:opacitySpecifier];
	if (row == NSNotFound) return;

	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
	UITableViewCell *cell = [self.table cellForRowAtIndexPath:indexPath];
	if (!cell) return;

	for (UIView *subview in cell.contentView.subviews) {
		if (![subview isKindOfClass:[UILabel class]]) continue;
		UILabel *label = (UILabel *)subview;
		if (!label.userInteractionEnabled) {
			label.userInteractionEnabled = YES;
		}
		BOOL isLikelyValueLabel = (label.textAlignment == NSTextAlignmentRight || CGRectGetWidth(label.frame) <= 72.0);
		if (!isLikelyValueLabel) continue;

		BOOL already = NO;
		for (UIGestureRecognizer *gr in label.gestureRecognizers) {
			if ([gr isKindOfClass:[UITapGestureRecognizer class]] && gr.view == label) {
				already = YES;
				break;
			}
		}
		if (!already) {
			UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openPillBackgroundOpacityEditor)];
			tap.numberOfTapsRequired = 2;
			[label addGestureRecognizer:tap];
		}
	}
}

- (void)openPillBackgroundOpacityEditor {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	double currentValue = [prefs objectForKey:kPillBackgroundOpacityKey] ? [prefs doubleForKey:kPillBackgroundOpacityKey] : 100.0;
	if (!isfinite(currentValue)) currentValue = 100.0;
	currentValue = MAX(0.0, MIN(100.0, currentValue));

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Pill Background Opacity" message:@"Enter a value from 0 to 100" preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *_Nonnull textField) {
		textField.keyboardType = UIKeyboardTypeDecimalPad;
		textField.placeholder = @"0-100";
		textField.text = [NSString stringWithFormat:@"%.1f", currentValue];
	}];

	__typeof(self) weakSelf = self;
	UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_Nonnull action) {
		__unused UIAlertAction *unusedAction = action;
		UITextField *tf = alert.textFields.firstObject;
		double v = tf.text.doubleValue;
		if (!isfinite(v)) v = currentValue;
		v = MAX(0.0, MIN(100.0, v));

		[prefs setDouble:v forKey:kPillBackgroundOpacityKey];
		[prefs synchronize];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);

		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf _scheduleSpecifiersReload:YES];
		});
	}];

	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:save];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)openNotificationCenterPreview {
	static CFAbsoluteTime lastTrigger = 0;
	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	if ((now - lastTrigger) < 0.35) return;
	lastTrigger = now;

	CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
	CFNotificationCenterPostNotification(darwin, (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);
	CFNotificationCenterPostNotification(darwin, (__bridge CFStringRef)kJikanOpenNCPreviewNotification, NULL, NULL, YES);
}

- (void)resetPreferences {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	if (!prefs) return;

	NSArray<NSString *> *keys = @[
		@"enabled",
		@"platterYOffset",
		@"platterPosXNorm",
		@"platterPosYNorm",
		@"platterPosXNormLandscape",
		@"platterPosYNormLandscape",
		@"pillPosXPortraitPercent",
		@"pillPosYPortraitPercent",
		@"pillPosXLandscapePercent",
		@"pillPosYLandscapePercent",
		@"pillBackgroundOpacityPercent",
		@"hideQuickActionButtons",
		@"showRemainingBatteryTime",
		@"autoResizeRemainingBatteryTime",
		@"tapToShowWattage",
		@"previewPlatter",
		@"showAfterFullCharge",
		@"lockPreviewXAxis",
		@"lockPreviewYAxis"
	];

	for (NSString *key in keys) {
		[prefs removeObjectForKey:key];
	}

	[prefs synchronize];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);

	dispatch_async(dispatch_get_main_queue(), ^{
		[self _scheduleSpecifiersReload:YES];
	});
}

- (void)resetPillPosition {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	if (!prefs) return;

	NSArray<NSString *> *keys = @[
		@"platterPosXNorm",
		@"platterPosYNorm",
		@"platterPosXNormLandscape",
		@"platterPosYNormLandscape",
		@"pillPosXPortraitPercent",
		@"pillPosYPortraitPercent",
		@"pillPosXLandscapePercent",
		@"pillPosYLandscapePercent",
		@"lockPreviewXAxis",
		@"lockPreviewYAxis"
	];

	for (NSString *key in keys) {
		[prefs removeObjectForKey:key];
	}

	[prefs synchronize];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);

	dispatch_async(dispatch_get_main_queue(), ^{
		[self _scheduleSpecifiersReload:YES];
	});
}

@end

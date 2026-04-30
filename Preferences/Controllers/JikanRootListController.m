#import "JikanRootListController.h"

@interface PSListController (Private)
- (id)readPreferenceValue:(PSSpecifier *)specifier;
@end

@interface JikanRootListController (CoalescedReload)
- (void)_scheduleSpecifiersReload:(BOOL)immediate;
@end

@interface JikanRootListController ()
@property (nonatomic, assign) BOOL jikanReloadQueued;
@property (nonatomic, assign) CFAbsoluteTime jikanLastReloadTime;
@end

static NSString *const kJikanPrefsSuite = @"moe.waru.jikan.preferences";
static NSString *const kJikanPrefsReloadNotification = @"moe.waru.jikan.preferences.reload";
static NSString *const kJikanOpenNCPreviewNotification = @"moe.waru.jikan.preview.nc.request";
static NSString *const kPillBackgroundOpacityKey = @"pillBackgroundOpacityPercent";
static NSString *const kBatteryEstimateTargetKey = @"batteryEstimateTargetPercent";
static NSString *const kBatteryEstimateSyncedKey = @"batteryEstimateSyncedWithChargeLimiter";
static const void *kJikanSliderEditorInstalledKey = &kJikanSliderEditorInstalledKey;
static const void *kJikanSliderEditorConfigKey = &kJikanSliderEditorConfigKey;
static const void *kJikanSliderThumbOnlyKey = &kJikanSliderThumbOnlyKey;

@interface UISlider (JikanThumbOnlyTracking)
- (BOOL)jikan_beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
@end

@implementation UISlider (JikanThumbOnlyTracking)

- (BOOL)jikan_beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
	if ([objc_getAssociatedObject(self, kJikanSliderThumbOnlyKey) boolValue]) {
		CGPoint point = [touch locationInView:self];
		CGRect trackRect = [self trackRectForBounds:self.bounds];
		CGRect thumbRect = [self thumbRectForBounds:self.bounds trackRect:trackRect value:self.value];
		if (!CGRectContainsPoint(CGRectInset(thumbRect, -12.0, -12.0), point)) {
			return NO;
		}
	}
	return [self jikan_beginTrackingWithTouch:touch withEvent:event];
}

@end

static void JikanInstallSliderTrackingGuardIfNeeded(void) {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		Method original = class_getInstanceMethod([UISlider class], @selector(beginTrackingWithTouch:withEvent:));
		Method replacement = class_getInstanceMethod([UISlider class], @selector(jikan_beginTrackingWithTouch:withEvent:));
		if (original && replacement) method_exchangeImplementations(original, replacement);
	});
}

@implementation JikanRootListController

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
		[self _localizeSpecifiersInPlace:_specifiers];
		[self _updateBatteryLimitInfoSpecifier];
		[self collectDynamicSpecifiersFromArray:_specifiers];
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

	[self _installSliderLongPressEditorsIfNeeded];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self _seedBatteryEstimateTargetIfNeeded];

	self.navigationController.navigationBar.prefersLargeTitles = NO;
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

	NSArray<NSString *> *subtitles = @[JikanLocalizedString(@"jikan.prefs.header.subtitle", @"Show time left to full charge on your lock screen")];
	JikanHeaderView *header = [[JikanHeaderView alloc] initWithTitle:@"Jikan" subtitles:subtitles bundle:[self bundle]];
	header.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(self.view.bounds), 180.0);
	UITableView *tableView = self.table ?: [self valueForKey:@"_table"];
	if (tableView) tableView.tableHeaderView = header;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	// Send scroll offset updates to view
	if ([self.navigationItem.titleView respondsToSelector:@selector(adjustLabelPositionToScrollOffset:)]) {
		[(AnimatedTitleView *)self.navigationItem.titleView adjustLabelPositionToScrollOffset:scrollView.contentOffset.y];
	}
	[self _installSliderLongPressEditorsIfNeeded];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL);
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"key"];
	NSSet<NSString *> *integerSliderKeys = [NSSet setWithArray:@[
		kPillBackgroundOpacityKey,
		kBatteryEstimateTargetKey,
		@"pillPosXPortraitPercent",
		@"pillPosYPortraitPercent",
		@"pillPosXLandscapePercent",
		@"pillPosYLandscapePercent"
	]];
	if ([integerSliderKeys containsObject:key]) {
		double raw = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 100.0;
		NSInteger rounded = (NSInteger)llround(raw);
		rounded = MAX(0, MIN(100, rounded));
		value = @(rounded);
		if ([key isEqualToString:kBatteryEstimateTargetKey]) {
			NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
			[prefs setBool:NO forKey:kBatteryEstimateSyncedKey];
			[prefs synchronize];
		}
	}
	[super setPreferenceValue:value specifier:specifier];

	if (self.hasDynamicSpecifiers) {
		NSString *specifierID = [specifier propertyForKey:PSIDKey];
		PSSpecifier *dynamicSpecifier = [self.dynamicSpecifiers objectForKey:specifierID];
		if (dynamicSpecifier) {
			[self.table beginUpdates];
			[self.table endUpdates];
		}
	}
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
}

- (void)reloadSpecifiers {
	self.jikanLastReloadTime = CFAbsoluteTimeGetCurrent();
	self.jikanReloadQueued = NO;
	[super reloadSpecifiers];
	[self _localizeSpecifiersInPlace:self.specifiers];
	[self _updateBatteryLimitInfoSpecifier];
	[self collectDynamicSpecifiersFromArray:self.specifiers];
	[self _configureAxisSliderLeftImages];
	[self _installSliderLongPressEditorsIfNeeded];
}

- (void)_updateBatteryLimitInfoSpecifier {
	PSSpecifier *spec = [self specifierForID:@"batteryLimitInfoRow"];
	if (!spec) return;
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	BOOL synced = [prefs objectForKey:kBatteryEstimateSyncedKey] ? [prefs boolForKey:kBatteryEstimateSyncedKey] : NO;
	if (synced) {
		[spec setProperty:@"showBatteryLimitSourceInfo" forKey:@"infoAction"];
	} else {
		[spec removePropertyForKey:@"infoAction"];
	}
}

- (void)collectDynamicSpecifiersFromArray:(NSArray *)array {
	if (!self.dynamicSpecifiers) {
		self.dynamicSpecifiers = [NSMutableDictionary new];
	} else {
		[self.dynamicSpecifiers removeAllObjects];
	}

	for (PSSpecifier *specifier in array) {
		NSString *dynamicSpecifierRule = [specifier propertyForKey:@"dynamicRule"];
		if (dynamicSpecifierRule.length == 0) continue;

		NSArray *ruleComponents = [dynamicSpecifierRule componentsSeparatedByString:@", "];
		if (ruleComponents.count == 3) {
			NSString *opposingSpecifierID = [ruleComponents objectAtIndex:0];
			[self.dynamicSpecifiers setObject:specifier forKey:opposingSpecifierID];
		} else {
			[NSException raise:NSInternalInconsistencyException format:@"dynamicRule key requires three components (Specifier ID, Comparator, Value To Compare To). You have %ld of 3 (%@) for specifier '%@'.", (long)ruleComponents.count, dynamicSpecifierRule, [specifier propertyForKey:PSTitleKey]];
		}
	}

	self.hasDynamicSpecifiers = (self.dynamicSpecifiers.count > 0);
}

- (NSString *)_localizedPreferenceText:(NSString *)text {
	if (![text isKindOfClass:[NSString class]] || text.length == 0) return text;
	static NSDictionary<NSString *, NSString *> *keyMap;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		keyMap = @{
			@"Enable": @"jikan.prefs.row.enable",
			@"Pill Preview": @"jikan.prefs.section.pill_preview",
			@"Lock X Axis": @"jikan.prefs.row.lock_x_axis",
			@"Lock Y Axis": @"jikan.prefs.row.lock_y_axis",
			@"Show Preview": @"jikan.prefs.row.show_preview",
			@"Pill Display": @"jikan.prefs.section.pill_display",
			@"Show after full charge": @"jikan.prefs.row.show_after_full_charge",
			@"Show current wattage": @"jikan.prefs.row.show_current_wattage",
			@"Tap and Hold the Slider Knob to Edit": @"jikan.prefs.footer.slider_hint",
			@"Opacity": @"jikan.prefs.row.opacity",
			@"Pill Background Opacity (%)": @"jikan.prefs.row.pill_background_opacity",
			@"Pill Position": @"jikan.prefs.section.pill_position",
			@"Portrait": @"jikan.prefs.row.portrait",
			@"Portrait X": @"jikan.prefs.row.portrait_x",
			@"Portrait Y": @"jikan.prefs.row.portrait_y",
			@"Landscape": @"jikan.prefs.row.landscape",
			@"Landscape X": @"jikan.prefs.row.landscape_x",
			@"Landscape Y": @"jikan.prefs.row.landscape_y",
			@"Miscellaneous": @"jikan.prefs.section.miscellaneous",
			@"Time Estimate": @"jikan.prefs.section.battery_estimate",
			@"Battery Limit": @"jikan.prefs.row.charge_limit",
			@"Charge Limit": @"jikan.prefs.row.charge_limit",
			@"Estimate Target (%)": @"jikan.prefs.row.estimate_target_percent",
			@"Sync with ChargeLimiter": @"jikan.prefs.row.sync_with_chargelimiter",
			@"Hide Quick Action Buttons": @"jikan.prefs.row.hide_quick_action_buttons",
			@"Only While Charging": @"jikan.prefs.row.only_while_charging",
			@"Reset": @"jikan.prefs.section.reset",
			@"Reset Pill Position": @"jikan.prefs.row.reset_pill_position",
			@"Reset To Defaults": @"jikan.prefs.row.reset_to_defaults",
			@"Reset Preferences": @"jikan.prefs.alert.reset_preferences.title",
			@"Reset all Jikan settings to defaults?": @"jikan.prefs.alert.reset_preferences.prompt",
			@"Reset portrait/landscape pill position and axis locks?": @"jikan.prefs.alert.reset_pill_position.prompt",
			@"Cancel": @"jikan.common.action.cancel"
		};
	});

	NSString *key = keyMap[text];
	if (key.length == 0) return text;
	return JikanLocalizedString(key, text);
}

- (void)_localizeSpecifiersInPlace:(NSArray<PSSpecifier *> *)specifiers {
	for (PSSpecifier *specifier in specifiers) {
		NSString *label = [specifier propertyForKey:@"label"];
		if ([label isKindOfClass:[NSString class]] && label.length > 0) {
			[specifier setProperty:[self _localizedPreferenceText:label] forKey:@"label"];
		}

		NSString *footerText = [specifier propertyForKey:@"footerText"];
		if ([footerText isKindOfClass:[NSString class]] && footerText.length > 0) {
			[specifier setProperty:[self _localizedPreferenceText:footerText] forKey:@"footerText"];
		}

		NSDictionary *confirmation = [specifier propertyForKey:@"confirmation"];
		if ([confirmation isKindOfClass:[NSDictionary class]]) {
			NSMutableDictionary *localizedConfirmation = [confirmation mutableCopy];
			for (NSString *key in @[@"title", @"prompt", @"cancelTitle"]) {
				NSString *value = confirmation[key];
				if ([value isKindOfClass:[NSString class]] && value.length > 0) {
					localizedConfirmation[key] = [self _localizedPreferenceText:value];
				}
			}
			[specifier setProperty:localizedConfirmation forKey:@"confirmation"];
		}
	}
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
	if (self.hasDynamicSpecifiers) {
		PSSpecifier *dynamicSpecifier = specifier;
		if ([self.dynamicSpecifiers.allValues containsObject:dynamicSpecifier]) {
			BOOL shouldHide = [self shouldHideSpecifier:dynamicSpecifier];
			UITableViewCell *specifierCell = [dynamicSpecifier propertyForKey:PSTableCellKey];
			specifierCell.clipsToBounds = shouldHide;
			if (shouldHide) return 0;
		}

		if ([dynamicSpecifier propertyForKey:@"height"] != 0) {
			return [[dynamicSpecifier propertyForKey:@"height"] doubleValue];
		}
	}

	return UITableViewAutomaticDimension;
}

- (BOOL)shouldHideSpecifier:(PSSpecifier *)specifier {
	if (!specifier) return NO;

	NSString *dynamicSpecifierRule = [specifier propertyForKey:@"dynamicRule"];
	NSArray *ruleComponents = [dynamicSpecifierRule componentsSeparatedByString:@", "];
	if (ruleComponents.count != 3) return NO;

	PSSpecifier *opposingSpecifier = [self specifierForID:[ruleComponents objectAtIndex:0]];
	id opposingValue = [self readPreferenceValue:opposingSpecifier];
	id requiredValue = [ruleComponents objectAtIndex:2];

	if ([opposingValue isKindOfClass:NSNumber.class]) {
		JikanDynamicSpecifierOperatorType operatorType = [self operatorTypeForString:[ruleComponents objectAtIndex:1]];
		switch (operatorType) {
			case JikanEqualToOperatorType:
				return ([opposingValue intValue] == [requiredValue intValue]);
			case JikanNotEqualToOperatorType:
				return ([opposingValue intValue] != [requiredValue intValue]);
			case JikanGreaterThanOperatorType:
				return ([opposingValue intValue] > [requiredValue intValue]);
			case JikanLessThanOperatorType:
				return ([opposingValue intValue] < [requiredValue intValue]);
		}
	}

	if ([opposingValue isKindOfClass:NSString.class]) {
		return [opposingValue isEqualToString:requiredValue];
	}

	if ([opposingValue isKindOfClass:NSArray.class]) {
		return [opposingValue containsObject:requiredValue];
	}

	return NO;
}

- (JikanDynamicSpecifierOperatorType)operatorTypeForString:(NSString *)string {
	NSDictionary *operatorValues = @{
		@"==": @(JikanEqualToOperatorType),
		@"!=": @(JikanNotEqualToOperatorType),
		@">": @(JikanGreaterThanOperatorType),
		@"<": @(JikanLessThanOperatorType)
	};
	return [operatorValues[string] intValue];
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

- (BOOL)_isSpacerSectionInTableView:(UITableView *)tableView section:(NSInteger)section {
	NSString *header = [super tableView:tableView titleForHeaderInSection:section];
	if (![header isKindOfClass:[NSString class]]) return NO;
	NSString *trimmed = [header stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return trimmed.length == 0;
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
		@{@"color": UIColor.systemYellowColor, @"text": JikanLocalizedString(@"jikan.prefs.legend.slow_charging", @"Slow charging")}
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

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if ([self _isSpacerSectionInTableView:tableView section:section]) {
		UIView *spacer = [[UIView alloc] initWithFrame:CGRectZero];
		spacer.backgroundColor = UIColor.clearColor;
		return spacer;
	}
	return [super tableView:tableView viewForHeaderInSection:section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if ([self _isEnableSectionInTableView:tableView section:section]) {
		return 42.0;
	}
	return [super tableView:tableView heightForFooterInSection:section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	if ([self _isSpacerSectionInTableView:tableView section:section]) {
		return 2.0;
	}
	return [super tableView:tableView heightForHeaderInSection:section];
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

- (NSArray<NSDictionary *> *)_sliderEditorConfigs {
	return @[
		@{@"id": @"pillBackgroundOpacitySlider", @"key": kPillBackgroundOpacityKey, @"title": JikanLocalizedString(@"jikan.prefs.slider.opacity.title", @"Pill Background Opacity"), @"min": @0.0, @"max": @100.0, @"decimals": @0},
		@{@"id": @"batteryEstimateTargetSlider", @"key": kBatteryEstimateTargetKey, @"title": JikanLocalizedString(@"jikan.prefs.slider.estimate_target.title", @"Estimate Target"), @"min": @0.0, @"max": @100.0, @"decimals": @0},
		@{@"id": @"pillPosXPortraitSlider", @"key": @"pillPosXPortraitPercent", @"title": JikanLocalizedString(@"jikan.prefs.slider.portrait_x.title", @"Portrait X"), @"min": @0.0, @"max": @100.0, @"decimals": @0},
		@{@"id": @"pillPosYPortraitSlider", @"key": @"pillPosYPortraitPercent", @"title": JikanLocalizedString(@"jikan.prefs.slider.portrait_y.title", @"Portrait Y"), @"min": @0.0, @"max": @100.0, @"decimals": @0},
		@{@"id": @"pillPosXLandscapeSlider", @"key": @"pillPosXLandscapePercent", @"title": JikanLocalizedString(@"jikan.prefs.slider.landscape_x.title", @"Landscape X"), @"min": @0.0, @"max": @100.0, @"decimals": @0},
		@{@"id": @"pillPosYLandscapeSlider", @"key": @"pillPosYLandscapePercent", @"title": JikanLocalizedString(@"jikan.prefs.slider.landscape_y.title", @"Landscape Y"), @"min": @0.0, @"max": @100.0, @"decimals": @0}
	];
}

- (UISlider *)_firstSliderInView:(UIView *)view {
	if ([view isKindOfClass:[UISlider class]]) return (UISlider *)view;
	for (UIView *subview in view.subviews) {
		UISlider *slider = [self _firstSliderInView:subview];
		if (slider) return slider;
	}
	return nil;
}

- (void)_installSliderLongPressEditorsIfNeeded {
	JikanInstallSliderTrackingGuardIfNeeded();

	for (NSDictionary *config in [self _sliderEditorConfigs]) {
		PSSpecifier *specifier = [self specifierForID:config[@"id"]];
		if (!specifier) continue;

		UITableViewCell *cell = [specifier propertyForKey:PSTableCellKey];
		if (!cell) continue;

		UISlider *slider = [self _firstSliderInView:cell.contentView];
		if (!slider) continue;
		objc_setAssociatedObject(slider, kJikanSliderThumbOnlyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		if ([objc_getAssociatedObject(slider, kJikanSliderEditorInstalledKey) boolValue]) continue;

		UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_handleSliderKnobHold:)];
		hold.minimumPressDuration = 0.35;
		hold.cancelsTouchesInView = NO;
		[slider addGestureRecognizer:hold];

		objc_setAssociatedObject(slider, kJikanSliderEditorInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(slider, kJikanSliderEditorConfigKey, config, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
}

- (void)_handleSliderKnobHold:(UILongPressGestureRecognizer *)gesture {
	if (gesture.state != UIGestureRecognizerStateBegan) return;
	if (![gesture.view isKindOfClass:[UISlider class]]) return;

	UISlider *slider = (UISlider *)gesture.view;
	CGRect trackRect = [slider trackRectForBounds:slider.bounds];
	CGRect thumbRect = [slider thumbRectForBounds:slider.bounds trackRect:trackRect value:slider.value];
	CGPoint touch = [gesture locationInView:slider];
	if (!CGRectContainsPoint(CGRectInset(thumbRect, -12.0, -12.0), touch)) return;

	NSDictionary *config = objc_getAssociatedObject(slider, kJikanSliderEditorConfigKey);
	if (![config isKindOfClass:[NSDictionary class]]) return;
	[self _presentSliderEditorWithConfig:config fallbackValue:slider.value];
}

- (void)_presentSliderEditorWithConfig:(NSDictionary *)config fallbackValue:(double)fallback {
	NSString *prefsKey = config[@"key"];
	NSString *title = config[@"title"];
	double minValue = [config[@"min"] doubleValue];
	double maxValue = [config[@"max"] doubleValue];
	NSInteger decimals = [config[@"decimals"] integerValue];

	if (prefsKey.length == 0 || title.length == 0) return;

	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	double currentValue = [prefs objectForKey:prefsKey] ? [prefs doubleForKey:prefsKey] : fallback;
	if (!isfinite(currentValue)) currentValue = fallback;
	if (!isfinite(currentValue)) currentValue = minValue;
	currentValue = MAX(minValue, MIN(maxValue, currentValue));

	NSString *messageFormat = JikanLocalizedString(@"jikan.prefs.alert.slider_range.message", @"Enter a value from %.0f to %.0f");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:[NSString stringWithFormat:messageFormat, minValue, maxValue] preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *_Nonnull textField) {
		textField.keyboardType = UIKeyboardTypeDecimalPad;
		textField.placeholder = [NSString stringWithFormat:@"%.0f-%.0f", minValue, maxValue];
		textField.text = [NSString stringWithFormat:[NSString stringWithFormat:@"%%.%ldf", (long)decimals], currentValue];
	}];

	__typeof(self) weakSelf = self;
	UIAlertAction *save = [UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.save", @"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_Nonnull action) {
		UITextField *tf = alert.textFields.firstObject;
		double value = tf.text.doubleValue;
		if (!isfinite(value)) value = currentValue;
		value = MAX(minValue, MIN(maxValue, value));

		[prefs setDouble:value forKey:prefsKey];
		if ([prefsKey isEqualToString:kBatteryEstimateTargetKey]) {
			[prefs setBool:NO forKey:kBatteryEstimateSyncedKey];
		}
		[prefs synchronize];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf _scheduleSpecifiersReload:YES];
		});
	}];

	[alert addAction:[UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:save];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)_clampedBatteryLimit:(NSInteger)limit {
	return MAX(0, MIN(100, limit));
}

- (NSNumber *)_detectChargeLimiterLimit {
	NSArray<NSString *> *installMarkers = @[
		@"/Applications/ChargeLimiter.app",
		@"/var/jb/Applications/ChargeLimiter.app",
		@"/var/containers/Bundle/Application/.jbroot-*/Applications/ChargeLimiter.app"
	];
	BOOL installed = NO;
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSString *marker in installMarkers) {
		if ([marker containsString:@"*"]) {
			NSArray<NSString *> *matches = [fm contentsOfDirectoryAtPath:@"/var/containers/Bundle/Application" error:nil];
			for (NSString *entry in matches) {
				if (![entry hasPrefix:@".jbroot-"]) continue;
				NSString *candidate = [@"/var/containers/Bundle/Application" stringByAppendingPathComponent:entry];
				candidate = [candidate stringByAppendingPathComponent:@"Applications/ChargeLimiter.app"];
				if ([fm fileExistsAtPath:candidate]) {
					installed = YES;
					break;
				}
			}
		} else if ([fm fileExistsAtPath:marker]) {
			installed = YES;
		}
		if (installed) break;
	}
	if (!installed) return nil;

	NSDictionary *conf = [NSDictionary dictionaryWithContentsOfFile:@"/var/root/aldente.conf"];
	if (![conf isKindOfClass:[NSDictionary class]]) return nil;
	id value = conf[@"charge_above"];
	if (![value respondsToSelector:@selector(integerValue)]) return nil;
	NSInteger limit = [self _clampedBatteryLimit:[value integerValue]];
	return @(limit);
}

- (void)_setBatteryEstimateTargetPercent:(NSInteger)percent {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	if (!prefs) return;
	[prefs setInteger:[self _clampedBatteryLimit:percent] forKey:kBatteryEstimateTargetKey];
	[prefs synchronize];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);
	dispatch_async(dispatch_get_main_queue(), ^{
		[self _scheduleSpecifiersReload:YES];
	});
}

- (void)_setBatteryEstimateSyncedState:(BOOL)synced {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	if (!prefs) return;
	[prefs setBool:synced forKey:kBatteryEstimateSyncedKey];
	[prefs synchronize];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);
	dispatch_async(dispatch_get_main_queue(), ^{
		[self _scheduleSpecifiersReload:YES];
	});
}

- (void)_seedBatteryEstimateTargetIfNeeded {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	if (!prefs) return;
	if ([prefs objectForKey:kBatteryEstimateTargetKey]) return;
	NSNumber *detected = [self _detectChargeLimiterLimit];
	NSInteger value = detected ? detected.integerValue : 100;
	[prefs setInteger:[self _clampedBatteryLimit:value] forKey:kBatteryEstimateTargetKey];
	[prefs synchronize];
}

- (void)detectBatteryLimit {
	NSNumber *detected = [self _detectChargeLimiterLimit];
	if (!detected) {
		[self _setBatteryEstimateTargetPercent:100];
		[self _setBatteryEstimateSyncedState:NO];
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:JikanLocalizedString(@"jikan.prefs.alert.detect_limit.none.title", @"No battery limit found") message:JikanLocalizedString(@"jikan.prefs.alert.detect_limit.none.message", @"No ChargeLimiter limit was detected. Using 100%.") preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.ok", @"OK") style:UIAlertActionStyleDefault handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
		return;
	}
	NSInteger value = detected.integerValue;
	[self _setBatteryEstimateTargetPercent:value];
	[self _setBatteryEstimateSyncedState:YES];
	NSString *format = JikanLocalizedString(@"jikan.prefs.alert.detect_limit.single.message", @"ChargeLimiter detected Applied battery limit of: %ld%%");
	NSString *message = [NSString stringWithFormat:format, (long)value];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:JikanLocalizedString(@"jikan.prefs.alert.detect_limit.single.title", @"ChargeLimiter detected") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.ok", @"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)showBatteryLimitSourceInfo {
	NSNumber *detected = [self _detectChargeLimiterLimit];
	if (!detected) return;
	NSString *message = [NSString stringWithFormat:@"ChargeLimiter: %ld%%", (long)detected.integerValue];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:JikanLocalizedString(@"jikan.prefs.alert.limit_sources.title", @"Synced with ChargeLimiter") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.ok", @"OK") style:UIAlertActionStyleDefault handler:nil]];
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
		@"hideQuickActionButtonsOnlyWhenCharging",
		@"showRemainingBatteryTime",
		@"autoResizeRemainingBatteryTime",
		@"tapToShowWattage",
		kBatteryEstimateTargetKey,
		kBatteryEstimateSyncedKey,
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

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
@property (nonatomic, assign) NSUInteger jikanReloadGeneration;
@property (nonatomic, assign) BOOL jikanObservingPreferences;
@property (nonatomic, assign) BOOL jikanPageActive;
@property (nonatomic, strong) JikanChargeLimiterDetector *jikanChargeLimiterDetector;
@property (nonatomic, copy) NSString *jikanDetectionSource;
@property (nonatomic, assign) NSInteger jikanDetectionTarget;
@property (nonatomic, strong) JikanSliderEditor *jikanSliderEditor;
@property (nonatomic, strong) PSSpecifier *jikanQuickActionChargingSpecifier;
@property (nonatomic, assign) BOOL jikanAnimatingQuickActionRow;
@property (nonatomic, assign) NSUInteger jikanQuickActionAnimationGeneration;
@end

static NSString *const kBatteryEstimateTargetKey = @"batteryEstimateTargetPercent";
static NSString *const kBatteryEstimateSyncedKey = @"batteryEstimateSyncedWithChargeLimiter";
static NSString *const kQuickActionsChargingOnlySpecifierID = @"hideQuickActionsChargingOnlyToggleID";
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
		[self _filterQuickActionChargingSpecifier:_specifiers];
		[self _updateBatteryLimitInfoSpecifier];
		[self _configureAxisSliderLeftImages];
		if (!self.jikanObservingPreferences) {
			CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, JikanPrefsDidChange, (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
			self.jikanObservingPreferences = YES;
		}
	}

	return _specifiers;
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];

	if (!self.navigationItem.titleView) {
		AnimatedTitleView *titleView = [[AnimatedTitleView alloc] initWithTitle:@"Jikan" minimumScrollOffsetRequired:100];
		self.navigationItem.titleView = titleView;
	}

	[self _installSliderLongPressEditorsIfNeeded];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self _normalizeStoredSliderValues];

	self.navigationController.navigationBar.prefersLargeTitles = NO;
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

	NSArray<NSString *> *subtitles = @[JikanLocalizedString(@"jikan.prefs.header.subtitle", @"Show time left to full charge on your lock screen")];
	JikanHeaderView *header = [[JikanHeaderView alloc] initWithTitle:@"Jikan" subtitles:subtitles bundle:[self bundle]];
	header.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(self.view.bounds), 180.0);
	UITableView *tableView = self.table ?: [self valueForKey:@"_table"];
	if (tableView) {
		tableView.tableHeaderView = header;
		tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	}
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if ([self.navigationItem.titleView respondsToSelector:@selector(adjustLabelPositionToScrollOffset:)]) {
		[(AnimatedTitleView *)self.navigationItem.titleView adjustLabelPositionToScrollOffset:scrollView.contentOffset.y];
	}
	[self _installSliderLongPressEditorsIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	self.jikanPageActive = NO;
	[self _cancelChargeLimiterDetection];
	[self.jikanSliderEditor dismiss];
}

- (void)dealloc {
	[_jikanChargeLimiterDetector cancel];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL);
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"key"];
	[self _cancelChargeLimiterDetection];
	if ([key isEqualToString:JikanEstimateSourceKey]) {
		[self.jikanSliderEditor dismiss];
		value = [value isKindOfClass:NSString.class] && [value isEqualToString:@"jikan"] ? @"jikan" : @"apple";
		NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
		if ([value isEqualToString:@"apple"] && ![prefs objectForKey:JikanEstimateAppleTargetKey]) {
			NSInteger jikanTarget = JikanEstimateTarget(prefs, @"jikan");
			[prefs setInteger:JikanAppleTargetIsSupported(jikanTarget) ? jikanTarget : 100 forKey:JikanEstimateAppleTargetKey];
			[prefs synchronize];
		}
	}
	if ([key isEqualToString:JikanEstimateAppleTargetKey]) {
		NSNumber *target = JikanAppleSliderTargetFromValue(value);
		if (!target) return;
		value = target;
		NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
		[prefs setBool:NO forKey:JikanEstimateAppleSyncedKey];
		[prefs synchronize];
	}
	NSNumber *normalized = JikanNormalizedSliderValue(value, key);
	if (normalized) value = normalized;
	if ([key isEqualToString:kBatteryEstimateTargetKey]) {
		NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
		[prefs setBool:NO forKey:kBatteryEstimateSyncedKey];
		[prefs synchronize];
	}
	[super setPreferenceValue:value specifier:specifier];
	if ([key isEqualToString:JikanEstimateSourceKey]) [self _scheduleSpecifiersReload:YES];
	if ([key isEqualToString:@"hideQuickActionButtons"]) [self _updateQuickActionChargingSpecifierAnimated];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
}

- (void)reloadSpecifiers {
	if ([self _isAnyPreferenceSliderTracking] || self.jikanAnimatingQuickActionRow) {
		[self _scheduleSpecifiersReload:NO];
		return;
	}
	self.jikanReloadGeneration++;
	self.jikanLastReloadTime = CFAbsoluteTimeGetCurrent();
	self.jikanReloadQueued = NO;
	[super reloadSpecifiers];
	[self _localizeSpecifiersInPlace:self.specifiers];
	[self _updateBatteryLimitInfoSpecifier];
	[self _configureAxisSliderLeftImages];
	[self _installSliderLongPressEditorsIfNeeded];
}

- (void)_updateBatteryLimitInfoSpecifier {
	PSSpecifier *spec = [self specifierForID:@"batteryLimitInfoRow"];
	if (!spec) return;
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	NSString *syncKey = [JikanEstimateSource(prefs) isEqualToString:@"apple"] ? JikanEstimateAppleSyncedKey : kBatteryEstimateSyncedKey;
	BOOL synced = [prefs boolForKey:syncKey];
	if (synced) {
		[spec setProperty:@"showBatteryLimitSourceInfo" forKey:@"infoAction"];
	} else {
		[spec removePropertyForKey:@"infoAction"];
	}
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
			@"Pill Style": @"jikan.prefs.section.pill_style",
			@"Show after full charge": @"jikan.prefs.row.show_after_full_charge",
			@"Stack": @"jikan.prefs.row.stack",
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
			@"Algorithm": @"jikan.prefs.row.algorithm",
			@"Estimate Target": @"jikan.prefs.row.estimate_target",
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
			NSString *localized = [self _localizedPreferenceText:label];
			specifier.name = localized;
			[specifier setProperty:localized forKey:@"label"];
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
	if ([self _isHiddenEstimateSpecifier:specifier]) return 0;
	id height = [specifier propertyForKey:@"height"];
	if (height) return [height doubleValue];

	return UITableViewAutomaticDimension;
}

- (BOOL)_isHiddenEstimateSpecifier:(PSSpecifier *)specifier {
	NSString *identifier = [specifier propertyForKey:PSIDKey];
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	BOOL apple = [JikanEstimateSource(prefs) isEqualToString:@"apple"];
	return (apple && [identifier isEqualToString:@"batteryEstimateTargetSlider"]) ||
		(!apple && [identifier isEqualToString:@"batteryEstimateAppleTargetSlider"]);
}

- (void)_filterQuickActionChargingSpecifier:(NSMutableArray<PSSpecifier *> *)specifiers {
	PSSpecifier *parent = nil;
	PSSpecifier *child = nil;
	for (PSSpecifier *specifier in specifiers) {
		NSString *identifier = [specifier propertyForKey:PSIDKey];
		if ([identifier isEqualToString:@"hideQuickActionsToggleID"]) parent = specifier;
		if ([identifier isEqualToString:kQuickActionsChargingOnlySpecifierID]) child = specifier;
	}
	self.jikanQuickActionChargingSpecifier = child;
	if (parent && child && [self _isQuickActionChargingOptionHiddenForParent:parent]) {
		[specifiers removeObject:child];
	}
}

- (void)_updateQuickActionChargingSpecifierAnimated {
	PSSpecifier *parent = [self specifierForID:@"hideQuickActionsToggleID"];
	PSSpecifier *child = self.jikanQuickActionChargingSpecifier;
	if (!parent || !child) return;
	BOOL hidden = [self _isQuickActionChargingOptionHiddenForParent:parent];
	BOOL present = [self.specifiers containsObject:child];
	if (hidden == !present) return;

	BOOL animated = !UIAccessibilityIsReduceMotionEnabled();
	NSUInteger generation = ++self.jikanQuickActionAnimationGeneration;
	self.jikanAnimatingQuickActionRow = animated;
	__weak typeof(self) weakSelf = self;
	[CATransaction begin];
	[CATransaction setCompletionBlock:^{
		__strong typeof(weakSelf) self = weakSelf;
		if (self && generation == self.jikanQuickActionAnimationGeneration) self.jikanAnimatingQuickActionRow = NO;
	}];
	if (hidden) {
		[self removeSpecifier:child animated:animated];
	} else {
		[self insertSpecifier:child afterSpecifier:parent animated:animated];
	}
	[CATransaction commit];
}

- (BOOL)_isQuickActionChargingOptionHiddenForParent:(PSSpecifier *)parent {
	id opposingValue = [self readPreferenceValue:parent];
	// Preserve the existing comparisons for stored values without parsing a rule.
	if ([opposingValue isKindOfClass:NSNumber.class]) {
		return [opposingValue intValue] == 0;
	}
	if ([opposingValue isKindOfClass:NSString.class]) {
		return [opposingValue isEqualToString:@"0"];
	}
	if ([opposingValue isKindOfClass:NSArray.class]) {
		return [opposingValue containsObject:@"0"];
	}
	return NO;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	self.jikanPageActive = YES;
	[self _normalizeStoredSliderValues];
	[self _scheduleSpecifiersReload:YES];
}

- (void)_appDidBecomeActive:(NSNotification *)note {
#pragma unused(note)
	[self _scheduleSpecifiersReload:NO];
}

- (BOOL)_viewContainsTrackingSlider:(UIView *)view {
	if ([view isKindOfClass:[UISlider class]] && [(UISlider *)view isTracking]) return YES;
	for (UIView *subview in view.subviews) {
		if ([self _viewContainsTrackingSlider:subview]) return YES;
	}
	return NO;
}

- (BOOL)_isAnyPreferenceSliderTracking {
	return [self _viewContainsTrackingSlider:self.viewIfLoaded];
}

- (void)_scheduleSpecifiersReload:(BOOL)immediate {
	BOOL tracking = [self _isAnyPreferenceSliderTracking];
	BOOL deferReload = tracking || self.jikanAnimatingQuickActionRow;
	if (immediate && !deferReload) {
		[self reloadSpecifiers];
		return;
	}

	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	if (self.jikanReloadQueued) return;

	NSTimeInterval delay = deferReload ? 0.10 : MAX(0.08, 0.25 - (now - self.jikanLastReloadTime));
	self.jikanReloadQueued = YES;
	NSUInteger generation = ++self.jikanReloadGeneration;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || generation != self.jikanReloadGeneration) return;
		self.jikanReloadQueued = NO;
		if (!self.viewIfLoaded.window) {
			return;
		}
		if ([self _isAnyPreferenceSliderTracking] || self.jikanAnimatingQuickActionRow) {
			[self _scheduleSpecifiersReload:NO];
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

- (JikanSliderEditor *)_sliderEditor {
	if (!self.jikanSliderEditor) {
		__weak typeof(self) weakSelf = self;
		self.jikanSliderEditor = [[JikanSliderEditor alloc] initWithController:self canEdit:^{
			return weakSelf.jikanPageActive;
		} willEdit:^{
			[weakSelf _cancelChargeLimiterDetection];
		} didEdit:^{
			[weakSelf _scheduleSpecifiersReload:YES];
		}];
	}
	return self.jikanSliderEditor;
}

- (void)_installSliderLongPressEditorsIfNeeded {
	JikanSliderEditor *editor = [self _sliderEditor];

	UITableView *tableView = self.table;
	for (UITableViewCell *cell in tableView.visibleCells) {
		NSIndexPath *indexPath = [tableView indexPathForCell:cell];
		if (!indexPath) continue;
		[editor configureCell:cell specifier:[self specifierAtIndexPath:indexPath]];
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	if ([cell isKindOfClass:PSTableCell.class]) [(PSTableCell *)cell setSeparatorStyle:UITableViewCellSeparatorStyleNone];
	PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
	BOOL hidden = [self _isHiddenEstimateSpecifier:specifier];
	cell.hidden = hidden;
	cell.accessibilityElementsHidden = hidden;
	cell.userInteractionEnabled = !hidden;
	if (!hidden) [[self _sliderEditor] configureCell:cell specifier:specifier];
	return cell;
}

- (void)_normalizeStoredSliderValues {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	BOOL changed = NO;
	id source = [prefs objectForKey:JikanEstimateSourceKey];
	if (source && (![source isKindOfClass:NSString.class] || (![source isEqualToString:@"jikan"] && ![source isEqualToString:@"apple"]))) {
		[prefs removeObjectForKey:JikanEstimateSourceKey];
		changed = YES;
	}
	id appleTarget = [prefs objectForKey:JikanEstimateAppleTargetKey];
	if (appleTarget && !JikanAppleTargetFromValue(appleTarget)) {
		[prefs setInteger:100 forKey:JikanEstimateAppleTargetKey];
		[prefs setBool:NO forKey:JikanEstimateAppleSyncedKey];
		changed = YES;
	}
	for (NSString *key in JikanSliderDefaults()) {
		id stored = [prefs objectForKey:key];
		if (!stored && ![key isEqualToString:kBatteryEstimateTargetKey]) continue;
		NSNumber *normalized = JikanNormalizedSliderValue(stored, key);
		if (![stored isEqual:normalized]) {
			[prefs setObject:normalized forKey:key];
			if ([key isEqualToString:kBatteryEstimateTargetKey]) [prefs setBool:NO forKey:kBatteryEstimateSyncedKey];
			changed = YES;
		}
	}
	if (changed) {
		[prefs synchronize];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);
	}
}

- (void)_cancelChargeLimiterDetection {
	[self.jikanChargeLimiterDetector cancel];
}

- (void)_finishChargeLimiterDetection:(NSNumber *)detected {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	NSString *source = JikanEstimateSource(prefs);
	if (![source isEqualToString:self.jikanDetectionSource] || JikanEstimateTarget(prefs, source) != self.jikanDetectionTarget) {
		[self _cancelChargeLimiterDetection];
		return;
	}
	[self _cancelChargeLimiterDetection];
	if (!self.jikanPageActive || !self.viewIfLoaded.window || self.presentedViewController || [self _isAnyPreferenceSliderTracking]) return;
	NSString *title;
	NSString *message;
	if (detected) {
		NSNumber *value = [source isEqualToString:@"apple"] ? JikanAppleTargetFromValue(detected) : JikanNormalizedSliderValue(detected, kBatteryEstimateTargetKey);
		if (!value) {
			title = JikanLocalizedString(@"jikan.prefs.alert.detect_limit.unsupported.title", @"Unsupported Apple target");
			message = [NSString stringWithFormat:JikanLocalizedString(@"jikan.prefs.alert.detect_limit.unsupported.message", @"ChargeLimiter reports %@%%. Apple targets are 80, 85, 90, 95, and 100%%. Your target was not changed."), detected];
		} else {
			NSString *targetKey = [source isEqualToString:@"apple"] ? JikanEstimateAppleTargetKey : kBatteryEstimateTargetKey;
			NSString *syncKey = [source isEqualToString:@"apple"] ? JikanEstimateAppleSyncedKey : kBatteryEstimateSyncedKey;
			[prefs setObject:value forKey:targetKey];
			[prefs setBool:YES forKey:syncKey];
			[prefs synchronize];
			CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);
			[self _scheduleSpecifiersReload:YES];
			title = JikanLocalizedString(@"jikan.prefs.alert.detect_limit.single.title", @"ChargeLimiter detected");
			message = [NSString stringWithFormat:JikanLocalizedString(@"jikan.prefs.alert.detect_limit.single.message", @"ChargeLimiter detected Applied battery limit of: %ld%%"), (long)value.integerValue];
		}
	} else {
		title = JikanLocalizedString(@"jikan.prefs.alert.detect_limit.none.title", @"No battery limit found");
		message = JikanLocalizedString(@"jikan.prefs.alert.detect_limit.unchanged.message", @"No ChargeLimiter limit was detected. Your estimate target has not changed.");
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.ok", @"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)detectBatteryLimit {
	if (!self.jikanPageActive || self.presentedViewController) return;
	[self _cancelChargeLimiterDetection];
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	self.jikanDetectionSource = JikanEstimateSource(prefs);
	self.jikanDetectionTarget = JikanEstimateTarget(prefs, self.jikanDetectionSource);
	if (!self.jikanChargeLimiterDetector) self.jikanChargeLimiterDetector = [JikanChargeLimiterDetector new];
	__weak typeof(self) weakSelf = self;
	[self.jikanChargeLimiterDetector detectLimitWithCompletion:^(NSNumber *detected) {
		[weakSelf _finishChargeLimiterDetection:detected];
	}];
}

- (void)showBatteryLimitSourceInfo {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	NSString *source = JikanEstimateSource(prefs);
	NSString *syncKey = [source isEqualToString:@"apple"] ? JikanEstimateAppleSyncedKey : kBatteryEstimateSyncedKey;
	if (![prefs boolForKey:syncKey] || !self.jikanPageActive || self.presentedViewController) return;
	NSNumber *value = @(JikanEstimateTarget(prefs, source));
	NSString *message = [NSString stringWithFormat:JikanLocalizedString(@"jikan.prefs.alert.limit_sources.applied.message", @"Last applied from ChargeLimiter: %ld%%"), (long)value.integerValue];
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
	CFNotificationCenterPostNotification(darwin, (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);
	CFNotificationCenterPostNotification(darwin, (__bridge CFStringRef)JikanPreviewRequestNotification, NULL, NULL, YES);
}

- (void)resetPreferences {
	[self _cancelChargeLimiterDetection];
	[self.jikanSliderEditor dismiss];
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	if (!prefs) return;

	NSArray<NSString *> *keys = @[
		@"enabled",
		@"platterYOffset",
		@"pillBackgroundOpacityPercent",
		@"hideQuickActionButtons",
		@"hideQuickActionButtonsOnlyWhenCharging",
		@"showRemainingBatteryTime",
		@"autoResizeRemainingBatteryTime",
		@"tapToShowWattage",
		JikanStackItemsKey,
		JikanTemperatureUnitKey,
		JikanPillAppearanceKey,
		kBatteryEstimateTargetKey,
		kBatteryEstimateSyncedKey,
		JikanEstimateSourceKey,
		JikanEstimateAppleTargetKey,
		JikanEstimateAppleSyncedKey,
		@"showAfterFullCharge"
	];

	JikanResetPillPosition(prefs);
	for (NSString *key in keys) {
		[prefs removeObjectForKey:key];
	}

	NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:[[self bundle] pathForResource:@"Root" ofType:@"plist"]];
	NSDictionary *automaticPositionDefaults = JikanPillPositionSliderDefaults();
	for (NSDictionary *item in root[@"items"]) {
		if (item[@"key"] && automaticPositionDefaults[item[@"key"]]) continue;
		if ([item[@"defaults"] isEqual:JikanPreferencesSuite] && item[@"key"] && item[@"default"]) {
			id value = JikanNormalizedSliderValue(item[@"default"], item[@"key"]) ?: item[@"default"];
			[prefs setObject:value forKey:item[@"key"]];
		}
	}
	[prefs setInteger:100 forKey:kBatteryEstimateTargetKey];
	[prefs setBool:NO forKey:kBatteryEstimateSyncedKey];
	[prefs setObject:@"apple" forKey:JikanEstimateSourceKey];
	[prefs setInteger:100 forKey:JikanEstimateAppleTargetKey];
	[prefs setBool:NO forKey:JikanEstimateAppleSyncedKey];
	[prefs synchronize];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);

	dispatch_async(dispatch_get_main_queue(), ^{
		[self _scheduleSpecifiersReload:YES];
	});
}

- (void)resetPillPosition {
	[self _cancelChargeLimiterDetection];
	[self.jikanSliderEditor dismiss];
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	if (!prefs) return;

	JikanResetPillPosition(prefs);

	[prefs synchronize];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);

	dispatch_async(dispatch_get_main_queue(), ^{
		[self _scheduleSpecifiersReload:YES];
	});
}

@end

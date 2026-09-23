#import <math.h>

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
@property (nonatomic, assign) NSUInteger jikanDetectionGeneration;
@property (nonatomic, strong) NSOperation *jikanDetectionOperation;
@property (nonatomic, strong) NSURLSessionDataTask *jikanDetectionTask;
@property (nonatomic, weak) UIAlertController *jikanSliderEditorAlert;
@property (nonatomic, weak) UIAlertAction *jikanSliderEditorSave;
@property (nonatomic, copy) NSDictionary *jikanSliderEditorConfig;
@property (nonatomic, strong) NSLocale *jikanSliderEditorLocale;
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

static NSDictionary<NSString *, NSNumber *> *JikanSliderDefaults(void) {
	return @{
		kPillBackgroundOpacityKey: @100,
		kBatteryEstimateTargetKey: @100,
		@"pillPosXPortraitPercent": @50,
		@"pillPosYPortraitPercent": @84,
		@"pillPosXLandscapePercent": @50,
		@"pillPosYLandscapePercent": @84
	};
}

static BOOL JikanParseNumber(NSString *text, NSLocale *locale, double *result) {
	if (![text isKindOfClass:NSString.class]) return NO;
	NSString *input = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!input.length) return NO;
	NSNumberFormatter *formatter = [NSNumberFormatter new];
	formatter.locale = locale;
	formatter.numberStyle = NSNumberFormatterDecimalStyle;
	formatter.usesGroupingSeparator = NO;
	formatter.lenient = NO;
	NSString *decimal = formatter.decimalSeparator;
	NSString *unsignedInput = input;
	if ([input hasPrefix:@"+"] || [input hasPrefix:@"-"]) unsignedInput = [input substringFromIndex:1];
	NSArray<NSString *> *parts = [unsignedInput componentsSeparatedByString:decimal];
	if (parts.count > 2) return NO;
	NSUInteger digitCount = 0;
	for (NSString *part in parts) {
		if ([part rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) return NO;
		digitCount += part.length;
	}
	if (!digitCount) return NO;
	NSNumber *number = [formatter numberFromString:input];
	if (!number || !isfinite(number.doubleValue)) return NO;
	if (result) *result = number.doubleValue;
	return YES;
}

static NSNumber *JikanNormalizedSliderValue(id value, NSString *key) {
	NSNumber *fallback = JikanSliderDefaults()[key];
	if (!fallback) return nil;
	double raw = fallback.doubleValue;
	if ([value isKindOfClass:NSNumber.class]) raw = [value doubleValue];
	else if ([value isKindOfClass:NSString.class]) {
		JikanParseNumber(value, [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"], &raw);
	}
	if (!isfinite(raw)) raw = fallback.doubleValue;
	double minimum = [key isEqualToString:kBatteryEstimateTargetKey] ? 1.0 : 0.0;
	return @((NSInteger)llround(MAX(minimum, MIN(100.0, raw))));
}

static NSNumber *JikanDetectedLimit(id value) {
	double raw = 0;
	if ([value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) raw = [value doubleValue];
	else if (![value isKindOfClass:NSString.class] || !JikanParseNumber(value, [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"], &raw))
		return nil;
	if (!isfinite(raw) || raw < 1 || raw > 100) return nil;
	return JikanNormalizedSliderValue(@(raw), kBatteryEstimateTargetKey);
}

static BOOL JikanIsChargeLimiterApp(NSString *path) {
	BOOL directory = NO;
	return [path.lastPathComponent isEqualToString:@"ChargeLimiter.app"] &&
		[NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] && directory;
}

static BOOL JikanChargeLimiterInstalled(NSOperation *operation) {
	if (operation.cancelled) return NO;
	if (JikanIsChargeLimiterApp(jbroot(@"/Applications/ChargeLimiter.app")) || JikanIsChargeLimiterApp(@"/Applications/ChargeLimiter.app")) return YES;
	for (NSString *root in @[@"/var/containers/Bundle/Application", @"/private/var/containers/Bundle/Application"]) {
		if (operation.cancelled) return NO;
		for (NSString *entry in [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil]) {
			if (operation.cancelled) return NO;
			NSString *path = [[root stringByAppendingPathComponent:entry] stringByAppendingPathComponent:@"ChargeLimiter.app"];
			if (JikanIsChargeLimiterApp(path)) return YES;
		}
	}
	return NO;
}

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
		if (!self.jikanObservingPreferences) {
			CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, JikanPrefsDidChange, (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
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
	if (tableView) tableView.tableHeaderView = header;
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
	[self _dismissSliderEditor];
}

- (void)dealloc {
	[_jikanDetectionOperation cancel];
	[_jikanDetectionTask cancel];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL);
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"key"];
	[self _cancelChargeLimiterDetection];
	NSNumber *normalized = JikanNormalizedSliderValue(value, key);
	if (normalized) value = normalized;
	if ([key isEqualToString:kBatteryEstimateTargetKey]) {
		NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
		[prefs setBool:NO forKey:kBatteryEstimateSyncedKey];
		[prefs synchronize];
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
	if ([self _isAnyPreferenceSliderTracking]) {
		[self _scheduleSpecifiersReload:NO];
		return;
	}
	self.jikanReloadGeneration++;
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
	if (immediate && !tracking) {
		[self reloadSpecifiers];
		return;
	}

	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	if (self.jikanReloadQueued) return;

	NSTimeInterval delay = tracking ? 0.10 : MAX(0.08, 0.25 - (now - self.jikanLastReloadTime));
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
		if ([self _isAnyPreferenceSliderTracking]) {
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

- (NSArray<NSDictionary *> *)_sliderEditorConfigs {
	return @[
		@{@"id": @"pillBackgroundOpacitySlider", @"key": kPillBackgroundOpacityKey, @"title": JikanLocalizedString(@"jikan.prefs.slider.opacity.title", @"Pill Background Opacity"), @"min": @0.0, @"max": @100.0, @"decimals": @0},
		@{@"id": @"batteryEstimateTargetSlider", @"key": kBatteryEstimateTargetKey, @"title": JikanLocalizedString(@"jikan.prefs.slider.estimate_target.title", @"Estimate Target"), @"min": @1.0, @"max": @100.0, @"decimals": @0},
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

	UITableView *tableView = self.table;
	for (UITableViewCell *cell in tableView.visibleCells) {
		NSIndexPath *indexPath = [tableView indexPathForCell:cell];
		if (!indexPath) continue;
		[self _configureSliderEditorForCell:cell specifier:[self specifierAtIndexPath:indexPath]];
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	[self _configureSliderEditorForCell:cell specifier:[self specifierAtIndexPath:indexPath]];
	return cell;
}

- (void)_configureSliderEditorForCell:(UITableViewCell *)cell specifier:(PSSpecifier *)specifier {
	UISlider *slider = [self _firstSliderInView:cell.contentView];
	if (!slider) return;
	NSDictionary *config = nil;
	for (NSDictionary *candidate in [self _sliderEditorConfigs]) {
		if ([candidate[@"id"] isEqual:[specifier propertyForKey:PSIDKey]]) {
			config = candidate;
			break;
		}
	}
	objc_setAssociatedObject(slider, kJikanSliderEditorConfigKey, config, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(slider, kJikanSliderThumbOnlyKey, @(config != nil), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	if (!config || [objc_getAssociatedObject(slider, kJikanSliderEditorInstalledKey) boolValue]) return;
	JikanInstallSliderTrackingGuardIfNeeded();

	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_handleSliderKnobHold:)];
	hold.minimumPressDuration = 0.35;
	hold.cancelsTouchesInView = NO;
	[slider addGestureRecognizer:hold];
	objc_setAssociatedObject(slider, kJikanSliderEditorInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

- (void)_dismissSliderEditor {
	UIAlertController *alert = self.jikanSliderEditorAlert;
	self.jikanSliderEditorAlert = nil;
	self.jikanSliderEditorSave = nil;
	self.jikanSliderEditorConfig = nil;
	self.jikanSliderEditorLocale = nil;
	if (alert) [alert dismissViewControllerAnimated:NO completion:nil];
}

- (BOOL)_sliderEditorValue:(double *)value {
	NSString *text = self.jikanSliderEditorAlert.textFields.firstObject.text;
	double parsed = 0;
	if (!JikanParseNumber(text, self.jikanSliderEditorLocale, &parsed)) return NO;
	if (parsed < [self.jikanSliderEditorConfig[@"min"] doubleValue] || parsed > [self.jikanSliderEditorConfig[@"max"] doubleValue]) return NO;
	if (value) *value = parsed;
	return YES;
}

- (void)_sliderEditorTextChanged:(UITextField *)field {
#pragma unused(field)
	BOOL valid = [self _sliderEditorValue:NULL];
	self.jikanSliderEditorSave.enabled = valid;
	NSString *format = valid ? JikanLocalizedString(@"jikan.prefs.alert.slider_range.message", @"Enter a value from %.0f to %.0f") : JikanLocalizedString(@"jikan.prefs.alert.slider_invalid.message", @"Enter a valid number from %.0f to %.0f.");
	self.jikanSliderEditorAlert.message = [NSString stringWithFormat:format, [self.jikanSliderEditorConfig[@"min"] doubleValue], [self.jikanSliderEditorConfig[@"max"] doubleValue]];
}

- (void)_presentSliderEditorWithConfig:(NSDictionary *)config fallbackValue:(double)fallback {
	NSString *prefsKey = config[@"key"];
	NSString *title = config[@"title"];
	if (!JikanSliderDefaults()[prefsKey] || !title.length || !self.jikanPageActive || self.presentedViewController) return;
	[self _cancelChargeLimiterDetection];
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	NSNumber *currentValue = JikanNormalizedSliderValue([prefs objectForKey:prefsKey] ?: @(fallback), prefsKey);
	NSLocale *locale = NSLocale.currentLocale;
	NSNumberFormatter *formatter = [NSNumberFormatter new];
	formatter.locale = locale;
	formatter.numberStyle = NSNumberFormatterDecimalStyle;
	formatter.usesGroupingSeparator = NO;
	formatter.maximumFractionDigits = 0;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.keyboardType = UIKeyboardTypeDecimalPad;
		textField.text = [formatter stringFromNumber:currentValue];
		[textField addTarget:self action:@selector(_sliderEditorTextChanged:) forControlEvents:UIControlEventEditingChanged];
	}];
	self.jikanSliderEditorAlert = alert;
	self.jikanSliderEditorConfig = config;
	self.jikanSliderEditorLocale = locale;
	__weak typeof(self) weakSelf = self;
	__weak UIAlertController *weakAlert = alert;
	UIAlertAction *save = [UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.save", @"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || !self.jikanPageActive || self.jikanSliderEditorAlert != weakAlert) return;
		double value = 0;
		if (![self _sliderEditorValue:&value]) return;
		PSSpecifier *specifier = [self specifierForID:config[@"id"]];
		if (!specifier) return;
		[self setPreferenceValue:JikanNormalizedSliderValue(@(value), prefsKey) specifier:specifier];
		self.jikanSliderEditorAlert = nil;
		self.jikanSliderEditorSave = nil;
		self.jikanSliderEditorConfig = nil;
		self.jikanSliderEditorLocale = nil;
		[self _scheduleSpecifiersReload:YES];
	}];
	[alert addAction:[UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
		if (weakSelf.jikanSliderEditorAlert == weakAlert) {
			weakSelf.jikanSliderEditorAlert = nil;
			weakSelf.jikanSliderEditorSave = nil;
			weakSelf.jikanSliderEditorConfig = nil;
			weakSelf.jikanSliderEditorLocale = nil;
		}
	}]];
	[alert addAction:save];
	self.jikanSliderEditorSave = save;
	[self _sliderEditorTextChanged:alert.textFields.firstObject];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)_normalizeStoredSliderValues {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	BOOL changed = NO;
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
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);
	}
}

- (void)_cancelChargeLimiterDetection {
	self.jikanDetectionGeneration++;
	[self.jikanDetectionOperation cancel];
	[self.jikanDetectionTask cancel];
	self.jikanDetectionOperation = nil;
	self.jikanDetectionTask = nil;
}

- (void)_finishChargeLimiterDetection:(NSNumber *)detected generation:(NSUInteger)generation {
	if (generation != self.jikanDetectionGeneration) return;
	[self _cancelChargeLimiterDetection];
	if (!self.jikanPageActive || !self.viewIfLoaded.window || self.presentedViewController || [self _isAnyPreferenceSliderTracking]) return;
	NSString *title;
	NSString *message;
	if (detected) {
		NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
		NSNumber *value = JikanNormalizedSliderValue(detected, kBatteryEstimateTargetKey);
		[prefs setObject:value forKey:kBatteryEstimateTargetKey];
		[prefs setBool:YES forKey:kBatteryEstimateSyncedKey];
		[prefs synchronize];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);
		[self _scheduleSpecifiersReload:YES];
		title = JikanLocalizedString(@"jikan.prefs.alert.detect_limit.single.title", @"ChargeLimiter detected");
		message = [NSString stringWithFormat:JikanLocalizedString(@"jikan.prefs.alert.detect_limit.single.message", @"ChargeLimiter detected Applied battery limit of: %ld%%"), (long)value.integerValue];
	} else {
		title = JikanLocalizedString(@"jikan.prefs.alert.detect_limit.none.title", @"No battery limit found");
		message = JikanLocalizedString(@"jikan.prefs.alert.detect_limit.unchanged.message", @"No ChargeLimiter limit was detected. Your estimate target has not changed.");
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.ok", @"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)_requestChargeLimiterLimitForGeneration:(NSUInteger)generation {
	if (generation != self.jikanDetectionGeneration || !self.jikanPageActive) return;
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:1230"]];
	request.HTTPMethod = @"POST";
	request.timeoutInterval = 1.5;
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"api": @"get_conf", @"key": @"charge_above"} options:0 error:nil];
	__weak typeof(self) weakSelf = self;
	self.jikanDetectionTask = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		NSNumber *detected = nil;
		if (!error && data.length && [response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode == 200) {
			id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			if ([json isKindOfClass:NSDictionary.class]) {
				id status = json[@"status"];
				double statusValue = NAN;
				if ([status isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)status) != CFBooleanGetTypeID()) statusValue = [status doubleValue];
				else if ([status isKindOfClass:NSString.class])
					JikanParseNumber(status, [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"], &statusValue);
				if (statusValue == 0) detected = JikanDetectedLimit(json[@"data"]);
			}
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf _finishChargeLimiterDetection:detected generation:generation];
		});
	}];
	[self.jikanDetectionTask resume];
}

- (void)detectBatteryLimit {
	if (!self.jikanPageActive || self.presentedViewController) return;
	[self _cancelChargeLimiterDetection];
	NSUInteger generation = self.jikanDetectionGeneration;
	__weak typeof(self) weakSelf = self;
	NSBlockOperation *operation = [NSBlockOperation new];
	__weak NSBlockOperation *weakOperation = operation;
	[operation addExecutionBlock:^{
		NSBlockOperation *operation = weakOperation;
		if (!operation || operation.cancelled) return;
		BOOL installed = JikanChargeLimiterInstalled(operation);
		if (operation.cancelled) return;
		NSNumber *detected = nil;
		if (installed) {
			NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:@"/var/root/aldente.conf"];
			detected = JikanDetectedLimit(config[@"charge_above"]);
		}
		if (operation.cancelled) return;
		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self || generation != self.jikanDetectionGeneration || operation.cancelled) return;
			self.jikanDetectionOperation = nil;
			if (detected || !installed) [self _finishChargeLimiterDetection:detected generation:generation];
			else
				[self _requestChargeLimiterLimitForGeneration:generation];
		});
	}];
	self.jikanDetectionOperation = operation;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [operation start]; });
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[weakSelf _finishChargeLimiterDetection:nil generation:generation];
	});
}

- (void)showBatteryLimitSourceInfo {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	if (![prefs boolForKey:kBatteryEstimateSyncedKey] || !self.jikanPageActive || self.presentedViewController) return;
	NSNumber *value = JikanNormalizedSliderValue([prefs objectForKey:kBatteryEstimateTargetKey], kBatteryEstimateTargetKey);
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
	CFNotificationCenterPostNotification(darwin, (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);
	CFNotificationCenterPostNotification(darwin, (__bridge CFStringRef)kJikanOpenNCPreviewNotification, NULL, NULL, YES);
}

- (void)resetPreferences {
	[self _cancelChargeLimiterDetection];
	[self _dismissSliderEditor];
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

	NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:[[self bundle] pathForResource:@"Root" ofType:@"plist"]];
	NSSet *automaticPositionKeys = [NSSet setWithArray:@[@"pillPosXPortraitPercent", @"pillPosYPortraitPercent", @"pillPosXLandscapePercent", @"pillPosYLandscapePercent"]];
	for (NSDictionary *item in root[@"items"]) {
		if ([automaticPositionKeys containsObject:item[@"key"]]) continue;
		if ([item[@"defaults"] isEqual:kJikanPrefsSuite] && item[@"key"] && item[@"default"]) {
			id value = JikanNormalizedSliderValue(item[@"default"], item[@"key"]) ?: item[@"default"];
			[prefs setObject:value forKey:item[@"key"]];
		}
	}
	[prefs setInteger:100 forKey:kBatteryEstimateTargetKey];
	[prefs setBool:NO forKey:kBatteryEstimateSyncedKey];
	[prefs synchronize];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);

	dispatch_async(dispatch_get_main_queue(), ^{
		[self _scheduleSpecifiersReload:YES];
	});
}

- (void)resetPillPosition {
	[self _cancelChargeLimiterDetection];
	[self _dismissSliderEditor];
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

#include "JikanRootListController.h"

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

	self.navigationController.navigationBar.prefersLargeTitles = NO;
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

	NSArray<NSString *> *subtitles = @[@"Show time left to full charge on your lock screen"];
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
	[self collectDynamicSpecifiersFromArray:self.specifiers];
	[self _configureAxisSliderLeftImages];
	[self _installSliderLongPressEditorsIfNeeded];
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

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.hasDynamicSpecifiers) {
		PSSpecifier *dynamicSpecifier = [self specifierAtIndexPath:indexPath];
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
		return 66.0;
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
		@{@"id": @"pillBackgroundOpacitySlider", @"key": kPillBackgroundOpacityKey, @"title": @"Pill Background Opacity", @"min": @0.0, @"max": @100.0, @"decimals": @1},
		@{@"id": @"pillPosXPortraitSlider", @"key": @"pillPosXPortraitPercent", @"title": @"Portrait X", @"min": @0.0, @"max": @100.0, @"decimals": @1},
		@{@"id": @"pillPosYPortraitSlider", @"key": @"pillPosYPortraitPercent", @"title": @"Portrait Y", @"min": @0.0, @"max": @100.0, @"decimals": @1},
		@{@"id": @"pillPosXLandscapeSlider", @"key": @"pillPosXLandscapePercent", @"title": @"Landscape X", @"min": @0.0, @"max": @100.0, @"decimals": @1},
		@{@"id": @"pillPosYLandscapeSlider", @"key": @"pillPosYLandscapePercent", @"title": @"Landscape Y", @"min": @0.0, @"max": @100.0, @"decimals": @1}
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

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:[NSString stringWithFormat:@"Enter a value from %.0f to %.0f", minValue, maxValue] preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *_Nonnull textField) {
		textField.keyboardType = UIKeyboardTypeDecimalPad;
		textField.placeholder = [NSString stringWithFormat:@"%.0f-%.0f", minValue, maxValue];
		textField.text = [NSString stringWithFormat:[NSString stringWithFormat:@"%%.%ldf", (long)decimals], currentValue];
	}];

	__typeof(self) weakSelf = self;
	UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_Nonnull action) {
		UITextField *tf = alert.textFields.firstObject;
		double value = tf.text.doubleValue;
		if (!isfinite(value)) value = currentValue;
		value = MAX(minValue, MIN(maxValue, value));

		[prefs setDouble:value forKey:prefsKey];
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

- (void)openPillBackgroundOpacityEditor {
	NSDictionary *config = [self _sliderEditorConfigs].firstObject;
	[self _presentSliderEditorWithConfig:config fallbackValue:100.0];
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

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
		[JikanPreferencesPresentation localizeSpecifiers:_specifiers];
		[self _configureQuickActionAvailability:_specifiers];
		[self _filterQuickActionChargingSpecifier:_specifiers];
		[self _updateBatteryLimitInfoSpecifier];
		[JikanPreferencesPresentation configureAxisSliderLeftImagesForController:self];
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

	[self _installSliderLongPressEditorsIfNeeded];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[JikanPreferencesPersistence normalizeStoredValuesInPreferences:[[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite]];

	self.navigationController.navigationBar.prefersLargeTitles = NO;
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
	self.navigationItem.titleView = nil;

	UITableView *tableView = self.table ?: [self valueForKey:@"_table"];
	if (tableView) {
		tableView.tableHeaderView = nil;
		tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	}
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
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
	if (([key isEqualToString:@"hideQuickActionButtons"] || [key isEqualToString:@"hideQuickActionButtonsOnlyWhenCharging"]) && !JikanDeviceSupportsQuickActionButtons()) return;
	[self _cancelChargeLimiterDetection];
	if ([key isEqualToString:JikanEstimateSourceKey]) [self.jikanSliderEditor dismiss];
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	if (![JikanPreferencesPersistence prepareValue:&value forKey:key preferences:prefs]) return;
	[super setPreferenceValue:value specifier:specifier];
	if ([key isEqualToString:JikanEstimateSourceKey]) [self _scheduleSpecifiersReload:YES];
	if ([key isEqualToString:@"hideQuickActionButtons"]) [self _updateQuickActionChargingSpecifierAnimated];
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
	[JikanPreferencesPresentation localizeSpecifiers:self.specifiers];
	[self _updateBatteryLimitInfoSpecifier];
	[JikanPreferencesPresentation configureAxisSliderLeftImagesForController:self];
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

- (void)_configureQuickActionAvailability:(NSArray<PSSpecifier *> *)specifiers {
	BOOL supported = JikanDeviceSupportsQuickActionButtons();
	for (PSSpecifier *specifier in specifiers) {
		NSString *identifier = [specifier propertyForKey:PSIDKey];
		if ([identifier isEqualToString:@"hideQuickActionsToggleID"] || [identifier isEqualToString:kQuickActionsChargingOnlySpecifierID]) {
			[specifier setProperty:@(supported) forKey:PSEnabledKey];
		} else if ([identifier isEqualToString:@"quickActionsGroupID"] && !supported) {
			[specifier setProperty:JikanLocalizedString(@"jikan.prefs.footer.quick_actions_unavailable", @"Quick Action buttons are unavailable on this device") forKey:@"footerText"];
		}
	}
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
	[JikanPreferencesPersistence normalizeStoredValuesInPreferences:[[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite]];
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

- (BOOL)_isPillStyleSection:(NSInteger)section {
	PSSpecifier *specifier = [self specifierForID:@"pillStylePreviewRow"];
	NSIndexPath *indexPath = specifier ? [self indexPathForSpecifier:specifier] : nil;
	return indexPath && indexPath.section == section;
}

- (BOOL)_isSpacerSectionInTableView:(UITableView *)tableView section:(NSInteger)section {
	NSString *header = [super tableView:tableView titleForHeaderInSection:section];
	return [JikanPreferencesPresentation isSpacerHeaderTitle:header];
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if ([self _isPillStyleSection:section]) {
		return [JikanPreferencesPresentation legendFooterView];
	}
	return [super tableView:tableView viewForFooterInSection:section];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if ([self _isSpacerSectionInTableView:tableView section:section]) {
		return [JikanPreferencesPresentation spacerHeaderView];
	}
	return [super tableView:tableView viewForHeaderInSection:section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if ([self _isPillStyleSection:section]) {
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

	[JikanPreferencesPersistence resetPreferences:prefs bundle:[self bundle]];

	dispatch_async(dispatch_get_main_queue(), ^{
		[self _scheduleSpecifiersReload:YES];
	});
}

- (void)resetPillPosition {
	[self _cancelChargeLimiterDetection];
	[self.jikanSliderEditor dismiss];
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	if (!prefs) return;

	[JikanPreferencesPersistence resetPillPositionInPreferences:prefs];

	dispatch_async(dispatch_get_main_queue(), ^{
		[self _scheduleSpecifiersReload:YES];
	});
}

@end

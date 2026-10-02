#import "JikanPreferencesPersistence.h"

static NSString *const kBatteryEstimateTargetKey = @"batteryEstimateTargetPercent";
static NSString *const kBatteryEstimateSyncedKey = @"batteryEstimateSyncedWithChargeLimiter";

@implementation JikanPreferencesPersistence

+ (BOOL)prepareValue:(id *)preparedValue forKey:(NSString *)key preferences:(NSUserDefaults *)prefs {
	id value = *preparedValue;
	if ([key isEqualToString:JikanEstimateSourceKey]) {
		value = [value isKindOfClass:NSString.class] && [value isEqualToString:@"jikan"] ? @"jikan" : @"apple";
		if ([value isEqualToString:@"apple"] && ![prefs objectForKey:JikanEstimateAppleTargetKey]) {
			NSInteger jikanTarget = JikanEstimateTarget(prefs, @"jikan");
			[prefs setInteger:JikanAppleTargetIsSupported(jikanTarget) ? jikanTarget : 100 forKey:JikanEstimateAppleTargetKey];
			[prefs synchronize];
		}
	}
	if ([key isEqualToString:JikanEstimateAppleTargetKey]) {
		NSNumber *target = JikanAppleSliderTargetFromValue(value);
		if (!target) return NO;
		value = target;
		[prefs setBool:NO forKey:JikanEstimateAppleSyncedKey];
		[prefs synchronize];
	}
	NSNumber *normalized = JikanNormalizedSliderValue(value, key);
	if (normalized) value = normalized;
	if ([key isEqualToString:kBatteryEstimateTargetKey]) {
		[prefs setBool:NO forKey:kBatteryEstimateSyncedKey];
		[prefs synchronize];
	}
	*preparedValue = value;
	return YES;
}

+ (void)normalizeStoredValuesInPreferences:(NSUserDefaults *)prefs {
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

+ (void)resetPreferences:(NSUserDefaults *)prefs bundle:(NSBundle *)bundle {
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

	NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:[bundle pathForResource:@"Root" ofType:@"plist"]];
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
}

+ (void)resetPillPositionInPreferences:(NSUserDefaults *)prefs {
	JikanResetPillPosition(prefs);

	[prefs synchronize];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);
}

@end

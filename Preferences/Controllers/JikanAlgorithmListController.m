#import "JikanAlgorithmListController.h"
#import "../../Shared/JikanEstimateSettings.h"
#import "../../Shared/JikanPreferences.h"

@implementation JikanAlgorithmListController

- (NSString *)_algorithmDescription {
	NSString *recommended = JikanLocalizedString(@"jikan.prefs.algorithm.recommended", @"Recommended");
	NSString *jikan = JikanLocalizedString(@"jikan.prefs.algorithm.jikan_description", @"Estimates time from your charging history and current battery readings. Choose any target from 1% to 100%.");
	NSString *apple = JikanLocalizedString(@"jikan.prefs.algorithm.apple_description", @"Uses a fixed local copy of Apple's charging models. Choose 80%, 85%, 90%, 95%, or 100%.");
	NSString *note = JikanLocalizedString(@"jikan.prefs.algorithm.apple_telemetry", @"Apple is the default when its required inputs are available. Otherwise Jikan is selected automatically. You can still choose Apple with estimated inputs.");
	BOOL appleAvailable = JikanAppleHasRequiredNativeInputs();
	NSString *appleLabel = appleAvailable ? [NSString stringWithFormat:@"Apple (%@)", recommended] : @"Apple";
	NSString *jikanLabel = appleAvailable ? @"Jikan" : [NSString stringWithFormat:@"Jikan (%@)", recommended];
	NSString *description = [NSString stringWithFormat:@"%@: %@\n\n%@: %@\n\n%@", appleLabel, apple, jikanLabel, jikan, note];
	if (JikanRecentAppleEstimateFailure()) {
		NSString *unavailable = JikanLocalizedString(@"jikan.prefs.algorithm.apple_unavailable", @"Some battery readings were unavailable recently. Apple predictions may remain unavailable even with estimated input power.");
		description = [description stringByAppendingFormat:@"\n\n%@", unavailable];
	}
	if ([[[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite] boolForKey:JikanEstimateAppleEstimatedPowerKey]) {
		description = [description stringByAppendingFormat:@"\n\n%@", JikanLocalizedString(@"jikan.prefs.algorithm.apple_estimation_enabled", @"Adapter-based approximation is enabled. Estimates using it are marked ≈. Select Jikan to disable it.")];
	}
	return description;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	NSArray *values = [self.specifier propertyForKey:PSValidValuesKey];
	NSUInteger appleIndex = [values isKindOfClass:NSArray.class] ? [values indexOfObject:@"apple"] : NSNotFound;
	BOOL selectingApple = indexPath.section == 0 && appleIndex != NSNotFound && indexPath.row == (NSInteger)appleIndex;
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	if (!selectingApple || [prefs boolForKey:JikanEstimateAppleEstimatedPowerKey] || JikanAppleHasRequiredNativeInputs()) {
		[super tableView:tableView didSelectRowAtIndexPath:indexPath];
		return;
	}
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	UIAlertController *warning = [UIAlertController alertControllerWithTitle:JikanLocalizedString(@"jikan.prefs.algorithm.warning.title", @"Estimated Charging Power")
		message:JikanLocalizedString(@"jikan.prefs.algorithm.warning.message", @"This device cannot provide an accurate measured input source. Switching models now will use estimated sources which may produce inaccurate estimates.")
		preferredStyle:UIAlertControllerStyleAlert];
	[warning addAction:[UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[warning addAction:[UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.prefs.algorithm.warning.allow", @"Use Estimated Power") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;
		[prefs setBool:YES forKey:JikanEstimateAppleEstimatedPowerKey];
		[prefs synchronize];
		[super tableView:tableView didSelectRowAtIndexPath:indexPath];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);
		[tableView reloadData];
		for (PSSpecifier *item in self.specifiers) {
			if ([[item propertyForKey:PSIDKey] isEqualToString:@"jikanAlgorithmDescriptions"]) {
				[item setProperty:[self _algorithmDescription] forKey:PSFooterTextGroupKey];
				[self reloadSpecifier:item animated:NO];
				break;
			}
		}
	}]];
	[self presentViewController:warning animated:YES completion:nil];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	if ([[specifier propertyForKey:@"key"] isEqualToString:JikanEstimateSourceKey]) {
		return JikanEstimateSource([[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite]);
	}
	return [super readPreferenceValue:specifier];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	for (PSSpecifier *item in self.specifiers) {
		if ([[item propertyForKey:PSIDKey] isEqual:@"jikanAlgorithmDescriptions"]) {
			[item setProperty:[self _algorithmDescription] forKey:PSFooterTextGroupKey];
			[self reloadSpecifier:item animated:NO];
			break;
		}
	}
}

- (NSArray *)specifiers {
	NSArray *items = [super specifiers];
	if (!items) return nil;
	for (PSSpecifier *item in items) {
		if ([[item propertyForKey:PSIDKey] isEqualToString:@"jikanAlgorithmDescriptions"]) return items;
	}

	PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
	[group setProperty:@"jikanAlgorithmDescriptions" forKey:PSIDKey];
	[group setProperty:[self _algorithmDescription] forKey:PSFooterTextGroupKey];
	_specifiers = [items mutableCopy];
	[_specifiers addObject:group];
	return _specifiers;
}

@end

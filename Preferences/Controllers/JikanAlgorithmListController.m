#import "JikanAlgorithmListController.h"

@implementation JikanAlgorithmListController

- (NSString *)_algorithmDescription {
	NSString *recommended = JikanLocalizedString(@"jikan.prefs.algorithm.recommended", @"Recommended");
	NSString *jikan = JikanLocalizedString(@"jikan.prefs.algorithm.jikan_description", @"Estimates time from your charging history and current battery readings. Choose any target from 1% to 100%.");
	NSString *apple = JikanLocalizedString(@"jikan.prefs.algorithm.apple_description", @"Uses a fixed local copy of Apple's charging models. Choose 80%, 85%, 90%, 95%, or 100%.");
	NSString *telemetry = JikanLocalizedString(@"jikan.prefs.algorithm.apple_telemetry", @"Uses native input-power readings when available, or measured input power on supported wired charging paths. If required readings are unavailable, select Jikan.");
	NSString *description = [NSString stringWithFormat:@"Apple (%@): %@\n%@\n\nJikan: %@", recommended, apple, telemetry, jikan];
	if (JikanRecentAppleEstimateFailure()) {
		NSString *unavailable = JikanLocalizedString(@"jikan.prefs.algorithm.apple_unavailable", @"Apple estimates are currently unavailable because required battery readings could not be obtained. Select Jikan to use charging history and battery current instead.");
		description = [description stringByAppendingFormat:@"\n\n%@", unavailable];
	}
	return description;
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

#import "JikanRootListController.h"

@interface JikanAlgorithmListController : PSListItemsController
@end

@implementation JikanAlgorithmListController

- (NSArray *)specifiers {
	NSArray *items = [super specifiers];
	if (!items) return nil;
	for (PSSpecifier *item in items) {
		if ([[item propertyForKey:PSIDKey] isEqualToString:@"jikanAlgorithmDescriptions"]) return items;
	}

	NSString *jikan = JikanLocalizedString(@"jikan.prefs.algorithm.jikan_description", @"Estimates time from your charging history and current battery readings. Choose any target from 1% to 100%.");
	NSString *apple = JikanLocalizedString(@"jikan.prefs.algorithm.apple_description", @"Uses a fixed local copy of Apple's charging models. Choose 80%, 85%, 90%, 95%, or 100%.");
	PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
	[group setProperty:@"jikanAlgorithmDescriptions" forKey:PSIDKey];
	[group setProperty:[NSString stringWithFormat:@"Jikan: %@\n\nApple: %@", jikan, apple] forKey:PSFooterTextGroupKey];
	_specifiers = [items mutableCopy];
	[_specifiers addObject:group];
	return _specifiers;
}

@end

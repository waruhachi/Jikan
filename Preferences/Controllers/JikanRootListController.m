#include "JikanRootListController.h"

@implementation JikanRootListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}

	return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];
}

- (void)respring {
	pid_t pid;
	const char *args[] = {"killall", "SpringBoard", NULL};
	int result = posix_spawn(&pid, jbroot("/usr/bin/killall"), NULL, NULL, (char *const *)args, NULL);
	if (result != 0) {
		NSLog(@"[JikanPreferences] Failed to respring SpringBoard: %d", result);
	}
}

@end

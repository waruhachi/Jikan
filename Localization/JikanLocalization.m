#import "JikanLocalization.h"

static NSString *const kJikanLocalizationTable = @"Localizable";

static NSBundle *JikanLocalizationBundle(void) {
	static NSBundle *cachedBundle = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSString *supportPath = jbroot(@"/Library/Tweak Support/Jikan/");
		cachedBundle = supportPath.length > 0 ? [NSBundle bundleWithPath:supportPath] : nil;
		if (!cachedBundle) cachedBundle = [NSBundle mainBundle];
	});
	return cachedBundle;
}

NSString *JikanLocalizedString(NSString *key, NSString *fallback) {
	if (key.length == 0) return fallback ?: @"";
	NSBundle *bundle = JikanLocalizationBundle();
	NSString *localized = [bundle localizedStringForKey:key value:nil table:kJikanLocalizationTable];
	if (localized.length == 0 || [localized isEqualToString:key]) {
		return fallback ?: key;
	}
	return localized;
}

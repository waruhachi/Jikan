#import "JikanAppearanceSettings.h"

NSString *const JikanPillAppearanceKey = @"pillAppearance";
NSString *const JikanPillAppearanceClassic = @"classic";
NSString *const JikanPillAppearanceProgressRing = @"progressRing";

NSString *JikanPillAppearance(NSUserDefaults *preferences) {
	id value = [preferences objectForKey:JikanPillAppearanceKey];
	return [value isKindOfClass:NSString.class] && [value isEqualToString:JikanPillAppearanceProgressRing]
		? JikanPillAppearanceProgressRing
		: JikanPillAppearanceClassic;
}

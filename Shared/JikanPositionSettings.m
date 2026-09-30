#import "JikanPositionSettings.h"

NSString *const JikanPillPortraitXPercentKey = @"pillPosXPortraitPercent";
NSString *const JikanPillPortraitYPercentKey = @"pillPosYPortraitPercent";
NSString *const JikanPillLandscapeXPercentKey = @"pillPosXLandscapePercent";
NSString *const JikanPillLandscapeYPercentKey = @"pillPosYLandscapePercent";
NSString *const JikanPreviewXAxisLockKey = @"lockPreviewXAxis";
NSString *const JikanPreviewYAxisLockKey = @"lockPreviewYAxis";

static NSArray<NSString *> *JikanPositionKeys(BOOL landscape) {
	return landscape ? @[@"platterPosXNormLandscape", @"platterPosYNormLandscape", JikanPillLandscapeXPercentKey, JikanPillLandscapeYPercentKey] : @[@"platterPosXNorm", @"platterPosYNorm", JikanPillPortraitXPercentKey, JikanPillPortraitYPercentKey];
}

static double JikanClampPosition(double value, double fallback) {
	return isfinite(value) ? MAX(0.05, MIN(0.95, value)) : fallback;
}

static double JikanPercentToNorm(id value, double fallback) {
	double percent = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback * 100.0;
	if (!isfinite(percent)) percent = fallback * 100.0;
	return MAX(0.0, MIN(100.0, percent)) / 100.0;
}

JikanPillPosition JikanReadPillPosition(NSUserDefaults *preferences, BOOL landscape) {
	NSArray<NSString *> *keys = JikanPositionKeys(landscape);
	BOOL custom = [preferences objectForKey:keys[0]] != nil && [preferences objectForKey:keys[1]] != nil;
	double x = JikanClampPosition(custom ? [preferences doubleForKey:keys[0]] : 0.5, 0.5);
	double y = JikanClampPosition(custom ? [preferences doubleForKey:keys[1]] : 0.84, 0.84);
	id percentX = [preferences objectForKey:keys[2]];
	id percentY = [preferences objectForKey:keys[3]];
	if (percentX || percentY) {
		x = JikanClampPosition(JikanPercentToNorm(percentX, x), 0.5);
		y = JikanClampPosition(JikanPercentToNorm(percentY, y), 0.84);
		custom = YES;
	}
	return (JikanPillPosition){x, y, custom};
}

void JikanSavePillPosition(NSUserDefaults *preferences, BOOL landscape, double x, double y) {
	NSArray<NSString *> *keys = JikanPositionKeys(landscape);
	[preferences setDouble:x forKey:keys[0]];
	[preferences setDouble:y forKey:keys[1]];
	[preferences setDouble:x * 100.0 forKey:keys[2]];
	[preferences setDouble:y * 100.0 forKey:keys[3]];
}

void JikanResetPillPosition(NSUserDefaults *preferences) {
	for (NSString *key in JikanPositionKeys(NO)) [preferences removeObjectForKey:key];
	for (NSString *key in JikanPositionKeys(YES)) [preferences removeObjectForKey:key];
	[preferences removeObjectForKey:JikanPreviewXAxisLockKey];
	[preferences removeObjectForKey:JikanPreviewYAxisLockKey];
}

NSDictionary<NSString *, NSNumber *> *JikanPillPositionSliderDefaults(void) {
	return @{JikanPillPortraitXPercentKey: @50,
		JikanPillPortraitYPercentKey: @84,
		JikanPillLandscapeXPercentKey: @50,
		JikanPillLandscapeYPercentKey: @84};
}

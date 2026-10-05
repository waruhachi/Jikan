#import "JikanEstimateFormatting.h"

NSString *JikanCompactEstimateForSeconds(double seconds, NSInteger targetPercent) {
	if (!isfinite(seconds) || seconds <= 0 || seconds > INT_MAX || targetPercent < 1 || targetPercent > 100) return nil;
	NSInteger totalMinutes = (NSInteger)llround(seconds / 60.0);
	NSInteger hours = totalMinutes / 60;
	NSInteger minutes = totalMinutes % 60;
	NSString *duration;
	if (hours && minutes) {
		duration = [NSString stringWithFormat:JikanLocalizedString(@"jikan.inline.format.hr_min", @"%ldh %ldm"), (long)hours, (long)minutes];
	} else if (hours) {
		duration = [NSString stringWithFormat:JikanLocalizedString(@"jikan.inline.format.hr", @"%ldh"), (long)hours];
	} else if (minutes) {
		duration = [NSString stringWithFormat:JikanLocalizedString(@"jikan.inline.format.min", @"%ldm"), (long)minutes];
	} else {
		duration = JikanLocalizedString(@"jikan.inline.format.lt1min", @"<1m");
	}
	return [NSString stringWithFormat:JikanLocalizedString(@"jikan.inline.format.to_target", @"%@ to %ld%%"), duration, (long)targetPercent];
}

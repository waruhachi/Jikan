#import "JikanStackSummaryCell.h"

@implementation JikanStackSummaryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
#pragma unused(style)
	self = [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier specifier:specifier];
	if (!self) return nil;
	[self _updateSummary];
	return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	[self _updateSummary];
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (self.window) [self _updateSummary];
}

- (void)_updateSummary {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	NSArray<NSString *> *items = JikanStackItems(prefs);
	NSDictionary<NSString *, NSString *> *names = @{
		JikanStackEstimate: JikanLocalizedString(@"jikan.stack.item.estimate", @"Estimated Time"),
		JikanStackWattage: JikanLocalizedString(@"jikan.stack.item.wattage", @"Wattage"),
		JikanStackTemperature: JikanLocalizedString(@"jikan.stack.item.temperature", @"Temperature"),
		JikanStackVoltage: JikanLocalizedString(@"jikan.stack.item.voltage", @"Voltage")
	};
	NSMutableArray<NSString *> *readings = [NSMutableArray arrayWithCapacity:items.count];
	for (NSString *item in items) [readings addObject:names[item]];
	NSString *allReadings = [readings componentsJoinedByString:@", "];
	// Estimated Time is always included; name it only when no optional readings are active.
	if (readings.count > 1) [readings removeObjectAtIndex:0];

	UIListContentConfiguration *content = [self defaultContentConfiguration];
	content.text = JikanLocalizedString(@"jikan.prefs.row.stack", @"Stack");
	content.secondaryText = [readings componentsJoinedByString:@", "];
	// UIKit moves the summary below the title when the side-by-side layout cannot fit.
	content.prefersSideBySideTextAndSecondaryText = YES;
	content.textProperties.numberOfLines = 0;
	content.secondaryTextProperties.numberOfLines = 0;
	content.secondaryTextProperties.lineBreakMode = NSLineBreakByWordWrapping;
	content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
	content.textProperties.adjustsFontForContentSizeCategory = YES;
	content.secondaryTextProperties.adjustsFontForContentSizeCategory = YES;
	self.contentConfiguration = content;
	self.accessibilityLabel = content.text;
	self.accessibilityValue = allReadings;
}

@end

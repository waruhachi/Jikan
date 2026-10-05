#import "JikanPreferencesPresentation.h"

@implementation JikanPreferencesPresentation

+ (NSString *)_localizedPreferenceText:(NSString *)text {
	if (![text isKindOfClass:[NSString class]] || text.length == 0) return text;
	static NSDictionary<NSString *, NSString *> *keyMap;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		keyMap = @{
			@"Enable": @"jikan.prefs.row.enable",
			@"Pill Preview": @"jikan.prefs.section.pill_preview",
			@"Lock X Axis": @"jikan.prefs.row.lock_x_axis",
			@"Lock Y Axis": @"jikan.prefs.row.lock_y_axis",
			@"Show Preview": @"jikan.prefs.row.show_preview",
			@"Pill Display": @"jikan.prefs.section.pill_display",
			@"Pill Style": @"jikan.prefs.section.pill_style",
			@"Show after full charge": @"jikan.prefs.row.show_after_full_charge",
			@"Stack": @"jikan.prefs.row.stack",
			@"Tap and Hold the Slider Knob to Edit": @"jikan.prefs.footer.slider_hint",
			@"Opacity": @"jikan.prefs.row.opacity",
			@"Pill Background Opacity (%)": @"jikan.prefs.row.pill_background_opacity",
			@"Pill Position": @"jikan.prefs.section.pill_position",
			@"Portrait": @"jikan.prefs.row.portrait",
			@"Portrait X": @"jikan.prefs.row.portrait_x",
			@"Portrait Y": @"jikan.prefs.row.portrait_y",
			@"Landscape": @"jikan.prefs.row.landscape",
			@"Landscape X": @"jikan.prefs.row.landscape_x",
			@"Landscape Y": @"jikan.prefs.row.landscape_y",
			@"Miscellaneous": @"jikan.prefs.section.miscellaneous",
			@"Time Estimate": @"jikan.prefs.section.battery_estimate",
			@"Replace Pill with Date Estimate": @"jikan.prefs.row.estimate_beside_date",
			@"Algorithm": @"jikan.prefs.row.algorithm",
			@"Estimate Target": @"jikan.prefs.row.estimate_target",
			@"Estimate Target (%)": @"jikan.prefs.row.estimate_target_percent",
			@"Sync with ChargeLimiter": @"jikan.prefs.row.sync_with_chargelimiter",
			@"Hide Quick Action Buttons": @"jikan.prefs.row.hide_quick_action_buttons",
			@"Only While Charging": @"jikan.prefs.row.only_while_charging",
			@"Reset": @"jikan.prefs.section.reset",
			@"Reset Pill Position": @"jikan.prefs.row.reset_pill_position",
			@"Reset To Defaults": @"jikan.prefs.row.reset_to_defaults",
			@"Reset Preferences": @"jikan.prefs.alert.reset_preferences.title",
			@"Reset all Jikan settings to defaults?": @"jikan.prefs.alert.reset_preferences.prompt",
			@"Reset portrait/landscape pill position and axis locks?": @"jikan.prefs.alert.reset_pill_position.prompt",
			@"Cancel": @"jikan.common.action.cancel"
		};
	});

	NSString *key = keyMap[text];
	if (key.length == 0) return text;
	return JikanLocalizedString(key, text);
}

+ (void)localizeSpecifiers:(NSArray<PSSpecifier *> *)specifiers {
	for (PSSpecifier *specifier in specifiers) {
		NSString *label = [specifier propertyForKey:@"label"];
		if ([label isKindOfClass:[NSString class]] && label.length > 0) {
			NSString *localized = [self _localizedPreferenceText:label];
			specifier.name = localized;
			[specifier setProperty:localized forKey:@"label"];
		}

		NSString *footerText = [specifier propertyForKey:@"footerText"];
		if ([footerText isKindOfClass:[NSString class]] && footerText.length > 0) {
			[specifier setProperty:[self _localizedPreferenceText:footerText] forKey:@"footerText"];
		}

		NSDictionary *confirmation = [specifier propertyForKey:@"confirmation"];
		if ([confirmation isKindOfClass:[NSDictionary class]]) {
			NSMutableDictionary *localizedConfirmation = [confirmation mutableCopy];
			for (NSString *key in @[@"title", @"prompt", @"cancelTitle"]) {
				NSString *value = confirmation[key];
				if ([value isKindOfClass:[NSString class]] && value.length > 0) {
					localizedConfirmation[key] = [self _localizedPreferenceText:value];
				}
			}
			[specifier setProperty:localizedConfirmation forKey:@"confirmation"];
		}
	}
}

+ (UIView *)legendFooterView {
	UIView *container = [[UIView alloc] initWithFrame:CGRectZero];

	UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 4.0;
	stack.alignment = UIStackViewAlignmentLeading;
	[container addSubview:stack];

	NSArray<NSDictionary *> *legend = @[
		@{@"color": UIColor.systemYellowColor, @"text": JikanLocalizedString(@"jikan.prefs.legend.slow_charging", @"Slow charging")}
	];

	for (NSDictionary *entry in legend) {
		UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero];
		row.axis = UILayoutConstraintAxisHorizontal;
		row.spacing = 6.0;
		row.alignment = UIStackViewAlignmentCenter;

		UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold];
		UIImage *bolt = [UIImage systemImageNamed:@"bolt.fill" withConfiguration:cfg];
		UIImageView *icon = [[UIImageView alloc] initWithImage:bolt];
		icon.tintColor = entry[@"color"];
		icon.contentMode = UIViewContentModeScaleAspectFit;
		[icon.widthAnchor constraintEqualToConstant:12.0].active = YES;
		[icon.heightAnchor constraintEqualToConstant:12.0].active = YES;

		UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
		label.text = entry[@"text"];
		label.textColor = [UIColor secondaryLabelColor];
		label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];

		[row addArrangedSubview:icon];
		[row addArrangedSubview:label];
		[stack addArrangedSubview:row];
	}

	[NSLayoutConstraint activateConstraints:@[
		[stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16.0],
		[stack.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-16.0],
		[stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:2.0],
		[stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8.0],
	]];

	return container;
}

+ (UIImage *)_axisIconForSymbol:(NSString *)symbolName {
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightRegular];
	UIImage *img = [UIImage systemImageNamed:symbolName withConfiguration:cfg];
	if (!img) return nil;
	return [img imageWithTintColor:[UIColor systemBlueColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (void)configureAxisSliderLeftImagesForController:(PSListController *)controller {
	NSArray<NSDictionary *> *map = @[
		@{@"id": @"pillPosXPortraitSlider", @"symbol": @"arrow.left.and.right"},
		@{@"id": @"pillPosYPortraitSlider", @"symbol": @"arrow.up.and.down"},
		@{@"id": @"pillPosXLandscapeSlider", @"symbol": @"arrow.left.and.right"},
		@{@"id": @"pillPosYLandscapeSlider", @"symbol": @"arrow.up.and.down"}
	];
	for (NSDictionary *entry in map) {
		PSSpecifier *spec = [controller specifierForID:entry[@"id"]];
		if (!spec) continue;
		UIImage *icon = [self _axisIconForSymbol:entry[@"symbol"]];
		if (!icon) continue;
		[spec setProperty:icon forKey:@"leftImage"];
	}
}

+ (BOOL)isSpacerHeaderTitle:(NSString *)title {
	if (![title isKindOfClass:[NSString class]]) return NO;
	NSString *trimmed = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return trimmed.length == 0;
}

+ (UIView *)spacerHeaderView {
	UIView *spacer = [[UIView alloc] initWithFrame:CGRectZero];
	spacer.backgroundColor = UIColor.clearColor;
	return spacer;
}

@end

#include "JikanRootListController.h"

@implementation JikanRootListController

static NSString *const kJikanPrefsSuite = @"moe.waru.jikan.preferences";
static NSString *const kJikanPrefsReloadNotification = @"moe.waru.jikan.preferences.reload";
static NSString *const kPillBackgroundOpacityKey = @"pillBackgroundOpacityPercent";

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}

	return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self _installOpacityValueTapIfNeeded];
}

- (void)reloadSpecifiers {
	[super reloadSpecifiers];
	[self _installOpacityValueTapIfNeeded];
}

- (void)_installOpacityValueTapIfNeeded {
	if (!self.table) return;

	PSSpecifier *opacitySpecifier = [self specifierForID:@"pillBackgroundOpacitySlider"];
	if (!opacitySpecifier) return;
	NSInteger row = [self indexOfSpecifier:opacitySpecifier];
	if (row == NSNotFound) return;

	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
	UITableViewCell *cell = [self.table cellForRowAtIndexPath:indexPath];
	if (!cell) return;

	for (UIView *subview in cell.contentView.subviews) {
		if (![subview isKindOfClass:[UILabel class]]) continue;
		UILabel *label = (UILabel *)subview;
		if (!label.userInteractionEnabled) {
			label.userInteractionEnabled = YES;
		}
		BOOL isLikelyValueLabel = (label.textAlignment == NSTextAlignmentRight || CGRectGetWidth(label.frame) <= 72.0);
		if (!isLikelyValueLabel) continue;

		BOOL already = NO;
		for (UIGestureRecognizer *gr in label.gestureRecognizers) {
			if ([gr isKindOfClass:[UITapGestureRecognizer class]] && gr.view == label) {
				already = YES;
				break;
			}
		}
		if (!already) {
			UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openPillBackgroundOpacityEditor)];
			tap.numberOfTapsRequired = 2;
			[label addGestureRecognizer:tap];
		}
	}
}

- (void)openPillBackgroundOpacityEditor {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	double currentValue = [prefs objectForKey:kPillBackgroundOpacityKey] ? [prefs doubleForKey:kPillBackgroundOpacityKey] : 100.0;
	if (!isfinite(currentValue)) currentValue = 100.0;
	currentValue = MAX(0.0, MIN(100.0, currentValue));

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Pill Background Opacity" message:@"Enter a value from 0 to 100" preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
		textField.keyboardType = UIKeyboardTypeDecimalPad;
		textField.placeholder = @"0-100";
		textField.text = [NSString stringWithFormat:@"%.1f", currentValue];
	}];

	__weak __typeof(self) weakSelf = self;
	UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
		__unused UIAlertAction *unusedAction = action;
		UITextField *tf = alert.textFields.firstObject;
		double v = tf.text.doubleValue;
		if (!isfinite(v)) v = currentValue;
		v = MAX(0.0, MIN(100.0, v));

		[prefs setDouble:v forKey:kPillBackgroundOpacityKey];
		[prefs synchronize];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);

		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf reloadSpecifiers];
		});
	}];

	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:save];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)resetPreferences {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kJikanPrefsSuite];
	if (!prefs) return;

	NSArray<NSString *> *keys = @[
		@"enabled",
		@"platterYOffset",
		@"platterPosXNorm",
		@"platterPosYNorm",
		@"platterPosXNormLandscape",
		@"platterPosYNormLandscape",
		@"hideQuickActionButtons",
		@"showRemainingBatteryTime",
		@"autoResizeRemainingBatteryTime",
		@"tapToShowWattage",
		@"previewPlatter",
		@"showAfterFullCharge",
		@"lockPreviewXAxis",
		@"lockPreviewYAxis"
	];

	for (NSString *key in keys) {
		[prefs removeObjectForKey:key];
	}

	[prefs synchronize];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kJikanPrefsReloadNotification, NULL, NULL, YES);

	dispatch_async(dispatch_get_main_queue(), ^{
		[self reloadSpecifiers];
	});
}

@end

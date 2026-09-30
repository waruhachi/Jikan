#import "JikanSliderEditor.h"

static NSString *const kBatteryEstimateTargetKey = @"batteryEstimateTargetPercent";
static const void *kJikanSliderEditorGestureKey = &kJikanSliderEditorGestureKey;
static const void *kJikanSliderEditorConfigKey = &kJikanSliderEditorConfigKey;
static const void *kJikanSliderThumbOnlyKey = &kJikanSliderThumbOnlyKey;

@interface UISlider (JikanThumbOnlyTracking)
- (BOOL)jikan_beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
@end

@implementation UISlider (JikanThumbOnlyTracking)

- (BOOL)jikan_beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
	if ([objc_getAssociatedObject(self, kJikanSliderThumbOnlyKey) boolValue]) {
		CGPoint point = [touch locationInView:self];
		CGRect trackRect = [self trackRectForBounds:self.bounds];
		CGRect thumbRect = [self thumbRectForBounds:self.bounds trackRect:trackRect value:self.value];
		if (!CGRectContainsPoint(CGRectInset(thumbRect, -12.0, -12.0), point)) {
			return NO;
		}
	}
	return [self jikan_beginTrackingWithTouch:touch withEvent:event];
}

@end

static void JikanInstallSliderTrackingGuardIfNeeded(void) {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		Method original = class_getInstanceMethod([UISlider class], @selector(beginTrackingWithTouch:withEvent:));
		Method replacement = class_getInstanceMethod([UISlider class], @selector(jikan_beginTrackingWithTouch:withEvent:));
		if (original && replacement) method_exchangeImplementations(original, replacement);
	});
}

@interface JikanSliderEditor ()
@property (nonatomic, weak) PSListController *controller;
@property (nonatomic, copy) BOOL (^canEdit)(void);
@property (nonatomic, copy) void (^willEdit)(void);
@property (nonatomic, copy) void (^didEdit)(void);
@property (nonatomic, weak) UIAlertController *alert;
@property (nonatomic, weak) UIAlertAction *saveAction;
@property (nonatomic, strong) JikanSliderDescriptor *descriptor;
@property (nonatomic, strong) NSLocale *locale;
@end

@implementation JikanSliderEditor

- (instancetype)initWithController:(PSListController *)controller canEdit:(BOOL (^)(void))canEdit willEdit:(void (^)(void))willEdit didEdit:(void (^)(void))didEdit {
	if ((self = [super init])) {
		_controller = controller;
		_canEdit = [canEdit copy];
		_willEdit = [willEdit copy];
		_didEdit = [didEdit copy];
		JikanInstallSliderTrackingGuardIfNeeded();
	}
	return self;
}

- (UISlider *)_firstSliderInView:(UIView *)view {
	if ([view isKindOfClass:[UISlider class]]) return (UISlider *)view;
	for (UIView *subview in view.subviews) {
		UISlider *slider = [self _firstSliderInView:subview];
		if (slider) return slider;
	}
	return nil;
}

- (void)configureCell:(UITableViewCell *)cell specifier:(PSSpecifier *)specifier {
	UISlider *slider = [self _firstSliderInView:cell.contentView];
	if (!slider) return;
	JikanSliderDescriptor *config = nil;
	for (JikanSliderDescriptor *candidate in JikanEditableSliders()) {
		if ([candidate.identifier isEqual:[specifier propertyForKey:PSIDKey]]) {
			config = candidate;
			break;
		}
	}
	objc_setAssociatedObject(slider, kJikanSliderEditorConfigKey, config, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(slider, kJikanSliderThumbOnlyKey, @(config != nil), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	if (!config) return;
	UILongPressGestureRecognizer *hold = objc_getAssociatedObject(slider, kJikanSliderEditorGestureKey);
	if (hold) {
		[hold removeTarget:nil action:NULL];
		[hold addTarget:self action:@selector(_handleSliderKnobHold:)];
	} else {
		hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_handleSliderKnobHold:)];
		hold.minimumPressDuration = 0.35;
		hold.cancelsTouchesInView = NO;
		[slider addGestureRecognizer:hold];
		objc_setAssociatedObject(slider, kJikanSliderEditorGestureKey, hold, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
}

- (void)_handleSliderKnobHold:(UILongPressGestureRecognizer *)gesture {
	if (gesture.state != UIGestureRecognizerStateBegan) return;
	if (![gesture.view isKindOfClass:[UISlider class]]) return;

	UISlider *slider = (UISlider *)gesture.view;
	CGRect trackRect = [slider trackRectForBounds:slider.bounds];
	CGRect thumbRect = [slider thumbRectForBounds:slider.bounds trackRect:trackRect value:slider.value];
	CGPoint touch = [gesture locationInView:slider];
	if (!CGRectContainsPoint(CGRectInset(thumbRect, -12.0, -12.0), touch)) return;

	JikanSliderDescriptor *config = objc_getAssociatedObject(slider, kJikanSliderEditorConfigKey);
	if (![config isKindOfClass:JikanSliderDescriptor.class]) return;
	[self _presentSliderEditorWithConfig:config fallbackValue:slider.value];
}

- (void)dismiss {
	UIAlertController *alert = self.alert;
	self.alert = nil;
	self.saveAction = nil;
	self.descriptor = nil;
	self.locale = nil;
	if (alert) [alert dismissViewControllerAnimated:NO completion:nil];
}

- (BOOL)_sliderEditorValue:(double *)value {
	NSString *text = self.alert.textFields.firstObject.text;
	double parsed = 0;
	if (!JikanParseNumber(text, self.locale, &parsed)) return NO;
	if (parsed < self.descriptor.minimum || parsed > self.descriptor.maximum) return NO;
	if (value) *value = parsed;
	return YES;
}

- (void)_sliderEditorTextChanged:(UITextField *)field {
#pragma unused(field)
	BOOL valid = [self _sliderEditorValue:NULL];
	self.saveAction.enabled = valid;
	NSString *format = valid ? JikanLocalizedString(@"jikan.prefs.alert.slider_range.message", @"Enter a value from %.0f to %.0f") : JikanLocalizedString(@"jikan.prefs.alert.slider_invalid.message", @"Enter a valid number from %.0f to %.0f.");
	self.alert.message = [NSString stringWithFormat:format, self.descriptor.minimum, self.descriptor.maximum];
}

- (void)_presentSliderEditorWithConfig:(JikanSliderDescriptor *)config fallbackValue:(double)fallback {
	NSString *prefsKey = config.preferenceKey;
	if ([prefsKey isEqualToString:kBatteryEstimateTargetKey]) {
		NSUserDefaults *currentPrefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
		if ([JikanEstimateSource(currentPrefs) isEqualToString:@"apple"]) return;
	}
	NSString *title = JikanLocalizedString(config.titleKey, config.fallbackTitle);
	if (!JikanSliderDefaults()[prefsKey] || !title.length || !self.controller || !self.canEdit() || self.controller.presentedViewController) return;
	self.willEdit();
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	NSNumber *currentValue = JikanNormalizedSliderValue([prefs objectForKey:prefsKey] ?: @(fallback), prefsKey);
	NSLocale *locale = NSLocale.currentLocale;
	NSNumberFormatter *formatter = [NSNumberFormatter new];
	formatter.locale = locale;
	formatter.numberStyle = NSNumberFormatterDecimalStyle;
	formatter.usesGroupingSeparator = NO;
	formatter.maximumFractionDigits = 0;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.keyboardType = UIKeyboardTypeDecimalPad;
		textField.text = [formatter stringFromNumber:currentValue];
		[textField addTarget:self action:@selector(_sliderEditorTextChanged:) forControlEvents:UIControlEventEditingChanged];
	}];
	self.alert = alert;
	self.descriptor = config;
	self.locale = locale;
	__weak typeof(self) weakSelf = self;
	__weak UIAlertController *weakAlert = alert;
	UIAlertAction *save = [UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.save", @"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || !self.controller || !self.canEdit() || self.alert != weakAlert) return;
		double value = 0;
		if (![self _sliderEditorValue:&value]) return;
		PSSpecifier *specifier = [self.controller specifierForID:config.identifier];
		if (!specifier) return;
		[self.controller setPreferenceValue:JikanNormalizedSliderValue(@(value), prefsKey) specifier:specifier];
		self.alert = nil;
		self.saveAction = nil;
		self.descriptor = nil;
		self.locale = nil;
		self.didEdit();
	}];
	[alert addAction:[UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
		if (weakSelf.alert == weakAlert) {
			weakSelf.alert = nil;
			weakSelf.saveAction = nil;
			weakSelf.descriptor = nil;
			weakSelf.locale = nil;
		}
	}]];
	[alert addAction:save];
	self.saveAction = save;
	[self _sliderEditorTextChanged:alert.textFields.firstObject];
	[self.controller presentViewController:alert animated:YES completion:nil];
}

@end

#import <Preferences/PSSpecifier.h>
#import <math.h>

#import "../../Shared/JikanEstimateSettings.h"
#import "../Controllers/JikanSliderSettings.h"
#import "JikanSliderCell.h"

@interface PSControlTableCell (JikanSliderValue)
- (UILabel *)valueLabel;
- (void)setValue:(id)value;
- (UIControl *)newControl;
@end

@interface PSSegmentableSlider : UISlider
- (NSInteger)segmentCount;
- (void)setSnapsToSegment:(BOOL)snaps;
- (void)setLocksToSegment:(BOOL)locks;
@end

// Runtime declarations keep the iOS 26 API optional with older build SDKs.
@interface UISlider (JikanTrackConfiguration)
@property (nonatomic, copy) id trackConfiguration;
@end

@interface NSObject (JikanSliderTicks)
+ (instancetype)configurationWithNumberOfTicks:(NSInteger)count;
+ (instancetype)configurationWithTicks:(NSArray *)ticks;
- (void)setAllowsTickValuesOnly:(BOOL)allowed;
@end

// Preferences configures these segment properties on the control it creates.
@interface JikanSliderControl : UISlider
@property (nonatomic) NSInteger segmentCount;
@property (nonatomic, getter=isSegmented) BOOL segmented;
@property (nonatomic) BOOL locksToSegment;
@property (nonatomic) BOOL snapsToSegment;
@end

@interface JikanLegacySliderControl : PSSegmentableSlider
@end

@implementation JikanSliderControl

- (BOOL)_adjustValueBySegment:(NSInteger)direction {
	NSInteger count = [self segmentCount];
	if (count <= 0 || self.maximumValue <= self.minimumValue) return NO;
	float step = (self.maximumValue - self.minimumValue) / count;
	float index = roundf((self.value - self.minimumValue) / step);
	float value = fmaxf(self.minimumValue, fminf(self.maximumValue, self.minimumValue + (index + direction) * step));
	if (value != self.value) {
		self.value = value;
		[self sendActionsForControlEvents:UIControlEventValueChanged];
	}
	return YES;
}

- (void)accessibilityIncrement {
	if (![self _adjustValueBySegment:1]) [super accessibilityIncrement];
}

- (void)accessibilityDecrement {
	if (![self _adjustValueBySegment:-1]) [super accessibilityDecrement];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (@available(iOS 26.0, *)) {
		// UIKit has no public setting to hide discrete tick markers.
		// Match only the verified marker row; leave unfamiliar hierarchies intact.
		NSInteger tickCount = self.segmentCount + 1;
		for (UIView *visual in self.subviews) {
			if (![NSStringFromClass(visual.class) isEqualToString:@"UIKit._UISliderGlassVisualElement"]) continue;
			for (UIView *row in visual.subviews) {
				if (row.subviews.count != tickCount || tickCount < 2) continue;
				BOOL markersOnly = YES;
				for (UIView *marker in row.subviews) {
					CGSize size = marker.bounds.size;
					if (marker.class != UIView.class || size.width <= 0 || size.width > 4 || size.height <= 0 || size.height > 4 || marker.isAccessibilityElement) {
						markersOnly = NO;
						break;
					}
				}
				if (markersOnly) row.hidden = YES;
			}
		}
	}
}

@end

@implementation JikanLegacySliderControl

- (BOOL)_adjustValueBySegment:(NSInteger)direction {
	NSInteger count = [self segmentCount];
	if (count <= 0 || self.maximumValue <= self.minimumValue) return NO;
	float step = (self.maximumValue - self.minimumValue) / count;
	float index = roundf((self.value - self.minimumValue) / step);
	float value = fmaxf(self.minimumValue, fminf(self.maximumValue, self.minimumValue + (index + direction) * step));
	if (value != self.value) {
		self.value = value;
		[self sendActionsForControlEvents:UIControlEventValueChanged];
	}
	return YES;
}

- (void)accessibilityIncrement {
	if (![self _adjustValueBySegment:1]) [super accessibilityIncrement];
}

- (void)accessibilityDecrement {
	if (![self _adjustValueBySegment:-1]) [super accessibilityDecrement];
}

- (void)drawRect:(CGRect)rect {
	// UIKit renders the track and thumb; omit Preferences' extra markers.
}

@end

@interface JikanSliderCell ()
@property (nonatomic, strong) UILabel *jikanValueLabel;
@property (nonatomic, strong) NSNumberFormatter *jikanValueFormatter;
@property (nonatomic, weak) UISlider *jikanConfiguredSlider;
@property (nonatomic) NSInteger jikanSegmentCount;
@property (nonatomic, weak) UISlider *jikanLayoutSlider;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *jikanLayoutConstraints;
@property (nonatomic, strong) NSLayoutConstraint *jikanValueWidthConstraint;
@end

@implementation JikanSliderCell

- (void)_configureSliderTrack:(UISlider *)slider {
	[self _configureSliderTrack:slider specifier:self.specifier];
}

- (void)_configureSliderTrack:(UISlider *)slider specifier:(PSSpecifier *)specifier {
	slider.continuous = [[specifier propertyForKey:@"isContinuous"] boolValue];
	if (@available(iOS 26.0, *)) {
		Class configurationClass = NSClassFromString(@"UISliderTrackConfiguration");
		if (![slider respondsToSelector:@selector(setTrackConfiguration:)] ||
			![configurationClass respondsToSelector:@selector(configurationWithNumberOfTicks:)] ||
			![configurationClass respondsToSelector:@selector(configurationWithTicks:)]) return;
		BOOL appleTarget = [[specifier propertyForKey:@"key"] isEqualToString:JikanEstimateAppleTargetKey];
		NSInteger count = appleTarget ? [[specifier propertyForKey:@"segmentCount"] integerValue] : 0;
		if (self.jikanConfiguredSlider == slider && self.jikanSegmentCount == count) return;
		// An explicit continuous configuration avoids iOS 26's stale value read
		// when a reused discrete slider's configuration is set to nil.
		id configuration = count > 0 ? [configurationClass configurationWithNumberOfTicks:count + 1] : [configurationClass configurationWithTicks:@[]];
		[configuration setAllowsTickValuesOnly:count > 0];
		slider.trackConfiguration = configuration;
		self.jikanSegmentCount = count;
		self.jikanConfiguredSlider = slider;
	}
}

- (UIControl *)newControl {
	UISlider *slider;
	if (@available(iOS 26.0, *)) {
		// Use UIKit directly so Preferences cannot replace discrete tracking.
		slider = [[JikanSliderControl alloc] initWithFrame:CGRectZero];
	} else {
		JikanLegacySliderControl *legacy = [[JikanLegacySliderControl alloc] initWithFrame:CGRectZero];
		[legacy setSnapsToSegment:YES];
		[legacy setLocksToSegment:YES];
		slider = legacy;
	}
	[slider addTarget:self action:@selector(controlChanged:) forControlEvents:UIControlEventValueChanged];
	return slider;
}

- (void)_updateValueLabel {
	if (!self.jikanValueLabel || ![self.control isKindOfClass:UISlider.class]) return;
	UISlider *slider = (UISlider *)self.control;
	NSString *key = [self.specifier propertyForKey:@"key"];
	NSNumber *value = [key isEqualToString:JikanEstimateAppleTargetKey] ? JikanAppleSliderTargetFromValue(@(slider.value)) : JikanNormalizedSliderValue(@(slider.value), key);
	if (!value) return;
	self.jikanValueFormatter.locale = NSLocale.currentLocale;
	self.jikanValueLabel.text = [self.jikanValueFormatter stringFromNumber:value];
}

- (void)setValue:(id)value {
	[super setValue:value];
	if ([self.control isKindOfClass:UISlider.class]) [self _configureSliderTrack:(UISlider *)self.control];
	[self _updateValueLabel];
}

- (void)controlChanged:(UIControl *)control {
	[super controlChanged:control];
	if ([control isKindOfClass:UISlider.class]) [self _configureSliderTrack:(UISlider *)control];
	[self _updateValueLabel];
	[self setNeedsLayout];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	// Replace the previous row's stops before Preferences loads the new value.
	if ([self.control isKindOfClass:UISlider.class]) [self _configureSliderTrack:(UISlider *)self.control specifier:specifier];
	[super refreshCellContentsWithSpecifier:specifier];
	if ([self.control isKindOfClass:UISlider.class]) [self _configureSliderTrack:(UISlider *)self.control];
	[self _updateValueLabel];
	[self setNeedsLayout];
}

- (void)prepareForReuse {
	self.jikanConfiguredSlider = nil;
	self.jikanSegmentCount = 0;
	[super prepareForReuse];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	[self _layoutValueLabel];
}

- (void)_layoutValueLabel {
	if (![self.control isKindOfClass:UISlider.class]) return;
	UISlider *slider = (UISlider *)self.control;
	[self _configureSliderTrack:slider];
	[super valueLabel].hidden = YES;
	if (!self.jikanValueLabel) {
		UILabel *label = [UILabel new];
		label.translatesAutoresizingMaskIntoConstraints = NO;
		label.textColor = UIColor.secondaryLabelColor;
		label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
		label.adjustsFontForContentSizeCategory = YES;
		label.isAccessibilityElement = NO;	// The native slider already announces its value.
		[self.contentView addSubview:label];
		self.jikanValueLabel = label;
		self.jikanValueFormatter = [NSNumberFormatter new];
		self.jikanValueFormatter.numberStyle = NSNumberFormatterDecimalStyle;
		self.jikanValueFormatter.usesGroupingSeparator = NO;
		self.jikanValueFormatter.maximumFractionDigits = 0;
	}
	UILabel *label = self.jikanValueLabel;
	label.textAlignment = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft ? NSTextAlignmentLeft : NSTextAlignmentRight;
	[self _updateValueLabel];
	if (self.jikanLayoutSlider != slider) {
		[NSLayoutConstraint deactivateConstraints:self.jikanLayoutConstraints];
		slider.translatesAutoresizingMaskIntoConstraints = NO;
		UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
		self.jikanValueWidthConstraint = [label.widthAnchor constraintEqualToConstant:0];
		self.jikanLayoutConstraints = @[
			[slider.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
			[slider.trailingAnchor constraintEqualToAnchor:label.leadingAnchor constant:-12],
			[slider.centerYAnchor constraintEqualToAnchor:margins.centerYAnchor],
			[label.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
			[label.centerYAnchor constraintEqualToAnchor:slider.centerYAnchor],
			self.jikanValueWidthConstraint,
		];
		self.jikanLayoutSlider = slider;
	}
	// Older Preferences uses frames; newer versions install their own constraints.
	// Own only the slider's horizontal geometry so the thumb cannot reach the label.
	for (UIView *view in @[self, self.contentView, slider]) {
		for (NSLayoutConstraint *constraint in view.constraints) {
			if ([self.jikanLayoutConstraints containsObject:constraint]) continue;
			NSLayoutAttribute attribute = constraint.firstItem == slider ? constraint.firstAttribute : (constraint.secondItem == slider ? constraint.secondAttribute : NSLayoutAttributeNotAnAttribute);
			if (attribute == NSLayoutAttributeLeading || attribute == NSLayoutAttributeTrailing || attribute == NSLayoutAttributeLeft || attribute == NSLayoutAttributeRight || attribute == NSLayoutAttributeWidth || attribute == NSLayoutAttributeCenterX) {
				constraint.active = NO;
			}
		}
	}
	NSString *maximum = [self.jikanValueFormatter stringFromNumber:@(slider.maximumValue)];
	CGFloat width = MAX([maximum sizeWithAttributes:@{NSFontAttributeName: label.font}].width, label.intrinsicContentSize.width);
	self.jikanValueWidthConstraint.constant = ceil(width);
	[NSLayoutConstraint activateConstraints:self.jikanLayoutConstraints];
	[self.contentView layoutIfNeeded];
}

@end

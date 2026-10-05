#import "JikanInlineWidgetEstimate.h"

static const void *kJikanInlineWidgetEstimateKey = &kJikanInlineWidgetEstimateKey;
static const CGFloat kJikanInlineEstimateSpacing = 8.0;
static const CGFloat kJikanInlineEstimateMinimumScale = 0.8;

static id JikanWidgetObject(id object, NSString *name) {
	SEL selector = NSSelectorFromString(name);
	return [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

@interface JikanInlineWidgetEstimate ()
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic, weak) UIViewController *host;
@property (nonatomic, weak) UIView *rootView;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic) CGAffineTransform originalTransform;
@property (nonatomic) CGRect contentBounds;
@property (nonatomic) CGSize canvasSize;
@property (nonatomic) BOOL measurementPending;
@property (nonatomic) NSUInteger measurementGeneration;
@property (nonatomic) BOOL layingOut;
- (BOOL)layout;
- (void)requestMeasurement;
- (void)refreshContentBounds;
@end

static CGRect JikanNativeWidgetContentBounds(UIViewController *host) {
	id image = JikanWidgetObject(JikanWidgetObject(host, @"_staticImageSnapshotView"), @"image");
	if (![image isKindOfClass:UIImage.class]) {
		id context = JikanWidgetObject(host, @"_persistedSnapshotContext");
		id url = JikanWidgetObject(context, @"url");
		SEL decoder = NSSelectorFromString(@"_snapshotImageFromURL:");
		if ([url isKindOfClass:NSURL.class] && [host respondsToSelector:decoder]) {
			image = ((id (*)(id, SEL, id))objc_msgSend)(host, decoder, url);
		}
	}
	if (![image isKindOfClass:UIImage.class]) return CGRectNull;
	CGImageRef bitmap = ((UIImage *)image).CGImage;
	if (!bitmap || ((UIImage *)image).imageOrientation != UIImageOrientationUp) return CGRectNull;
	size_t width = CGImageGetWidth(bitmap), height = CGImageGetHeight(bitmap);
	if (!width || !height || width > 4096 || height > 512) return CGRectNull;
	uint8_t *pixels = calloc(width * height, 4);
	if (!pixels) return CGRectNull;
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef drawing = CGBitmapContextCreate(pixels, width, height, 8, width * 4, colorSpace,
		kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGColorSpaceRelease(colorSpace);
	if (!drawing) {
		free(pixels);
		return CGRectNull;
	}
	CGContextDrawImage(drawing, CGRectMake(0, 0, width, height), bitmap);
	size_t minX = width, maxX = 0;
	for (size_t y = 0; y < height; y++) {
		for (size_t x = 0; x < width; x++) {
			if (pixels[(y * width + x) * 4 + 3] > 16) {
				minX = MIN(minX, x);
				maxX = MAX(maxX, x + 1);
			}
		}
	}
	CGContextRelease(drawing);
	free(pixels);
	CGSize size = ((UIImage *)image).size;
	if (minX >= maxX || size.width <= 0 || size.height <= 0) return CGRectNull;
	CGSize canvas = host.viewIfLoaded.bounds.size;
	if (fabs(size.width - canvas.width) > 1.0 || fabs(size.height - canvas.height) > 1.0) return CGRectNull;
	// Keep the faint antialiasing at either edge of the visible glyphs.
	CGFloat left = MAX(0.0, minX * size.width / width - 1.0);
	CGFloat right = MIN(size.width, maxX * size.width / width + 1.0);
	return CGRectMake(left, 0, right - left, size.height);
}

@implementation JikanInlineWidgetEstimate

- (void)refreshContentBounds {
	self.canvasSize = self.controller.viewIfLoaded.bounds.size;
	self.contentBounds = JikanNativeWidgetContentBounds(self.host);
	[self layout];
	[self.rootView setNeedsLayout];
}

- (void)requestMeasurement {
	if (!self.host || self.measurementPending) return;
	self.measurementPending = YES;
	NSUInteger generation = self.measurementGeneration;
	__weak JikanInlineWidgetEstimate *weakSelf = self;
	__weak UIViewController *weakHost = self.host;
	// Native snapshots capture live remote scenes as well as static widgets.
	// Refresh on attachment/content changes, outside layout passes.
	dispatch_async(dispatch_get_main_queue(), ^{
		JikanInlineWidgetEstimate *estimate = weakSelf;
		UIViewController *host = weakHost;
		if (!host || estimate.host != host || estimate.measurementGeneration != generation) return;
		void (^completion)(void) = ^{
			dispatch_async(dispatch_get_main_queue(), ^{
				JikanInlineWidgetEstimate *current = weakSelf;
				if (!current || current.host != weakHost || current.measurementGeneration != generation) return;
				current.measurementPending = NO;
				[current refreshContentBounds];
			});
		};
		SEL snapshot = NSSelectorFromString(@"snapshotContentWithTimeout:queue:completion:");
		if ([host respondsToSelector:snapshot]) {
			((void (*)(id, SEL, NSTimeInterval, dispatch_queue_t, id))objc_msgSend)(host, snapshot, 1.0,
				dispatch_get_main_queue(), completion);
		} else {
			completion();
		}
	});
}

- (BOOL)updateWithController:(UIViewController *)controller rootView:(UIView *)rootView dateView:(UIView *)dateView text:(NSString *)text {
	UIViewController *host = JikanWidgetObject(controller, @"widgetHostViewController");
	if (self.controller != controller || self.host != host) [self invalidate];
	UIView *wrapper = controller.viewIfLoaded;
	UIView *widget = host.viewIfLoaded;
	id parameters = JikanWidgetObject(host, @"inlineTextParameters");
	if (!text.length || !wrapper.window || !widget || widget.superview != wrapper || widget.hidden ||
		![wrapper isDescendantOfView:rootView] || !parameters) {
		[self invalidate];
		return NO;
	}
	if (!self.controller && (!CGRectEqualToRect(widget.frame, wrapper.bounds) || !CGAffineTransformIsIdentity(widget.transform))) return NO;
	BOOL attached = !self.controller;
	if (attached) {
		self.controller = controller;
		self.host = host;
		self.rootView = rootView;
		self.originalTransform = widget.transform;
		self.contentBounds = CGRectNull;
		self.canvasSize = wrapper.bounds.size;
		self.label = [UILabel new];
		self.label.userInteractionEnabled = NO;
		self.label.accessibilityIdentifier = @"jikan.inline-widget-estimate";
		objc_setAssociatedObject(controller, kJikanInlineWidgetEstimateKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(host, kJikanInlineWidgetEstimateKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[wrapper addSubview:self.label];
	}

	id specification = JikanWidgetObject(parameters, @"fontSpecification");
	NSNumber *size = JikanWidgetObject(specification, @"size");
	NSNumber *weight = JikanWidgetObject(specification, @"weight");
	UIFont *nativeFont = JikanWidgetObject(dateView, @"primaryFont");
	CGFloat pointSize = size.doubleValue > 0 ? size.doubleValue : (nativeFont ? nativeFont.pointSize : 20.0);
	NSString *fontName = JikanWidgetObject(specification, @"name");
	UIFont *font = fontName.length ? [UIFont fontWithName:fontName size:pointSize] : nil;
	if (!font) font = [UIFont systemFontOfSize:pointSize weight:weight ? weight.doubleValue : UIFontWeightSemibold];
	UIColor *color = JikanWidgetObject(dateView, @"primaryTextColor") ?: wrapper.tintColor;
	NSString *suffix = [NSString stringWithFormat:@"· %@", text];
	if (![self.label.text isEqualToString:suffix]) self.label.text = suffix;
	if (![self.label.font isEqual:font]) self.label.font = font;
	if (![self.label.textColor isEqual:color]) self.label.textColor = color;
	if (attached) {
		[self refreshContentBounds];
		[self requestMeasurement];
	}
	return [self layout];
}

- (BOOL)layout {
	UIView *wrapper = self.controller.viewIfLoaded;
	UIView *widget = self.host.viewIfLoaded;
	CGRect bounds = wrapper.bounds;
	CGSize size = [self.label sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGRectGetHeight(bounds))];
	CGFloat labelWidth = ceil(size.width);
	if (!wrapper || !widget || self.label.superview != wrapper) {
		[self invalidate];
		return NO;
	}
	if (self.layingOut) return !self.label.hidden;
	self.layingOut = YES;
	if (!CGSizeEqualToSize(self.canvasSize, bounds.size)) {
		self.contentBounds = CGRectNull;
		self.canvasSize = bounds.size;
		[self requestMeasurement];
	}
	CGFloat naturalWidth = CGRectGetWidth(self.contentBounds) + kJikanInlineEstimateSpacing + labelWidth;
	CGFloat scale = MIN(1.0, CGRectGetWidth(bounds) / MAX(1.0, naturalWidth));
	BOOL fits = !CGRectIsNull(self.contentBounds) && !CGRectIsEmpty(self.contentBounds) &&
		size.height <= CGRectGetHeight(bounds) && scale >= kJikanInlineEstimateMinimumScale;
	if (!fits) {
		// The pill remains available while native content bounds are missing,
		// or when the combined row cannot fit at a readable size.
		self.label.hidden = YES;
		widget.transform = self.originalTransform;
		widget.bounds = CGRectMake(0, 0, CGRectGetWidth(bounds), CGRectGetHeight(bounds));
		widget.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
		self.layingOut = NO;
		return NO;
	}
	BOOL rtl = wrapper.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
	CGFloat start = CGRectGetMidX(bounds) - naturalWidth * scale * 0.5;
	CGFloat widgetStart = start + (rtl ? (labelWidth + kJikanInlineEstimateSpacing) * scale : 0.0);
	CGFloat labelStart = start + (rtl ? 0.0 : (CGRectGetWidth(self.contentBounds) + kJikanInlineEstimateSpacing) * scale);
	// Preserve the native scene's full canvas and date/widget alignment.
	// Position its visible content as a centered group with the suffix;
	// scale both together only when necessary, instead of truncating the scene.
	widget.bounds = CGRectMake(0, 0, CGRectGetWidth(bounds), CGRectGetHeight(bounds));
	widget.transform = CGAffineTransformScale(self.originalTransform, scale, scale);
	widget.center = CGPointMake(widgetStart + (CGRectGetWidth(bounds) * 0.5 - CGRectGetMinX(self.contentBounds)) * scale,
		CGRectGetMidY(bounds));
	self.label.hidden = NO;
	self.label.bounds = CGRectMake(0, 0, labelWidth, CGRectGetHeight(bounds));
	self.label.transform = CGAffineTransformMakeScale(scale, scale);
	self.label.center = CGPointMake(labelStart + labelWidth * scale * 0.5, CGRectGetMidY(bounds));
	self.label.textAlignment = rtl ? NSTextAlignmentRight : NSTextAlignmentLeft;
	self.layingOut = NO;
	return YES;
}

- (void)invalidate {
	UIViewController *host = self.host;
	UIViewController *controller = self.controller;
	if (host) objc_setAssociatedObject(host, kJikanInlineWidgetEstimateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	if (controller) objc_setAssociatedObject(controller, kJikanInlineWidgetEstimateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	self.measurementGeneration++;
	self.measurementPending = NO;
	[self.label removeFromSuperview];
	if (host) {
		UIView *widget = host.viewIfLoaded;
		UIView *wrapper = controller.viewIfLoaded;
		if (wrapper && widget.superview == wrapper) {
			widget.transform = self.originalTransform;
			widget.bounds = CGRectMake(0, 0, CGRectGetWidth(wrapper.bounds), CGRectGetHeight(wrapper.bounds));
			widget.center = CGPointMake(CGRectGetMidX(wrapper.bounds), CGRectGetMidY(wrapper.bounds));
		}
		[widget setNeedsLayout];
	}
	self.controller = nil;
	self.host = nil;
	self.rootView = nil;
	self.label = nil;
	self.contentBounds = CGRectNull;
}

+ (void)nativeContentDidChangeForHost:(UIViewController *)host {
	JikanInlineWidgetEstimate *estimate = objc_getAssociatedObject(host, kJikanInlineWidgetEstimateKey);
	[estimate requestMeasurement];
}

+ (void)layoutInController:(UIViewController *)controller {
	JikanInlineWidgetEstimate *estimate = objc_getAssociatedObject(controller, kJikanInlineWidgetEstimateKey);
	if (!estimate) return;
	if (![controller.viewIfLoaded isDescendantOfView:estimate.rootView]) [estimate invalidate];
	else
		[estimate layout];
}

@end

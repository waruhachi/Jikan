#import "JikanInlineEstimateAdapter.h"

static const void *kJikanInlineEstimateAdapterKey = &kJikanInlineEstimateAdapterKey;

@interface JikanInlineEstimateAdapter ()
@property (nonatomic, weak) UIView *rootView;
@property (nonatomic, weak) UIView *dateView;
@property (nonatomic, copy) NSString *estimateText;
@property (nonatomic, strong) JikanInlineWidgetEstimate *widgetEstimate;
@end

static BOOL JikanInlineViewBelongsToRoot(UIView *view, UIView *root) {
	// Native clock transitions can make an ancestor transparent while this
	// view still supplies the displayed date. Do not filter by ancestor alpha.
	if (!view.window || CGRectIsEmpty(view.bounds)) return NO;
	for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
		SEL editing = NSSelectorFromString(@"usesEditingLayout");
		if ([ancestor respondsToSelector:editing] && ((BOOL (*)(id, SEL))objc_msgSend)(ancestor, editing)) return NO;
		if (ancestor == root) return YES;
	}
	return NO;
}

static UIView *JikanFindInlineDateView(UIView *root) {
	if (@available(iOS 16.0, *)) {
		Class dateClass = NSClassFromString(@"CSProminentSubtitleDateView");
		if (!dateClass || ![dateClass instancesRespondToSelector:NSSelectorFromString(@"_dateString")] ||
			![dateClass instancesRespondToSelector:NSSelectorFromString(@"_updateLabel")]) return nil;
		NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
		while (pending.count) {
			UIView *view = pending.lastObject;
			[pending removeLastObject];
			if ([view isKindOfClass:dateClass] && JikanInlineViewBelongsToRoot(view, root)) return view;
			[pending addObjectsFromArray:view.subviews];
		}
	}
	return nil;
}

static UIViewController *JikanFindInlineWidgetController(UIView *root) {
	Class wrapperClass = NSClassFromString(@"CSComplicationWrapperViewController");
	Class inlineClass = NSClassFromString(@"CSInlineWidgetContainerViewController");
	Class complicationClass = NSClassFromString(@"CSComplicationContainerViewController");
	if (!wrapperClass) return nil;
	NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
	while (pending.count) {
		UIView *view = pending.lastObject;
		[pending removeLastObject];
		UIResponder *responder = view.nextResponder;
		if ([responder isKindOfClass:wrapperClass] && !view.hidden && JikanInlineViewBelongsToRoot(view, root)) {
			UIViewController *controller = (UIViewController *)responder;
			UIViewController *container = controller.parentViewController;
			if (inlineClass && [container isKindOfClass:inlineClass]) return controller;
			// iOS 16 shares this container with the widgets below the clock.
			// Its native descriptor identifies the single inline date-row widget.
			SEL descriptor = NSSelectorFromString(@"_inlineComplicationDescriptorIfSolo");
			if (complicationClass && [container isKindOfClass:complicationClass] &&
				[container respondsToSelector:descriptor] && ((id (*)(id, SEL))objc_msgSend)(container, descriptor)) return controller;
		}
		[pending addObjectsFromArray:view.subviews];
	}
	return nil;
}

static void JikanRefreshInlineDateView(UIView *view) {
	if (!view) return;
	SEL selector = NSSelectorFromString(@"_updateLabel");
	if ([view respondsToSelector:selector]) ((void (*)(id, SEL))objc_msgSend)(view, selector);
	[view setNeedsLayout];
	[view.superview setNeedsLayout];
}

static UILabel *JikanInlineDateLabel(UIView *view) {
	SEL selector = NSSelectorFromString(@"textLabel");
	if (![view respondsToSelector:selector]) return nil;
	id label = ((id (*)(id, SEL))objc_msgSend)(view, selector);
	return [label isKindOfClass:UILabel.class] ? label : nil;
}

static BOOL JikanInlineDateShowsEstimate(UIView *view, NSString *text) {
	NSString *renderedText = JikanInlineDateLabel(view).text;
	NSString *suffix = [NSString stringWithFormat:@" · %@", text];
	return view && !view.hidden && text.length && renderedText.length &&
		[renderedText rangeOfString:suffix].location != NSNotFound;
}

@implementation JikanInlineEstimateAdapter

- (instancetype)initWithRootView:(UIView *)rootView {
	if ((self = [super init])) {
		_rootView = rootView;
		_widgetEstimate = [JikanInlineWidgetEstimate new];
	}
	return self;
}

- (BOOL)updateWithState:(JikanPresentationState *)state {
	BOOL requested = (state.settings.showEstimateBesideDate || state.previewActive) && state.shouldShowPlatter;
	NSString *text = nil;
	if (requested) {
		if (state.usesPreviewContent) {
			text = JikanLocalizedString(@"jikan.platter.preview.eta", @"1 hr 23 min");
		} else if (state.snapshot.targetReached && state.settings.showAfterFullCharge) {
			text = [NSString stringWithFormat:@"%ld%% %@", (long)state.snapshot.displayPercent, JikanLocalizedString(@"jikan.platter.label.charged", @"charged")];
		} else {
			text = state.snapshot.timeString;
		}
	}
	UIView *dateView = text.length && self.rootView ? JikanFindInlineDateView(self.rootView) : nil;
	UIViewController *widgetController = text.length && self.rootView ? JikanFindInlineWidgetController(self.rootView) : nil;
	BOOL showingWidgetEstimate = NO;
	if (widgetController) {
		showingWidgetEstimate = [self.widgetEstimate updateWithController:widgetController rootView:self.rootView dateView:dateView text:text];
	} else {
		[self.widgetEstimate invalidate];
	}
	// An inline widget replaces the date view but keeps it in the hierarchy,
	// hidden. Do not report that hidden label as a successful presentation.
	if (!text.length || widgetController || dateView.hidden) dateView = nil;
	if (self.dateView == dateView && [self.estimateText isEqualToString:text]) return JikanInlineDateShowsEstimate(dateView, text) || showingWidgetEstimate;
	if (!self.dateView && !dateView) return showingWidgetEstimate;

	UIView *previousView = self.dateView;
	if (previousView != dateView) {
		if (previousView) objc_setAssociatedObject(previousView, kJikanInlineEstimateAdapterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		self.dateView = dateView;
		if (dateView) objc_setAssociatedObject(dateView, kJikanInlineEstimateAdapterKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	self.estimateText = dateView ? text : nil;
	if (previousView != dateView) JikanRefreshInlineDateView(previousView);
	JikanRefreshInlineDateView(dateView);
	return JikanInlineDateShowsEstimate(dateView, text) || showingWidgetEstimate;
}

- (void)invalidate {
	UIView *dateView = self.dateView;
	if (dateView) objc_setAssociatedObject(dateView, kJikanInlineEstimateAdapterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	self.dateView = nil;
	self.estimateText = nil;
	JikanRefreshInlineDateView(dateView);
	[self.widgetEstimate invalidate];
}

+ (NSString *)dateString:(NSString *)dateString forView:(UIView *)dateView {
	JikanInlineEstimateAdapter *adapter = objc_getAssociatedObject(dateView, kJikanInlineEstimateAdapterKey);
	// Alter only the date view attached to this Cover Sheet, leaving wallpaper
	// editing and other native date views alone. Native formatting remains in
	// charge of the date, font, color, and midnight updates.
	if (!adapter.estimateText.length || dateView.hidden || !JikanInlineViewBelongsToRoot(dateView, adapter.rootView) || !dateString.length) return dateString;
	return [NSString stringWithFormat:@"%@ · %@", dateString, adapter.estimateText];
}

#pragma mark - LiquidAss compatibility

// Observed with LiquidAss 0.1.2t on iOS 16.3.1: its UILabel setText: and
// setAttributedText: hooks replace the appended estimate with a shortened date.
// Revisit this fallback when LiquidAss changes its date handling. The ordinary
// _dateString hook and rendered-text verification remain independent of it.
+ (void)applyLiquidAssCompatibilityToDateView:(UIView *)dateView {
	JikanInlineEstimateAdapter *adapter = objc_getAssociatedObject(dateView, kJikanInlineEstimateAdapterKey);
	if (!adapter.estimateText.length || dateView.hidden || !JikanInlineViewBelongsToRoot(dateView, adapter.rootView) ||
		JikanInlineDateShowsEstimate(dateView, adapter.estimateText)) return;
	UILabel *label = JikanInlineDateLabel(dateView);
	if (!label.text.length) return;
	// Bypass the conflicting setters only when the estimate is missing. Keep
	// the rendered date and native font/color on this associated date label.
	SEL setter = NSSelectorFromString(@"_setText:");
	if (![label respondsToSelector:setter]) return;
	NSString *combined = [NSString stringWithFormat:@"%@ · %@", label.text, adapter.estimateText];
	((void (*)(id, SEL, id))objc_msgSend)(label, setter, combined);
	[label setNeedsLayout];
	[dateView setNeedsLayout];
}

@end

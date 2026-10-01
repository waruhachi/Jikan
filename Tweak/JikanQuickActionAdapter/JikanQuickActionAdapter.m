#import "JikanQuickActionAdapter.h"

static const void *kTTQuickActionOriginalHiddenKey = &kTTQuickActionOriginalHiddenKey;
static const void *kTTQuickActionHiddenByJikanKey = &kTTQuickActionHiddenByJikanKey;
static const void *kTTQuickActionInternalHiddenWriteKey = &kTTQuickActionInternalHiddenWriteKey;

@interface JikanQuickActionAdapter ()
@property (nonatomic, weak) UIView *rootView;
@property (nonatomic, assign) BOOL styleCaptured;
@end

static UIView *TTFindQuickActionsView(UIView *root) {
	if (!root) return nil;
	Class quickActionsClass = NSClassFromString(@"CSQuickActionsView");
	if (!quickActionsClass) return nil;

	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
	while (stack.count) {
		UIView *view = stack.lastObject;
		[stack removeLastObject];
		if ([view isKindOfClass:quickActionsClass]) {
			return (UIView *)view;
		}
		for (UIView *sub in view.subviews) {
			[stack addObject:sub];
		}
	}
	return nil;
}

static id TTObjectForSelector(id target, NSString *selectorName) {
	if (!target || selectorName.length == 0) return nil;
	SEL selector = NSSelectorFromString(selectorName);
	if (!selector || ![target respondsToSelector:selector]) return nil;

	@try {
		NSMethodSignature *signature = [target methodSignatureForSelector:selector];
		if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
		return ((id (*)(id, SEL))objc_msgSend)(target, selector);
	}
	@catch (__unused NSException *exception) {
		return nil;
	}
}

static UIView *TTViewForSelector(id target, NSString *selectorName) {
	id object = TTObjectForSelector(target, selectorName);
	return [object isKindOfClass:[UIView class]] ? (UIView *)object : nil;
}

static BOOL TTResolveQuickActionButtons(UIView *quickActions, UIView **leadingOut, UIView **trailingOut) {
	if (leadingOut) *leadingOut = nil;
	if (trailingOut) *trailingOut = nil;
	if (!quickActions) return NO;

	UIView *leading = nil;
	UIView *trailing = nil;
	id container = TTObjectForSelector(quickActions, @"buttonContainerView");
	if (container) {
		leading = TTViewForSelector(container, @"leadingButton");
		trailing = TTViewForSelector(container, @"trailingButton");
	}

	if (!leading) leading = TTViewForSelector(quickActions, @"flashlightButton");
	if (!trailing) trailing = TTViewForSelector(quickActions, @"cameraButton");

	if (!leading || !trailing) {
		id buttonsObject = TTObjectForSelector(quickActions, @"buttons");
		if ([buttonsObject isKindOfClass:[NSArray class]]) {
			NSMutableArray<UIView *> *buttonViews = [NSMutableArray array];
			for (id object in (NSArray *)buttonsObject) {
				if (![object isKindOfClass:[UIView class]]) continue;
				UIView *view = (UIView *)object;
				if (![view isDescendantOfView:quickActions]) continue;
				if (![buttonViews containsObject:view]) [buttonViews addObject:view];
			}

			[buttonViews sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
				CGRect aRect = [a convertRect:a.bounds toView:quickActions];
				CGRect bRect = [b convertRect:b.bounds toView:quickActions];
				CGFloat aX = CGRectGetMidX(aRect);
				CGFloat bX = CGRectGetMidX(bRect);
				if (aX < bX) return NSOrderedAscending;
				if (aX > bX) return NSOrderedDescending;
				return NSOrderedSame;
			}];

			for (UIView *view in buttonViews) {
				if (!leading && view != trailing) leading = view;
			}
			for (UIView *view in buttonViews.reverseObjectEnumerator) {
				if (!trailing && view != leading) trailing = view;
			}
		}
	}
	if (leading == trailing) trailing = nil;

	if (leadingOut) *leadingOut = leading;
	if (trailingOut) *trailingOut = trailing;
	return leading || trailing;
}

static void TTSetQuickActionControlHidden(UIView *control, BOOL shouldHide) {
	if (!control) return;
	BOOL hiddenByJikan = [objc_getAssociatedObject(control, kTTQuickActionHiddenByJikanKey) boolValue];

	if (shouldHide) {
		if (!hiddenByJikan) {
			objc_setAssociatedObject(control, kTTQuickActionOriginalHiddenKey, @(control.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			objc_setAssociatedObject(control, kTTQuickActionHiddenByJikanKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		objc_setAssociatedObject(control, kTTQuickActionInternalHiddenWriteKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		control.hidden = YES;
		objc_setAssociatedObject(control, kTTQuickActionInternalHiddenWriteKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	if (!hiddenByJikan) return;
	NSNumber *originalHidden = (NSNumber *)objc_getAssociatedObject(control, kTTQuickActionOriginalHiddenKey);
	objc_setAssociatedObject(control, kTTQuickActionOriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(control, kTTQuickActionHiddenByJikanKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	if (originalHidden) control.hidden = originalHidden.boolValue;
}

static void TTSetQuickActionButtonsHidden(UIView *quickActions, BOOL shouldHide) {
	UIView *leading = nil;
	UIView *trailing = nil;
	if (!TTResolveQuickActionButtons(quickActions, &leading, &trailing)) return;

	TTSetQuickActionControlHidden(leading, shouldHide);
	if (trailing && trailing != leading) TTSetQuickActionControlHidden(trailing, shouldHide);
}

static UIView *TTPlatterHost(UIView *coverSheet) {
	UIView *actions = TTFindQuickActionsView(coverSheet);
	for (UIView *parent = actions.superview; parent && parent != coverSheet; parent = parent.superview) {
		if ([NSStringFromClass(parent.class) isEqualToString:@"CSCoverSheetContentsContainerView"]) return parent;
	}
	// Older releases may not expose that container. Share the buttons' moving
	// parent when present; keep the root only until the content is installed.
	return actions.superview ?: coverSheet;
}

static UIView *TTQuickActionVisibleBackground(UIView *button) {
	if (@available(iOS 26.0, *)) {
		UIView *background = TTViewForSelector(button, @"backgroundView");
		if (background && !CGRectIsEmpty(background.bounds)) return background;
		for (UIView *child in button.subviews) {
			id effect = TTObjectForSelector(child, @"_glassEffect");
			if ([effect isKindOfClass:NSClassFromString(@"UIGlassEffect")] && !CGRectIsEmpty(child.bounds)) return child;
		}
	}

	for (UIView *child in button.subviews) {
		if ([child isKindOfClass:[UIVisualEffectView class]] && !CGRectIsEmpty(child.bounds)) return child;
		for (UIView *grandchild in child.subviews) {
			if ([grandchild isKindOfClass:[UIVisualEffectView class]] && !CGRectIsEmpty(grandchild.bounds)) return grandchild;
		}
	}
	return button;
}

static BOOL TTQuickActionButtonFramesInView(UIView *coverSheet, UIView *host, CGRect *leadingRectOut, CGRect *trailingRectOut) {
	UIView *quickActions = TTFindQuickActionsView(coverSheet);
	UIView *leading = nil;
	UIView *trailing = nil;
	if (!TTResolveQuickActionButtons(quickActions, &leading, &trailing) || !leading || !trailing) return NO;
	if (![leading isDescendantOfView:coverSheet] || ![trailing isDescendantOfView:coverSheet]) return NO;

	leading = TTQuickActionVisibleBackground(leading);
	trailing = TTQuickActionVisibleBackground(trailing);
	CGRect leadingRect = [leading convertRect:leading.bounds toView:host];
	CGRect trailingRect = [trailing convertRect:trailing.bounds toView:host];
	if (CGRectIsEmpty(leadingRect) || CGRectIsEmpty(trailingRect)) return NO;
	if (!isfinite(leadingRect.origin.x) || !isfinite(leadingRect.origin.y) || !isfinite(leadingRect.size.width) || !isfinite(leadingRect.size.height) ||
		!isfinite(trailingRect.origin.x) || !isfinite(trailingRect.origin.y) || !isfinite(trailingRect.size.width) || !isfinite(trailingRect.size.height)) return NO;
	if (CGRectGetMidX(leadingRect) > CGRectGetMidX(trailingRect)) {
		CGRect swap = leadingRect;
		leadingRect = trailingRect;
		trailingRect = swap;
	}
	if (leadingRectOut) *leadingRectOut = leadingRect;
	if (trailingRectOut) *trailingRectOut = trailingRect;
	return YES;
}

static UIView *TTFindNearestQuickActionMaterialView(UIView *root) {
	if (!root) return nil;
	UIView *quickActions = TTFindQuickActionsView(root);
	if (!quickActions) return nil;
	UIView *leading = nil;
	UIView *trailing = nil;
	TTResolveQuickActionButtons(quickActions, &leading, &trailing);
	NSMutableArray<UIView *> *candidates = [NSMutableArray array];
	if (leading) [candidates addObject:leading];
	if (trailing && trailing != leading) [candidates addObject:trailing];
	for (UIView *button in candidates) {
		if (!button) continue;
		UIView *backgroundEffectView = TTViewForSelector(button, @"backgroundEffectView");
		UIView *backgroundView = TTViewForSelector(button, @"backgroundView");

		NSMutableArray<UIView *> *buttonStack = [NSMutableArray arrayWithObject:button];
		if (backgroundView) [buttonStack addObject:backgroundView];
		if (backgroundEffectView) [buttonStack addObject:backgroundEffectView];
		while (buttonStack.count) {
			UIView *v = buttonStack.lastObject;
			[buttonStack removeLastObject];
			if ([v isKindOfClass:[UIVisualEffectView class]] && ((UIVisualEffectView *)v).effect) return v;
			if ([NSStringFromClass(v.class) containsString:@"MTMaterial"]) return v;
			for (UIView *sub in v.subviews) {
				[buttonStack addObject:sub];
			}
		}
	}
	return nil;
}

@implementation JikanQuickActionAdapter

+ (Class)visibilityControlClass {
	Class quickButtonClass = NSClassFromString(@"CSQuickActionsButton");
	Class prominentClass = NSClassFromString(@"CSProminentButtonControl");
	return prominentClass && [quickButtonClass isSubclassOfClass:prominentClass] ? prominentClass : quickButtonClass;
}

+ (BOOL)hiddenValueForControl:(UIView *)control requestedHidden:(BOOL)hidden {
	if ([objc_getAssociatedObject(control, kTTQuickActionHiddenByJikanKey) boolValue] && ![objc_getAssociatedObject(control, kTTQuickActionInternalHiddenWriteKey) boolValue]) {
		objc_setAssociatedObject(control, kTTQuickActionOriginalHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		hidden = YES;
	}
	return hidden;
}

+ (void)setButtonsInView:(UIView *)quickActions hidden:(BOOL)hidden {
	TTSetQuickActionButtonsHidden(quickActions, hidden);
}

- (instancetype)initWithRootView:(UIView *)rootView {
	if ((self = [super init])) _rootView = rootView;
	return self;
}

- (void)setButtonsHidden:(BOOL)hidden {
	TTSetQuickActionButtonsHidden(TTFindQuickActionsView(self.rootView), hidden);
}

- (UIView *)platterHostView {
	return TTPlatterHost(self.rootView);
}

- (BOOL)getButtonFramesInView:(UIView *)host leadingRect:(CGRect *)leadingRect trailingRect:(CGRect *)trailingRect {
	return TTQuickActionButtonFramesInView(self.rootView, host, leadingRect, trailingRect);
}

- (void)invalidateStyle {
	self.styleCaptured = NO;
}

- (void)applyStyleToPlatter:(JikanPlatterView *)platter {
	UIView *coverSheet = self.rootView;
	if (!coverSheet || !platter) return;
	UIView *quickActions = TTFindQuickActionsView(coverSheet);
	UIView *leading = nil;
	UIView *trailing = nil;
	TTResolveQuickActionButtons(quickActions, &leading, &trailing);
	UIView *referenceButton = leading ?: trailing;
	if (@available(iOS 26.0, *)) {
		// Glass is attached to the controls' child views, rather than a
		// UIVisualEffectView. Refresh the recipe as wallpaper traits change.
		if ([platter applyQuickActionGlassFromView:leading] ||
			[platter applyQuickActionGlassFromView:trailing]) return;
	}
	if (self.styleCaptured) return;

	UIView *sourceMaterialView = TTFindNearestQuickActionMaterialView(coverSheet);
	if (!sourceMaterialView) return;

	if ([sourceMaterialView isKindOfClass:[UIVisualEffectView class]]) {
		UIVisualEffectView *sourceEffect = (UIVisualEffectView *)sourceMaterialView;
		[platter applyQuickActionVisualEffect:sourceEffect.effect];
		UIView *styleSource = sourceMaterialView.superview ?: (referenceButton ?: sourceMaterialView);
		[platter applyQuickActionBackgroundStyleFromView:styleSource];
		if (!self.styleCaptured) {
			self.styleCaptured = YES;
		}
		return;
	}

	[platter applyQuickActionBackgroundStyleFromView:sourceMaterialView];
	if (!self.styleCaptured) {
		self.styleCaptured = YES;
	}
}

@end

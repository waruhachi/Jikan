#import "JikanFocusIndicatorVisibility.h"

@implementation JikanFocusIndicatorVisibility

// The hidden value the system last asked for, so turning the option off restores it.
+ (NSMapTable<UIView *, NSNumber *> *)requestedVisibility {
	static NSMapTable<UIView *, NSNumber *> *visibility;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ visibility = [NSMapTable weakToStrongObjectsMapTable]; });
	return visibility;
}

+ (BOOL)shouldHide {
	return [JikanPresentationStore sharedInstance].state.shouldHideFocusIndicator;
}

+ (BOOL)hiddenValueForView:(UIView *)view requested:(BOOL)hidden {
	NSAssert(NSThread.isMainThread, @"Focus indicator visibility belongs to the main thread");
	[[self requestedVisibility] setObject:@(hidden) forKey:view];
	return hidden || [self shouldHide];
}

+ (void)updateView:(UIView *)view {
	if (!view) return;
	NSNumber *requested = [[self requestedVisibility] objectForKey:view];
	// The setHidden: hook records the request and applies the override.
	view.hidden = requested ? requested.boolValue : view.hidden;
}

+ (void)refreshTrackedViews {
	for (UIView *view in [self requestedVisibility].keyEnumerator.allObjects) [self updateView:view];
}

@end

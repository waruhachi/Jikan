#import "JikanUnlockTextVisibility.h"

@implementation JikanUnlockTextVisibility

+ (NSHashTable<UIView *> *)trackedLabels {
	static NSHashTable<UIView *> *labels;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ labels = [NSHashTable weakObjectsHashTable]; });
	return labels;
}

+ (NSMapTable<UIView *, NSNumber *> *)originalVisibility {
	static NSMapTable<UIView *, NSNumber *> *visibility;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ visibility = [NSMapTable weakToStrongObjectsMapTable]; });
	return visibility;
}

+ (void)updateLabel:(UIView *)label {
	if (!label) return;
	NSAssert(NSThread.isMainThread, @"Unlock instruction visibility belongs to the main thread");
	[[self trackedLabels] addObject:label];
	NSMapTable<UIView *, NSNumber *> *visibility = [self originalVisibility];
	BOOL shouldHide = [JikanPresentationStore sharedInstance].state.settings.enabled &&
		[JikanPresentationStore sharedInstance].state.settings.hideSwipeToUnlockText;
	NSNumber *originalHidden = [visibility objectForKey:label];
	if (shouldHide) {
		if (!originalHidden) [visibility setObject:@(label.hidden) forKey:label];
		label.hidden = YES;
	} else if (originalHidden) {
		label.hidden = originalHidden.boolValue;
		[visibility removeObjectForKey:label];
	}
}

+ (void)updateModernContainer:(UIView *)container {
	id label = nil;
	@try {
		label = [container valueForKey:@"_callToActionLabel"];
	} @catch (__unused NSException *exception) {
		return;
	}
	if ([label isKindOfClass:UIView.class]) [self updateLabel:label];
}

+ (void)updateLegacyLabel:(UIView *)label {
	[self updateLabel:label];
}

+ (void)refreshTrackedLabels {
	for (UIView *label in [self trackedLabels].allObjects) [self updateLabel:label];
}

@end

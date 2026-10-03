#import "JikanGlassEffect.h"

BOOL JikanConfigureLiquidGlass(UIVisualEffectView *view) {
	if (@available(iOS 26.0, *)) {
		// Resolve the public UIKit APIs at runtime so the tweak still builds
		// with its older SDK and loads on iOS versions without Liquid Glass.
		Class glassClass = NSClassFromString(@"UIGlassEffect");
		Class cornerClass = NSClassFromString(@"UICornerConfiguration");
		SEL effectSelector = NSSelectorFromString(@"effectWithStyle:");
		SEL capsuleSelector = NSSelectorFromString(@"capsuleConfiguration");
		SEL cornerSetter = NSSelectorFromString(@"setCornerConfiguration:");
		if (![glassClass respondsToSelector:effectSelector] ||
			![cornerClass respondsToSelector:capsuleSelector] ||
			![view respondsToSelector:cornerSetter]) return NO;
		UIVisualEffect *effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassClass, effectSelector, 0);	 // UIGlassEffectStyleRegular
		id corners = ((id (*)(id, SEL))objc_msgSend)(cornerClass, capsuleSelector);
		if (![effect isKindOfClass:UIVisualEffect.class] || !corners) return NO;
		view.effect = effect;
		((void (*)(id, SEL, id))objc_msgSend)(view, cornerSetter, corners);
		return YES;
	}
	return NO;
}

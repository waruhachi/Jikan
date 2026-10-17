#import "JikanDeviceCapabilities.h"

BOOL JikanDeviceSupportsQuickActionButtons(void) {
	// Stock Lock Screen quick actions use the Face ID iPhone layout. Query
	// hardware support rather than the current visibility of its controls.
	return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone && MGGetBoolAnswer(CFSTR("PearlIDCapability"));
}

BOOL JikanDeviceSupportsInlineEstimate(void) {
	// iOS 14/15 use SBFLockScreenDateSubtitleView; later releases use
	// CSProminentSubtitleDateView or the native inline widget container.
	if (@available(iOS 14.0, *)) return YES;
	return NO;
}
